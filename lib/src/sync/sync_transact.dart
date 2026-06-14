part of 'sync_engine.dart';

/// Private transaction send/receive helpers for [SyncEngine].
///
/// Moved verbatim from `sync_engine.dart` into a `part of` extension. As an
/// extension in the same library it retains access to the engine's private
/// fields and methods. No logic was changed — only relocated. (Methods that
/// reference the class's private *static* loggers, such as `sendTransaction`,
/// were intentionally left in the main class body, since extensions cannot
/// reference static members unqualified without editing the moved code.)
extension _SyncTransact on SyncEngine {
  Future<void> _applyRemoteTransaction(Transaction transaction) async {
    try {
      // Don't log every operation to reduce verbosity
      if (_refreshOkCount <= 3) {
        InstantDBLogging.root.debug(
          'Applying remote transaction ${transaction.id} with ${transaction.operations.length} operations',
        );
      }

      // Apply the transaction with already-synced status to avoid re-sending
      await _store.applyTransaction(transaction);
      // No need to mark as synced separately since remote transactions have synced status
    } catch (e) {
      // Handle conflict resolution here
      // For now, just log the error
      InstantDBLogging.root.severe('Error applying remote transaction', e);
    }
  }

  void _handleRemoteTransact(Map<String, dynamic> data) async {
    // InstantDB sends remote transactions as 'transact' messages with tx-steps
    // We need to convert these to our Transaction format
    try {
      // Check if this is our own transaction echoed back
      final clientEventId = data['client-event-id'];
      if (clientEventId != null && _sentEventIds.contains(clientEventId)) {
        InstantDBLogging.root.debug(
          'Ignoring our own echoed transaction: $clientEventId',
        );
        return;
      }

      final txSteps = data['tx-steps'] as List?;
      if (txSteps == null) {
        InstantDBLogging.root.warning('No tx-steps in transact message');
        return;
      }

      // Generate a transaction ID from the event ID if available
      final txId = data['client-event-id']?.toString() ?? _uuid.v4();
      final timestamp = data['created'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['created'] as int)
          : DateTime.now();

      // Convert tx-steps to operations
      final operations = <Operation>[];

      for (final step in txSteps) {
        if (step is! List || step.isEmpty) continue;

        final stepType = step[0] as String;

        switch (stepType) {
          case 'add-triple':
            if (step.length >= 4) {
              final entityId = step[1].toString();
              final attrId = step[2].toString();
              final value = step[3];

              // Find the attribute name from our cache
              String? attrName;
              for (final nsEntry in _attributeCache.entries) {
                for (final attrEntry in nsEntry.value.entries) {
                  if (attrEntry.value == attrId) {
                    attrName = attrEntry.key;
                    break;
                  }
                }
                if (attrName != null) break;
              }

              if (attrName != null) {
                // Check if this is a type declaration for a local-only entity
                if (attrName == '__type' && value is String) {
                  final isLocalOnlyType = schema?.isLocalOnly(value) ?? false;
                  if (isLocalOnlyType) {
                    InstantDBLogging.root.warning(
                      'Skipping remote transaction for local-only entity type: $value',
                    );
                    continue; // Skip this entire tx-step
                  }
                }

                operations.add(
                  Operation.legacy(
                    type: OperationType.add,
                    entityId: entityId,
                    attribute: attrName,
                    value: value,
                  ),
                );
              } else {
                // If we don't have the attribute cached, try to use common attribute names
                // This is a workaround for when we receive updates before the attribute cache is fully populated
                InstantDBLogging.root.debug(
                  'Unknown attribute ID: $attrId, trying to infer attribute name',
                );

                // Common attributes we might expect
                if (value is String && (value == 'todos' || value == 'users')) {
                  // This is likely a __type attribute
                  // Check if this is a local-only entity type
                  final isLocalOnlyType = schema?.isLocalOnly(value) ?? false;
                  if (!isLocalOnlyType) {
                    operations.add(
                      Operation.legacy(
                        type: OperationType.add,
                        entityId: entityId,
                        attribute: '__type',
                        value: value,
                      ),
                    );
                  } else {
                    InstantDBLogging.root.warning(
                      'Skipping remote transaction for inferred local-only entity type: $value',
                    );
                  }
                } else {
                  // For now, skip unknown attributes but log them
                  InstantDBLogging.root.debug(
                    'Skipping unknown attribute ID: $attrId with value: $value',
                  );
                }
              }
            }
            break;

          case 'delete-entity':
            if (step.length >= 2) {
              final entityId = step[1].toString();
              operations.add(
                Operation.legacy(
                  type: OperationType.delete,
                  entityId: entityId,
                ),
              );
            }
            break;

          case 'add-attr':
            // This is an attribute registration, update our cache
            if (step.length >= 2 && step[1] is Map) {
              final attrData = step[1] as Map<String, dynamic>;
              if (attrData['id'] != null &&
                  attrData['forward-identity'] is List &&
                  (attrData['forward-identity'] as List).length >= 3) {
                final forwardIdentity = attrData['forward-identity'] as List;
                final namespace = forwardIdentity[1].toString();
                final attrName = forwardIdentity[2].toString();
                final attrId = attrData['id'].toString();

                // Cache the attribute UUID
                _attributeCache.putIfAbsent(namespace, () => {});
                _attributeCache[namespace]![attrName] = attrId;

                // Silently cache remote attributes to avoid spam
              }
            }
            break;
        }
      }

      if (operations.isNotEmpty) {
        // Create and apply the transaction
        final transaction = Transaction(
          id: txId,
          operations: operations,
          timestamp: timestamp,
          status: TransactionStatus.synced,
        );

        InstantDBLogging.logTransaction(
          'APPLY_REMOTE',
          txId,
          operationCount: operations.length,
          status: 'synced',
        );
        await _applyRemoteTransaction(transaction);
      }
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Error handling remote transact: $e');
      InstantDBLogging.root.debug('Stack trace: $stackTrace');
    }
  }

