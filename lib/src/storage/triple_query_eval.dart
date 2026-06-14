import 'dart:convert';

import '../core/types.dart';

/// Pure query/filter/aggregate helpers extracted from [TripleStore].
///
/// These functions touch no instance state; they operate purely on the maps
/// and values handed to them. They were moved verbatim from `triple_store.dart`
/// (private `_`-prefixed methods renamed to public free functions) to keep the
/// store class focused and to make this logic directly unit-testable.

bool matchesWhere(Map<String, dynamic> entity, Map<String, dynamic> where) {
  for (final entry in where.entries) {
    final key = entry.key;
    final value = entry.value;

    // Handle special logical operators
    if (key == '\$or') {
      if (value is List) {
        bool matchesAny = false;
        for (final condition in value) {
          if (condition is Map<String, dynamic> &&
              matchesWhere(entity, condition)) {
            matchesAny = true;
            break;
          }
        }
        if (!matchesAny) return false;
      }
      continue;
    }

    if (key == '\$and') {
      if (value is List) {
        for (final condition in value) {
          if (condition is Map<String, dynamic> &&
              !matchesWhere(entity, condition)) {
            return false;
          }
        }
      }
      continue;
    }

    if (key == '\$not') {
      if (value is Map<String, dynamic>) {
        // If the NOT condition matches, this fails
        if (matchesWhere(entity, value)) return false;
      }
      continue;
    }

    if (!entity.containsKey(key)) return false;

    final entityValue = entity[key];

    // Handle complex operators
    if (value is Map<String, dynamic>) {
      if (!matchesOperator(entityValue, value)) return false;
    } else {
      // Simple equality check
      if (entityValue != value) return false;
    }
  }
  return true;
}

bool matchesOperator(dynamic entityValue, Map<String, dynamic> operators) {
  for (final entry in operators.entries) {
    final operator = entry.key;
    final operandValue = entry.value;

    switch (operator) {
      // Standard comparison operators
      case '>':
      case '\$gt':
        if (entityValue is! Comparable || operandValue is! Comparable) {
          return false;
        }
        if ((entityValue).compareTo(operandValue) <= 0) {
          return false;
        }
        break;
      case '>=':
      case '\$gte':
        if (entityValue is! Comparable || operandValue is! Comparable) {
          return false;
        }
        if ((entityValue).compareTo(operandValue) < 0) {
          return false;
        }
        break;
      case '<':
      case '\$lt':
        if (entityValue is! Comparable || operandValue is! Comparable) {
          return false;
        }
        if ((entityValue).compareTo(operandValue) >= 0) {
          return false;
        }
        break;
      case '<=':
      case '\$lte':
        if (entityValue is! Comparable || operandValue is! Comparable) {
          return false;
        }
        if ((entityValue).compareTo(operandValue) > 0) {
          return false;
        }
        break;
      case '!=':
      case '\$ne':
        if (entityValue == operandValue) return false;
        break;
      case 'in':
      case '\$in':
        if (operandValue is List && !operandValue.contains(entityValue)) {
          return false;
        }
        break;
      case 'not_in':
      case '\$nin':
        if (operandValue is List && operandValue.contains(entityValue)) {
          return false;
        }
        break;

      // String pattern matching operators
      case '\$like':
        if (entityValue is! String || operandValue is! String) return false;
        final pattern = operandValue.replaceAll('%', '.*');
        final regex = RegExp(pattern, caseSensitive: true);
        if (!regex.hasMatch(entityValue)) return false;
        break;
      case '\$ilike':
        if (entityValue is! String || operandValue is! String) return false;
        final pattern = operandValue.toLowerCase().replaceAll('%', '.*');
        final regex = RegExp(pattern, caseSensitive: false);
        if (!regex.hasMatch(entityValue.toLowerCase())) return false;
        break;

      // Null checking operators
      case '\$isNull':
        final shouldBeNull = operandValue == true;
        final isNull = entityValue == null;
        if (shouldBeNull != isNull) return false;
        break;

      // Existence operators
      case '\$exists':
        // For our implementation, we consider a field to exist if it's not null
        final shouldExist = operandValue == true;
        final exists = entityValue != null;
        if (shouldExist != exists) return false;
        break;

      // Array/Collection operators
      case '\$contains':
        if (entityValue is List) {
          if (!entityValue.contains(operandValue)) return false;
        } else if (entityValue is String && operandValue is String) {
          if (!entityValue.contains(operandValue)) return false;
        } else {
          return false;
        }
        break;
      case '\$size':
        if (entityValue is List) {
          if (entityValue.length != operandValue) return false;
        } else if (entityValue is String) {
          if (entityValue.length != operandValue) return false;
        } else {
          return false;
        }
        break;

      // Logical operators (handled at higher level but included for completeness)
      case '\$not':
        if (operandValue is Map<String, dynamic>) {
          if (matchesOperator(entityValue, operandValue)) return false;
        } else {
          if (entityValue == operandValue) return false;
        }
        break;

      default:
        // Unknown operator, treat as equality
        if (entityValue != operandValue) return false;
    }
  }
  return true;
}

Operation withEntityId(Operation op, String id) => Operation(
      type: op.type,
      entityType: op.entityType.isNotEmpty ? op.entityType : op.lookupRef!.entityType,
      entityId: id,
      data: op.data,
      options: op.options,
    );

