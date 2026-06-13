import 'dart:async';
import '../core/types.dart';

/// Abstract interface for storage backends
/// This allows InstantDB to work with either SQLite (TripleStore) or ReaxDB (ReaxStore)
abstract class StorageInterface {
  /// Stream of all changes to the store
  Stream<TripleChange> get changes;

  /// Apply a transaction to the store
  Future<void> applyTransaction(Transaction transaction);

  /// Rollback a transaction
  Future<void> rollbackTransaction(String txId);

  /// Query entities with filtering, sorting, and pagination
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
  });

  /// Clear all data from the store
  Future<void> clearAll();

  /// Mark a transaction as synced
  Future<void> markTransactionSynced(String txId);

  /// Get pending (unsynced) transactions
  Future<List<Transaction>> getPendingTransactions();

  /// Get entity type for a specific entity ID
  Future<String?> getEntityType(String entityId);

  /// Resolve operations whose target is a [LookupRef] into concrete entity ids.
  /// For write ops with no existing match, a new entity id is allocated (upsert
  /// by unique attribute). Delete ops with no match are dropped.
  Future<List<Operation>> resolveTargetLookups(List<Operation> operations);

  /// Close the store and clean up resources
  Future<void> close();
}