  void _handleTransactionAck(String txId) async {
    InstantDBLogging.logTransaction('ACK', txId, status: 'synced');
    await _store.markTransactionSynced(txId);
  }

  Future<void> _handleTransactionError(String txId, String error) async {
    InstantDBLogging.logTransaction('ERROR', txId, status: 'rejected');
    InstantDBLogging.root.warning(
      'Rolling back transaction $txId due to server rejection: $error',
    );

    try {
      await _store.rollbackTransaction(txId);
      InstantDBLogging.root.info('Transaction $txId rolled back successfully');
    } catch (e) {
      InstantDBLogging.root.severe('Failed to rollback transaction $txId: $e');
    }
  }

  /// Clean up old entries from recently created entities map
  void _cleanupRecentlyCreatedEntities() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _recentlyCreatedEntities.entries) {
      final age = now.difference(entry.value);
      if (age.inSeconds > 30) {
        // Remove entries older than 30 seconds
        toRemove.add(entry.key);
      }
    }

    for (final key in toRemove) {
      _recentlyCreatedEntities.remove(key);
    }

    if (toRemove.isNotEmpty) {
      InstantDBLogging.root.debug(
        'Cleaned up ${toRemove.length} old recently-created entity entries',
      );
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_syncQueue.isNotEmpty) {
        final transaction = _syncQueue.removeFirst();

        if (_connectionStatus.value &&
            _webSocket != null &&
            _webSocket.isOpen) {
          // Send via WebSocket
          try {
            // Transform to InstantDB's expected format
            // InstantDB requires UUIDs for attributes, not simple names
            final txSteps = <dynamic>[];

            // Track namespace for operations
            String? namespace;

            // First pass: identify namespace from __type attribute
            for (final op in transaction.operations) {
              if (op.attribute == '__type' && op.value is String) {
                namespace = op.value as String;
                break;
              }
            }

            // Second pass: add the actual operations using attribute UUIDs
            for (final op in transaction.operations) {
              if (op.type == OperationType.add) {
                // Handle new Operation format with data map
                if (op.data != null && op.data!.isNotEmpty) {
                  final ns = op.entityType.isNotEmpty
                      ? op.entityType
                      : (namespace ?? 'todos');
                  InstantDBLogging.root.debug(
                    'Processing add operation for entity ${op.entityId} in namespace $ns',
                  );
                  InstantDBLogging.root.debug('Operation data: ${op.data}');

                  // Convert each attribute in the data map to a tx-step
                  for (final entry in op.data!.entries) {
                    final attrName = entry.key;
                    final attrValue = entry.value;

                    // Skip __type attribute for now - we'll handle it separately
                    if (attrName == '__type') continue;

                    // Look up the attribute ID from cache
                    String? attrId = _attributeCache[ns]?[attrName];

                    if (attrId != null) {
                      // Use known attribute UUID
                      txSteps.add([
                        'add-triple',
                        op.entityId,
                        attrId,
                        attrValue,
                      ]);
                      InstantDBLogging.root.debug(
                        'Added tx-step for $ns.$attrName = $attrValue (UUID: $attrId)',
                      );
                    } else {
                      // Fail loudly instead of silently skipping
                      final errorMsg =
                          'Unknown attribute $ns.$attrName - not in attribute cache. '
                          'This may indicate the schema is out of sync or the attribute '
                          'was created by another client. Available attributes for $ns: '
                          '${_attributeCache[ns]?.keys.join(", ") ?? "none"}';

                      InstantDBLogging.root.severe(errorMsg);

                      throw InstantException(
                        message: errorMsg,
                        code: 'missing_attribute',
                      );
                    }
                  }
                }
                // Legacy format support (for backwards compatibility)
                else if (op.attribute != null && op.attribute != '__type') {
                  // Look up the attribute ID from cache
                  final ns = namespace ?? 'todos';
                  String? attrId = _attributeCache[ns]?[op.attribute];

                  if (attrId != null) {
                    // Use known attribute UUID
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  } else {
                    // Fail loudly instead of silently skipping
                    final errorMsg =
                        'Unknown attribute ${op.attribute} for namespace $ns - not in attribute cache. '
                        'This may indicate the schema is out of sync or the attribute '
                        'was created by another client. Available attributes for $ns: '
                        '${_attributeCache[ns]?.keys.join(", ") ?? "none"}';

                    InstantDBLogging.root.severe(errorMsg);

                    throw InstantException(
                      message: errorMsg,
                      code: 'missing_attribute',
                    );
                  }
                }
              } else if (op.type == OperationType.update) {
                if (op.attribute != null) {
                  // Look up the attribute ID from cache
                  final ns = namespace ?? 'todos';
                  String? attrId = _attributeCache[ns]?[op.attribute];

                  if (attrId != null) {
                    // Use known attribute UUID
                    txSteps.add([
                      'add-triple',
                      op.entityId,
                      attrId,
                      op.value ?? '',
                    ]);
                  } else {
                    // Fail loudly instead of silently skipping
                    final errorMsg =
                        'Unknown attribute ${op.attribute} for namespace $ns in update - not in attribute cache. '
                        'This may indicate the schema is out of sync or the attribute '
                        'was created by another client. Available attributes for $ns: '
                        '${_attributeCache[ns]?.keys.join(", ") ?? "none"}';

                    InstantDBLogging.root.severe(errorMsg);

                    throw InstantException(
                      message: errorMsg,
                      code: 'missing_attribute',
                    );
                  }
                }
              } else if (op.type == OperationType.delete) {
                // For deletes, we need to ensure entity ID is a proper string
                // Sometimes entity IDs come as stringified arrays from corrupted data
                String cleanEntityId = op.entityId;

                // Check if entity ID looks like a stringified array
                if (cleanEntityId.startsWith('[') &&
                    cleanEntityId.endsWith(']')) {
                  try {
                    // Try to parse it as JSON array and extract first element
                    final parsed = jsonDecode(cleanEntityId);
                    if (parsed is List && parsed.isNotEmpty) {
                      cleanEntityId = parsed[0].toString();
                      InstantDBLogging.root.debug(
                        'Fixed corrupted entity ID from "$op.entityId" to "$cleanEntityId"',
                      );
                    }
                  } catch (e) {
                    // If parsing fails, try to extract first UUID-like string
                    final uuidPattern = RegExp(
                      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                    );
                    final match = uuidPattern.firstMatch(cleanEntityId);
                    if (match != null) {
                      cleanEntityId = match.group(0)!;
                      InstantDBLogging.root.debug(
                        'Extracted entity ID "$cleanEntityId" from corrupted string',
                      );
                    }
                  }
                }

                // Resolve entity type if it's 'unknown'
                String entityType = op.entityType;
                if (entityType == 'unknown' || entityType.isEmpty) {
                  // Try to resolve from store, fallback to namespace or default
                  final resolvedType = await _store.getEntityType(
                    cleanEntityId,
                  );
                  entityType = resolvedType ?? namespace ?? 'todos';

                  if (resolvedType != null) {
                    InstantDBLogging.root.debug(
                      'Resolved entity type for $cleanEntityId: $resolvedType',
                    );
                  } else {
                    InstantDBLogging.root.debug(
                      'Could not resolve entity type for $cleanEntityId, using fallback: $entityType',
                    );
                  }
                }

                txSteps.add(['delete-entity', cleanEntityId, entityType]);
              }
            }

            final clientEventId =
                transaction.id; // Use transaction ID as client-event-id
            _sentEventIds.add(clientEventId); // Track for deduplication

            // Track entity IDs from add operations for deduplication
            final now = DateTime.now();
            for (final op in transaction.operations) {
              if (op.type == OperationType.add) {
                _recentlyCreatedEntities[op.entityId] = now;
                InstantDBLogging.root.debug(
                  'Tracking recently created entity: ${op.entityId}',
                );
              }
            }

            // Forward permission rule params if any operation carries them.
            Map<String, dynamic>? ruleParams;
            for (final op in transaction.operations) {
              final rp = op.options?['ruleParams'];
              if (rp is Map<String, dynamic>) {
                ruleParams = {...?ruleParams, ...rp};
              }
            }

            final transactionMessage = {
              'op': 'transact',
              'tx-steps': txSteps,
              if (ruleParams != null) 'rule-params': ruleParams,
              'created': DateTime.now().millisecondsSinceEpoch,
              'order': 1,
              'client-event-id': clientEventId,
            };

            // Debug log transaction details
            InstantDBLogging.root.debug(
              'Sending transaction ${transaction.id} with ${txSteps.length} steps',
            );
            if (txSteps.isNotEmpty) {
              InstantDBLogging.root.debug(
                'First tx-step: ${jsonEncode(txSteps.first)}',
              );
            }
            _webSocket.send(jsonEncode(transactionMessage));
          } catch (e) {
            // Re-queue on WebSocket error
            _syncQueue.addFirst(transaction);
            break;
          }
        } else {
          // Fallback to HTTP if WebSocket unavailable
          try {
            await _dio.post('/v1/transact', data: transaction.toJson());
            await _store.markTransactionSynced(transaction.id);
          } catch (e) {
            // Re-queue on HTTP error
            _syncQueue.addFirst(transaction);
            break;
          }
        }

        // Small delay between transactions
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processPendingTransactions() async {
    final pendingTransactions = await _store.getPendingTransactions();
    InstantDBLogging.root.info(
      'Found ${pendingTransactions.length} pending transactions to sync',
    );

    for (final transaction in pendingTransactions) {
      _syncQueue.add(transaction);
      InstantDBLogging.root.debug(
        'Queued transaction ${transaction.id} with ${transaction.operations.length} operations',
      );
    }

    if (_syncQueue.isNotEmpty) {
      _processQueue();
    }
  }
}
