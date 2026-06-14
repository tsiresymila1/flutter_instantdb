import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:uuid/uuid.dart';

import '../core/types.dart';
import '../core/logging_config.dart';
import '../schema/schema.dart';
import 'database_factory.dart';
import 'storage_interface.dart';
import 'triple_query_eval.dart';

/// Local triple store implementation using SQLite
class TripleStore implements StorageInterface {
  late final Database _db;
  final String appId;
  final InstantSchema? _schema;
  final StreamController<TripleChange> _changeController =
      StreamController.broadcast();

  /// Stream of all changes to the triple store
  @override
  Stream<TripleChange> get changes => _changeController.stream;

  TripleStore._(this.appId, this._db, this._schema);

  /// Initialize the triple store
  static Future<TripleStore> init({
    required String appId,
    String? persistenceDir,
    InstantSchema? schema,
  }) async {
    // Initialize the platform-specific database factory
    await initializeDatabaseFactory();

    // Get the platform-specific database path
    final dbPath = await getDatabasePath(appId, persistenceDir: persistenceDir);

    // Get the platform-specific database factory
    final factory = getDatabaseFactory();

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      ),
    );

    return TripleStore._(appId, db, schema);
  }

  static Future<void> _createTables(Database db, int version) async {
    // Triples table - core data storage
    await db.execute('''
      CREATE TABLE triples (
        entity_id TEXT NOT NULL,
        attribute TEXT NOT NULL,
        value TEXT NOT NULL,
        tx_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retracted BOOLEAN DEFAULT FALSE,
        is_local_only BOOLEAN DEFAULT FALSE,
        PRIMARY KEY (entity_id, attribute, value, tx_id)
      )
    ''');

    // Indexes for performance
    await db.execute('CREATE INDEX idx_entity ON triples(entity_id)');
    await db.execute('CREATE INDEX idx_attribute ON triples(attribute)');
    await db.execute('CREATE INDEX idx_tx ON triples(tx_id)');
    await db.execute('CREATE INDEX idx_created_at ON triples(created_at)');
    await db.execute('CREATE INDEX idx_retracted ON triples(retracted)');
    await db.execute('CREATE INDEX idx_local_only ON triples(is_local_only)');

    // Transactions table - track transaction status
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        synced BOOLEAN DEFAULT FALSE,
        data TEXT NOT NULL
      )
    ''');

    // Metadata table - store app state
    await db.execute('''
      CREATE TABLE metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgradeTables(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Handle database schema migrations here
    if (oldVersion < 2 && newVersion >= 2) {
      // Migration from v1 to v2: Add is_local_only column
      await db.execute(
        'ALTER TABLE triples ADD COLUMN is_local_only BOOLEAN DEFAULT FALSE',
      );
      await db.execute('CREATE INDEX idx_local_only ON triples(is_local_only)');
    }
  }

  /// Add a triple to the store
  Future<void> addTriple(Triple triple) async {
    await _db.insert('triples', {
      'entity_id': triple.entityId,
      'attribute': triple.attribute,
      'value': jsonEncode(triple.value),
      'tx_id': triple.txId,
      'created_at': triple.createdAt.millisecondsSinceEpoch,
      'retracted': triple.retracted ? 1 : 0,
      'is_local_only': triple.isLocalOnly ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _changeController.add(TripleChange(type: ChangeType.add, triple: triple));
  }

  /// Retract a triple (soft delete)
  Future<void> retractTriple(Triple triple) async {
    await _db.update(
      'triples',
      {'retracted': 1},
      where: 'entity_id = ? AND attribute = ? AND value = ? AND tx_id = ?',
      whereArgs: [
        triple.entityId,
        triple.attribute,
        jsonEncode(triple.value),
        triple.txId,
      ],
    );

    _changeController.add(
      TripleChange(type: ChangeType.retract, triple: triple),
    );
  }

  /// Query triples by entity ID
  Future<List<Triple>> queryByEntity(
    String entityId, {
    bool syncedOnly = false,
  }) async {
    final where = syncedOnly
        ? 'entity_id = ? AND retracted = FALSE AND is_local_only = FALSE'
        : 'entity_id = ? AND retracted = FALSE';

    final results = await _db.query(
      'triples',
      where: where,
      whereArgs: [entityId],
      orderBy: 'created_at ASC',
    );

    return results.map(mapToTriple).toList();
  }

  /// Query triples by attribute
  Future<List<Triple>> queryByAttribute(String attribute) async {
    final results = await _db.query(
      'triples',
      where: 'attribute = ? AND retracted = FALSE',
      whereArgs: [attribute],
      orderBy: 'created_at ASC',
    );

    return results.map(mapToTriple).toList();
  }

  /// Query all entities of a specific type
  Future<List<String>> queryEntityIdsByType(String entityType) async {
    final results = await _db.query(
      'triples',
      columns: ['entity_id'],
      where: 'attribute = ? AND value = ? AND retracted = FALSE',
      whereArgs: ['__type', jsonEncode(entityType)],
      distinct: true,
    );

    return results.map((row) => row['entity_id'] as String).toList();
  }

  @override
  Future<String> getLocalId(String name) async {
    final key = 'localId:$name';
    return await _db.transaction((txn) async {
      final existing = await txn.query(
        'metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return existing.first['value'] as String;
      }
      final id = const Uuid().v4();
      await txn.insert(
        'metadata',
        {'key': key, 'value': id},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return id;
    });
  }

  /// Get entity type for a specific entity ID
  @override
  Future<String?> getEntityType(String entityId) async {
    final results = await _db.query(
      'triples',
      columns: ['value'],
      where: 'entity_id = ? AND attribute = ? AND retracted = FALSE',
      whereArgs: [entityId, '__type'],
    );

    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }

    return null;
  }

  /// Execute a complex query with WHERE conditions
  @override
  Future<List<Map<String, dynamic>>> queryEntities({
    String? entityType,
    String? entityId,
    Map<String, dynamic>? where,
    List<String>? orderBy,
    int? limit,
    int? offset,
    Map<String, dynamic>? aggregate,
    List<String>? groupBy,
    bool syncedOnly = false,
  }) async {
    final entities = <String, Map<String, dynamic>>{};

    // Build WHERE clause for synced-only filtering
    final baseWhere = syncedOnly
        ? 'retracted = FALSE AND is_local_only = FALSE'
        : 'retracted = FALSE';

    // Get entity IDs
    List<String> entityIds;
    if (entityId != null) {
      // Query specific entity
      entityIds = [entityId];
    } else if (entityType != null) {
      entityIds = await queryEntityIdsByType(entityType);
    } else {
      final results = await _db.query(
        'triples',
        columns: ['entity_id'],
        where: baseWhere,
        distinct: true,
      );
      entityIds = results.map((row) => row['entity_id'] as String).toList();
    }

    // Build entities from triples
    for (final entityId in entityIds) {
      final triples = await queryByEntity(entityId, syncedOnly: syncedOnly);
      final entity = <String, dynamic>{'id': entityId};

      for (final triple in triples) {
        final attr = triple.attribute;
        // 'id' is already set from entityId above; skip to avoid creating
        // a spurious list when the legacy 'add' operation stores id as a triple.
        if (attr == 'id') continue;
        if (entity.containsKey(attr)) {
          final existing = entity[attr];
          if (existing is List) {
            existing.add(triple.value);
          } else {
            entity[attr] = <dynamic>[existing, triple.value];
          }
        } else {
          entity[attr] = triple.value;
        }
      }

      entities[entityId] = entity;
    }

    var result = entities.values.toList();

    // Apply WHERE filtering
    if (where != null) {
      result = result.where((entity) => matchesWhere(entity, where)).toList();
    }

    // Handle aggregations
    if (aggregate != null) {
      return processAggregations(result, aggregate, groupBy);
    }

    // Apply ordering
    if (orderBy != null) {
      result.sort((a, b) => compareEntities(a, b, orderBy));
    }

    // Apply pagination
    if (offset != null) {
      result = result.skip(offset).toList();
    }
    if (limit != null) {
      result = result.take(limit).toList();
    }

    return result;
  }

  /// Resolve a lookup reference to find entity ID by attribute value
  Future<String?> resolveLookup(
    String entityType,
    String attribute,
    dynamic value,
  ) async {
    final results = await queryEntities(
      entityType: entityType,
      where: {attribute: value},
      limit: 1,
    );

    if (results.isNotEmpty) {
      return results.first['id'] as String?;
    }

    return null;
  }

  /// Resolve multiple lookup references at once
  Future<Map<LookupRef, String?>> resolveLookupsMap(
    List<LookupRef> lookups,
  ) async {
    final results = <LookupRef, String?>{};

    for (final lookup in lookups) {
      final entityId = await resolveLookup(
        lookup.entityType,
        lookup.attribute,
        lookup.value,
      );
      results[lookup] = entityId;
    }

    return results;
  }

  @override
  Future<List<Operation>> resolveTargetLookups(
    List<Operation> operations,
  ) async {
    final resolved = <Operation>[];
    for (final op in operations) {
      final ref = op.lookupRef;
      if (ref == null) {
        resolved.add(op);
        continue;
      }

      final existingId = await resolveLookup(
        ref.entityType,
        ref.attribute,
        ref.value,
      );

      if (existingId != null) {
        resolved.add(withEntityId(op, existingId));
        continue;
      }

      // No existing entity for this unique attribute.
      if (op.type == OperationType.delete) {
        // Nothing to delete — drop the op.
        continue;
      }

      // Upsert: allocate a new id and ensure the type + lookup attribute are
      // persisted so the entity is findable next time.
      final newId = const Uuid().v4();
      final data = <String, dynamic>{
        ...?op.data,
        '__type': ref.entityType,
        ref.attribute: ref.value,
      };
      resolved.add(
        Operation(
          type: op.type == OperationType.merge
              ? OperationType.merge
              : OperationType.update,
          entityType: ref.entityType,
          entityId: newId,
          data: data,
          options: op.options,
        ),
      );
    }
    return resolved;
  }

  /// Apply a transaction to the store
  @override
  Future<void> applyTransaction(Transaction transaction) async {
    // Check if transaction already exists
    final existing = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transaction.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Transaction already applied, skip
      InstantDBLogging.root.debug(
        'Transaction ${transaction.id} already applied, skipping',
      );
      return;
    }

    // Resolve any lookup references first (outside DB transaction)
    final resolvedOperations = await _resolveLookupReferences(
      transaction.operations,
    );

    // Collect change events to emit after the transaction completes
    final pendingChanges = <TripleChange>[];

    await _db.transaction((txn) async {
      // Store transaction record
      await txn.insert('transactions', {
        'id': transaction.id,
        'timestamp': transaction.timestamp.millisecondsSinceEpoch,
        'status': transaction.status.name,
        'synced': transaction.status == TransactionStatus.synced ? 1 : 0,
        'data': jsonEncode(transaction.toJson()),
      });

      // Apply resolved operations and collect changes
      for (final operation in resolvedOperations) {
        final changes = await _applyOperationWithChanges(
          txn,
          operation,
          transaction.id,
        );
        pendingChanges.addAll(changes);
      }
    });

    // Emit all changes after transaction completes
    InstantDBLogging.root.debug(
      'TripleStore: Transaction ${transaction.id} complete, emitting ${pendingChanges.length} changes',
    );
    for (final change in pendingChanges) {
      InstantDBLogging.root.debug(
        'TripleStore: Emitting change - ${change.type} for entity ${change.triple.entityId}, attribute ${change.triple.attribute}',
      );
      _changeController.add(change);
    }
  }

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

  /// Rollback a transaction
  @override
  Future<void> rollbackTransaction(String txId) async {
    await _db.transaction((txn) async {
      // Mark transaction as failed
      await txn.update(
        'transactions',
        {'status': TransactionStatus.failed.name},
        where: 'id = ?',
        whereArgs: [txId],
      );

      // Retract all triples from this transaction
      await txn.update(
        'triples',
        {'retracted': 1},
        where: 'tx_id = ?',
        whereArgs: [txId],
      );
    });
  }

  /// Get transaction by ID
  Future<Transaction?> getTransaction(String txId) async {
    final results = await _db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [txId],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final row = results.first;
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    return Transaction.fromJson(data);
  }

  /// Get all pending transactions
  @override
  Future<List<Transaction>> getPendingTransactions() async {
    final results = await _db.query(
      'transactions',
      where: 'synced = FALSE AND status != ?',
      whereArgs: [TransactionStatus.failed.name],
      orderBy: 'timestamp ASC',
    );

    final transactions = <Transaction>[];
    final corruptedIds = <String>[];

    for (final row in results) {
      try {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final transaction = Transaction.fromJson(data);

        // Check if this transaction has corrupted entity IDs
        bool hasCorruptedIds = false;
        for (final op in transaction.operations) {
          if (op.type == OperationType.delete &&
              op.entityId.startsWith('[') &&
              op.entityId.endsWith(']')) {
            hasCorruptedIds = true;
            break;
          }
        }

        if (hasCorruptedIds) {
          // Mark corrupted transactions as failed
          corruptedIds.add(transaction.id);
          InstantDBLogging.root.debug(
            'Found corrupted transaction ${transaction.id}, marking as failed',
          );
        } else {
          transactions.add(transaction);
        }
      } catch (e) {
        InstantDBLogging.root.severe('Error parsing transaction', e);
      }
    }

    // Mark corrupted transactions as failed so they won't be retried
    if (corruptedIds.isNotEmpty) {
      await _markTransactionsAsFailed(corruptedIds);
    }

    return transactions;
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

  /// Mark transaction as synced
  @override
  Future<void> markTransactionSynced(String txId) async {
    await _db.update(
      'transactions',
      {'synced': 1, 'status': TransactionStatus.synced.name},
      where: 'id = ?',
      whereArgs: [txId],
    );
  }

  /// Vacuum the database to reclaim space from deleted (retracted) triples
  ///
  /// This method deletes retracted triples older than the specified retention
  /// period and runs VACUUM to reclaim disk space. This prevents unbounded
  /// database growth over time.
  ///
  /// [retentionDays] - Number of days to keep retracted triples (default: 30)
  ///
  /// Returns the number of triples deleted
  Future<int> vacuum({int retentionDays = 30}) async {
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;

    InstantDBLogging.root.info(
      'TripleStore: Starting vacuum - removing retracted triples older than $retentionDays days',
    );

    // Count triples to be deleted
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM triples WHERE retracted = ? AND created_at < ?',
      [1, cutoffTime],
    );
    final count = countResult.first['count'] as int;

    if (count == 0) {
      InstantDBLogging.root.info(
        'TripleStore: No retracted triples to clean up',
      );
      return 0;
    }

    // Delete old retracted triples
    await _db.delete(
      'triples',
      where: 'retracted = ? AND created_at < ?',
      whereArgs: [1, cutoffTime],
    );

    // Run VACUUM to reclaim space
    await _db.execute('VACUUM');

    InstantDBLogging.root.info(
      'TripleStore: Vacuum complete - deleted $count retracted triples and reclaimed disk space',
    );

    return count;
  }

  /// Clear all data from the database (useful for development/debugging)
  @override
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete('triples');
      await txn.delete('transactions');
      await txn.delete('metadata');
    });

    // Emit a change event to update any listeners
    _changeController.add(TripleChange.clear());
  }

  /// Close the database
  @override
  Future<void> close() async {
    await _changeController.close();
    await _db.close();
  }
}
