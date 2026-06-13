import 'package:uuid/uuid.dart';
import 'types.dart';

/// Transaction builder that implements the `tx` namespace pattern
class TransactionBuilder {
  final Map<String, EntityBuilder> _entities = {};

  /// Access entity builder by type (e.g., tx.goals, tx.todos)
  EntityBuilder operator [](String entityType) {
    return _entities[entityType] ??= EntityBuilder(entityType);
  }

  /// Get entity builder dynamically (allows tx.goals, tx.todos, etc.)
  EntityBuilder getEntity(String entityType) => this[entityType];

  /// Handle dynamic property access (tx.todos, tx.goals, etc.)
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final entityType = invocation.memberName.toString().split('"')[1];
      return this[entityType];
    }
    return super.noSuchMethod(invocation);
  }
}

/// Entity-specific transaction builder
class EntityBuilder {
  final String entityType;
  final Map<String, EntityInstanceBuilder> _instances = {};
  final _uuid = const Uuid();

  EntityBuilder(this.entityType);

  /// Access specific entity instance (e.g., tx.goals[goalId])
  EntityInstanceBuilder operator [](String entityId) {
    return _instances[entityId] ??= EntityInstanceBuilder(entityType, entityId);
  }

  /// Create a new entity of this type
  TransactionChunk create(Map<String, dynamic> data) {
    final entityId = data['id'] as String? ?? _uuid.v4();

    // Ensure __type is included
    final fullData = Map<String, dynamic>.from(data);
    fullData['__type'] = entityType;

    return TransactionChunk([
      Operation(
        type: OperationType.add,
        entityType: entityType,
        entityId: entityId,
        data: fullData,
      ),
    ]);
  }

  /// Target an entity by a unique attribute (upsert-by-lookup), chainable like
  /// `tx.profiles.lookup('email', 'a@b.com').update({...})`.
  EntityInstanceBuilder lookup(String attribute, dynamic value) {
    return EntityInstanceBuilder.lookup(entityType, attribute, value);
  }
}

/// Builder for operations on a specific entity instance
class EntityInstanceBuilder {
  final String entityType;
  final String entityId;
  final LookupRef? lookupRef;

  EntityInstanceBuilder(this.entityType, this.entityId) : lookupRef = null;

  /// Construct a builder whose target is resolved by a unique attribute.
  EntityInstanceBuilder.lookup(this.entityType, String attribute, dynamic value)
      : entityId = '',
        lookupRef = LookupRef(
          entityType: entityType,
          attribute: attribute,
          value: value,
        );

  /// Update entity with new data. Pass `opts: TxOpts(upsert: false)` for
  /// strict mode (do not create the entity if it does not exist).
  TransactionChunk update(Map<String, dynamic> data, {TxOpts? opts}) {
    return TransactionChunk([
      Operation(
        type: OperationType.update,
        entityType: entityType,
        entityId: entityId,
        data: data,
        options: opts?.toOptions(),
        lookupRef: lookupRef,
      ),
    ]);
  }

  /// Link this entity to another entity or entities
  TransactionChunk link(Map<String, dynamic> links) {
    final operations = <Operation>[];

    for (final entry in links.entries) {
      final relationName = entry.key;
      final targetIds = entry.value;

      if (targetIds is List) {
        // Link to multiple entities
        for (final targetId in targetIds) {
          operations.add(
            Operation(
              type: OperationType.link,
              entityType: entityType,
              entityId: entityId,
              data: {relationName: targetId},
              lookupRef: lookupRef,
            ),
          );
        }
      } else {
        // Link to single entity
        operations.add(
          Operation(
            type: OperationType.link,
            entityType: entityType,
            entityId: entityId,
            data: {relationName: targetIds},
            lookupRef: lookupRef,
          ),
        );
      }
    }

    return TransactionChunk(operations);
  }

  /// Unlink this entity from another entity or entities
  TransactionChunk unlink(Map<String, dynamic> unlinks) {
    final operations = <Operation>[];

    for (final entry in unlinks.entries) {
      final relationName = entry.key;
      final targetIds = entry.value;

      if (targetIds is List) {
        // Unlink from multiple entities
        for (final targetId in targetIds) {
          operations.add(
            Operation(
              type: OperationType.unlink,
              entityType: entityType,
              entityId: entityId,
              data: {relationName: targetId},
              lookupRef: lookupRef,
            ),
          );
        }
      } else {
        // Unlink from single entity
        operations.add(
          Operation(
            type: OperationType.unlink,
            entityType: entityType,
            entityId: entityId,
            data: {relationName: targetIds},
            lookupRef: lookupRef,
          ),
        );
      }
    }

    return TransactionChunk(operations);
  }

  /// Deep-merge data into the existing entity. Pass `opts: TxOpts(upsert:false)`
  /// for strict mode.
  TransactionChunk merge(Map<String, dynamic> data, {TxOpts? opts}) {
    return TransactionChunk([
      Operation(
        type: OperationType.merge,
        entityType: entityType,
        entityId: entityId,
        data: data,
        options: opts?.toOptions(),
        lookupRef: lookupRef,
      ),
    ]);
  }

  /// Delete this entity
  TransactionChunk delete() {
    return TransactionChunk([
      Operation(
        type: OperationType.delete,
        entityType: entityType,
        entityId: entityId,
        lookupRef: lookupRef,
      ),
    ]);
  }
}

/// Create a lookup reference for transactions
LookupRef lookup(String entityType, String attribute, dynamic value) {
  return LookupRef(entityType: entityType, attribute: attribute, value: value);
}

/// Helper function to combine multiple transaction chunks
TransactionChunk combineChunks(List<TransactionChunk> chunks) {
  final allOperations = <Operation>[];
  for (final chunk in chunks) {
    allOperations.addAll(chunk.operations);
  }
  return TransactionChunk(allOperations);
}
