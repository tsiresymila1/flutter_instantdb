part of 'triple_store.dart';

/// Private apply/transaction helpers for [TripleStore].
///
/// Moved verbatim from `triple_store.dart` into a `part of` extension to keep
/// the main class file focused. As an extension in the same library, it retains
/// access to the store's private fields (`_db`, `_schema`, `_changeController`)
/// and private methods. No logic was changed — only relocated.
extension _TripleStoreApply on TripleStore {
  /// Resolve any LookupRef references in operation data to actual entity IDs
  Future<List<Operation>> _resolveLookupReferences(
    List<Operation> operations,
  ) async {
    final resolvedOperations = <Operation>[];

    for (final operation in operations) {
      if (operation.data == null) {
        resolvedOperations.add(operation);
        continue;
      }

      final resolvedData = <String, dynamic>{};
      bool hasChanges = false;

      for (final entry in operation.data!.entries) {
        final value = entry.value;
        if (value is LookupRef) {
          // Resolve the lookup reference
          final entityId = await resolveLookup(
            value.entityType,
            value.attribute,
            value.value,
          );
          if (entityId != null) {
            resolvedData[entry.key] = entityId;
            hasChanges = true;
          } else {
            throw InstantException(
              message:
                  'Could not resolve lookup reference: ${value.entityType}.${value.attribute} = ${value.value}',
              code: 'lookup_failed',
            );
          }
        } else {
          resolvedData[entry.key] = value;
        }
      }

      if (hasChanges) {
        resolvedOperations.add(
          Operation(
            type: operation.type,
            entityType: operation.entityType,
            entityId: operation.entityId,
            data: resolvedData,
            options: operation.options,
          ),
        );
      } else {
        resolvedOperations.add(operation);
      }
    }

    return resolvedOperations;
  }

  Future<bool> _entityExists(DatabaseExecutor txn, String entityId) async {
    final rows = await txn.query(
      'triples',
      where: 'entity_id = ? AND retracted = FALSE',
      whereArgs: [entityId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Persist a `__type` triple for the entity if its type is known and not
  /// already recorded. This makes upserted entities discoverable by type
  /// queries (update/merge are upserts by default).
  Future<void> _ensureEntityType(
    DatabaseExecutor txn,
    Operation operation,
    String txId,
    DateTime now,
    bool isLocalOnly,
  ) async {
    final entityType = operation.entityType;
    if (entityType.isEmpty || entityType == 'unknown') return;

    // If the operation's own data already carries __type, the main apply loop
    // will insert it — avoid a duplicate insert here.
    if (operation.data?.containsKey('__type') ?? false) return;

    final existing = await txn.query(
      'triples',
      where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
      whereArgs: [operation.entityId, '__type'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await txn.insert('triples', {
      'entity_id': operation.entityId,
      'attribute': '__type',
      'value': jsonEncode(entityType),
      'tx_id': txId,
      'created_at': now.millisecondsSinceEpoch,
      'retracted': 0,
      'is_local_only': isLocalOnly ? 1 : 0,
    });
  }

  Future<List<TripleChange>> _applyOperationWithChanges(
    DatabaseExecutor txn,
    Operation operation,
    String txId,
  ) async {
    final changes = <TripleChange>[];
    final now = DateTime.now();

    // Determine if this entity type is local-only
    final isLocalOnly = _schema?.isLocalOnly(operation.entityType) ?? false;

    switch (operation.type) {
      case OperationType.add:
        // Add operation with data map
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
              'is_local_only': isLocalOnly ? 1 : 0,
            });

            changes.add(
              TripleChange(
                type: ChangeType.add,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                  isLocalOnly: isLocalOnly,
                ),
              ),
            );
          }
        }
        break;

      case OperationType.update:
        if (operation.options?['upsert'] == false &&
            !await _entityExists(txn, operation.entityId)) {
          break; // strict mode: do not create a missing entity
        }
        // Ensure the entity type is recorded so the (possibly newly upserted)
        // entity is discoverable by type queries.
        await _ensureEntityType(txn, operation, txId, now, isLocalOnly);
        // Update operation with data map
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            // Retract old value
            await txn.update(
              'triples',
              {'retracted': 1},
              where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
              whereArgs: [operation.entityId, entry.key],
            );

            // Add new value
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
              'is_local_only': isLocalOnly ? 1 : 0,
            });