int compareEntities(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  dynamic orderBy,
) {
  if (orderBy is String) {
    // Simple single field ordering
    final parts = orderBy.split(' ');
    final field = parts[0];
    final direction = parts.length > 1 ? parts[1].toLowerCase() : 'asc';
    return compareSingleField(a, b, field, direction);
  } else if (orderBy is List) {
    // Multiple field ordering
    for (final orderSpec in orderBy) {
      if (orderSpec is Map<String, dynamic>) {
        final field = orderSpec.keys.first;
        final direction = orderSpec[field]?.toString().toLowerCase() ?? 'asc';
        final comparison = compareSingleField(a, b, field, direction);
        if (comparison != 0) return comparison;
      }
    }
    return 0;
  } else if (orderBy is Map<String, dynamic>) {
    // Single field with explicit direction
    final field = orderBy.keys.first;
    final direction = orderBy[field]?.toString().toLowerCase() ?? 'asc';
    return compareSingleField(a, b, field, direction);
  }

  return 0;
}

int compareSingleField(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  String field,
  String direction,
) {
  final aValue = a[field];
  final bValue = b[field];

  if (aValue == null && bValue == null) return 0;
  if (aValue == null) return direction == 'asc' ? -1 : 1;
  if (bValue == null) return direction == 'asc' ? 1 : -1;

  int comparison;
  if (aValue is Comparable && bValue is Comparable) {
    comparison = (aValue).compareTo(bValue);
  } else {
    // Fallback to string comparison
    comparison = aValue.toString().compareTo(bValue.toString());
  }

  return direction == 'desc' ? -comparison : comparison;
}

List<Map<String, dynamic>> processAggregations(
  List<Map<String, dynamic>> entities,
  Map<String, dynamic> aggregate,
  List<String>? groupBy,
) {
  if (groupBy != null && groupBy.isNotEmpty) {
    // Group by specified fields
    final groups = <String, List<Map<String, dynamic>>>{};

    for (final entity in entities) {
      final groupKey = groupBy
          .map((field) => entity[field]?.toString() ?? '')
          .join('|');
      groups.putIfAbsent(groupKey, () => []);
      groups[groupKey]!.add(entity);
    }

    // Apply aggregations to each group
    return groups.entries.map((entry) {
      final group = entry.value;
      final result = calculateAggregates(group, aggregate);

      // Add group fields to result
      final groupKeys = entry.key.split('|');
      for (int i = 0; i < groupBy.length && i < groupKeys.length; i++) {
        result[groupBy[i]] = parseValue(groupKeys[i]);
      }

      return result;
    }).toList();
  } else {
    // Apply aggregations to all entities
    return [calculateAggregates(entities, aggregate)];
  }
}

Map<String, dynamic> calculateAggregates(
  List<Map<String, dynamic>> entities,
  Map<String, dynamic> aggregate,
) {
  final result = <String, dynamic>{};

  for (final entry in aggregate.entries) {
    final aggregateType = entry.key;
    final field = entry.value;

    switch (aggregateType) {
      case 'count':
        result['count'] = entities.length;
        break;

      case 'sum':
        if (field is String && field != '*') {
          final values = entities
              .map((e) => e[field])
              .whereType<num>()
              .cast<num>();
          result['sum'] = values.isEmpty ? 0 : values.reduce((a, b) => a + b);
        }
        break;

      case 'avg':
        if (field is String && field != '*') {
          final values = entities
              .map((e) => e[field])
              .whereType<num>()
              .cast<num>();
          result['avg'] = values.isEmpty
              ? 0
              : values.reduce((a, b) => a + b) / values.length;
        }
        break;

      case 'min':
        if (field is String && field != '*') {
          final values = entities
              .map((e) => e[field])
              .whereType<Comparable>()
              .cast<Comparable>();
          if (values.isNotEmpty) {
            result['min'] = values.reduce(
              (a, b) => a.compareTo(b) < 0 ? a : b,
            );
          }
        }
        break;

      case 'max':
        if (field is String && field != '*') {
          final values = entities
              .map((e) => e[field])
              .whereType<Comparable>()
              .cast<Comparable>();
          if (values.isNotEmpty) {
            result['max'] = values.reduce(
              (a, b) => a.compareTo(b) > 0 ? a : b,
            );
          }
        }
        break;
    }
  }

  return result;
}

dynamic parseValue(String value) {
  // Try to parse as number
  if (value.isEmpty) return null;
  final intValue = int.tryParse(value);
  if (intValue != null) return intValue;
  final doubleValue = double.tryParse(value);
  if (doubleValue != null) return doubleValue;
  // Try to parse as boolean
  if (value.toLowerCase() == 'true') return true;
  if (value.toLowerCase() == 'false') return false;
  // Return as string
  return value;
}

Triple mapToTriple(Map<String, dynamic> row) {
  return Triple(
    entityId: row['entity_id'] as String,
    attribute: row['attribute'] as String,
    value: jsonDecode(row['value'] as String),
    txId: row['tx_id'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    retracted: (row['retracted'] as int) == 1,
    isLocalOnly: ((row['is_local_only'] as int?) ?? 0) == 1,
  );
}

/// Deep merge two maps, recursively merging nested maps
Map<String, dynamic> deepMerge(
  Map<String, dynamic> target,
  Map<String, dynamic> source,
) {
  final result = Map<String, dynamic>.from(target);

  for (final entry in source.entries) {
    final key = entry.key;
    final value = entry.value;

    if (value is Map<String, dynamic> &&
        result[key] is Map<String, dynamic>) {
      result[key] = deepMerge(result[key] as Map<String, dynamic>, value);
    } else {
      result[key] = value;
    }
  }

  return result;
}