            changes.add(
              TripleChange(
                type: ChangeType.add,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                  isLocalOnly: isLocalOnly,
                ),
              ),
            );
          }
        }
        break;

      case OperationType.merge:
        if (operation.options?['upsert'] == false &&
            !await _entityExists(txn, operation.entityId)) {
          break;
        }
        await _ensureEntityType(txn, operation, txId, now, isLocalOnly);
        // Merge operation - deep merge with existing data
        final existingTriples = await txn.query(
          'triples',
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );

        final existingData = <String, dynamic>{};
        for (final triple in existingTriples) {
          existingData[triple['attribute'] as String] = jsonDecode(
            triple['value'] as String,
          );
        }

        if (operation.data != null) {
          final mergedData = deepMerge(existingData, operation.data!);

          // Update changed fields
          for (final entry in mergedData.entries) {
            if (existingData[entry.key] != entry.value) {
              // Retract old value
              await txn.update(
                'triples',
                {'retracted': 1},
                where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
                whereArgs: [operation.entityId, entry.key],
              );

              // Add merged value
              await txn.insert('triples', {
                'entity_id': operation.entityId,
                'attribute': entry.key,
                'value': jsonEncode(entry.value),
                'tx_id': txId,
                'created_at': now.millisecondsSinceEpoch,
                'retracted': 0,
                'is_local_only': isLocalOnly ? 1 : 0,
              });

              changes.add(
                TripleChange(
                  type: ChangeType.add,
                  triple: Triple(
                    entityId: operation.entityId,
                    attribute: entry.key,
                    value: entry.value,
                    txId: txId,
                    createdAt: now,
                    isLocalOnly: isLocalOnly,
                  ),
                ),
              );
            }
          }
        }
        break;

      case OperationType.link:
        // Link operation - create relationship triples
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            // Add link triple
            await txn.insert('triples', {
              'entity_id': operation.entityId,
              'attribute': entry.key,
              'value': jsonEncode(entry.value),
              'tx_id': txId,
              'created_at': now.millisecondsSinceEpoch,
              'retracted': 0,
              'is_local_only': isLocalOnly ? 1 : 0,
            });

            changes.add(
              TripleChange(
                type: ChangeType.add,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                  isLocalOnly: isLocalOnly,
                ),
              ),
            );
          }
        }
        break;

      case OperationType.unlink:
        // Unlink operation - remove relationship triples
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.update(
              'triples',
              {'retracted': 1},
              where:
                  'entity_id = ? AND attribute = ? AND value = ? AND retracted = FALSE',
              whereArgs: [
                operation.entityId,
                entry.key,
                jsonEncode(entry.value),
              ],
            );

            changes.add(
              TripleChange(
                type: ChangeType.retract,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                  retracted: true,
                  isLocalOnly: isLocalOnly,
                ),
              ),
            );
          }
        }
        break;

      case OperationType.delete:
        // Get all triples for this entity before deletion
        final triplesToDelete = await txn.query(
          'triples',
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );

        // Retract all triples for this entity
        await txn.update(
          'triples',
          {'retracted': 1},
          where: 'entity_id = ? AND retracted = FALSE',
          whereArgs: [operation.entityId],
        );

        // Emit change events for each retracted triple
        for (final tripleData in triplesToDelete) {
          changes.add(
            TripleChange(
              type: ChangeType.retract,
              triple: Triple(
                entityId: tripleData['entity_id'] as String,
                attribute: tripleData['attribute'] as String,
                value: jsonDecode(tripleData['value'] as String),
                txId: txId,
                createdAt: DateTime.fromMillisecondsSinceEpoch(
                  tripleData['created_at'] as int,
                ),
                retracted: true,
                isLocalOnly: ((tripleData['is_local_only'] as int?) ?? 0) == 1,
              ),
            ),
          );
        }
        break;

      case OperationType.retract:
        // Legacy retract operation for backward compatibility
        if (operation.data != null) {
          for (final entry in operation.data!.entries) {
            await txn.update(
              'triples',
              {'retracted': 1},
              where:
                  'entity_id = ? AND attribute = ? AND value = ? AND retracted = FALSE',
              whereArgs: [
                operation.entityId,
                entry.key,
                jsonEncode(entry.value),
              ],
            );

            changes.add(
              TripleChange(
                type: ChangeType.retract,
                triple: Triple(
                  entityId: operation.entityId,
                  attribute: entry.key,
                  value: entry.value,
                  txId: txId,
                  createdAt: now,
                  retracted: true,
                  isLocalOnly: isLocalOnly,
                ),
              ),
            );
          }
        }
        break;
    }

    return changes;
  }

  /// Mark multiple transactions as failed
  Future<void> _markTransactionsAsFailed(List<String> txIds) async {
    if (txIds.isEmpty) return;

    final batch = _db.batch();
    for (final txId in txIds) {
      batch.update(
        'transactions',
        {'status': TransactionStatus.failed.name, 'synced': 0},
        where: 'id = ?',
        whereArgs: [txId],
      );
    }
    await batch.commit();
  }
}
