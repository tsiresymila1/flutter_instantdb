import 'package:logging/logging.dart';

import '../core/logging_config.dart';

/// Pure datalog-to-collection conversion helpers extracted from [SyncEngine].
///
/// These functions were the near-pure datalog sub-cluster of the sync engine:
/// they only read the attribute cache and emit log lines. Moved verbatim
/// (private `_`-prefixed methods renamed to public free functions); `_wsLogger`
/// became an optional `log` parameter and `_attributeCache` became the
/// `attributeCache` parameter. No logic was changed — only relocated.

/// Enhanced datalog conversion method that handles multiple format variations
Map<String, List<Map<String, dynamic>>> tryConvertDatalogToCollectionFormat(
  dynamic resultData,
  Map<String, Map<String, String>> attributeCache, {
  String? queryEntityType,
  Logger? log,
}) {
  final convertedData = <String, List<Map<String, dynamic>>>{};

  if (resultData is! Map<String, dynamic>) {
    log?.debug('ResultData is not a Map, cannot process');
    return convertedData;
  }

  final resultMap = resultData;

  // Try multiple datalog format variations
  final possibleDatalogPaths = [
    resultMap['datalog-result'],
    resultMap['datalog'],
    (resultMap['result'] as Map<String, dynamic>?)?['datalog-result'],
    (resultMap['data'] as Map<String, dynamic>?)?['datalog-result'],
  ];

  for (final datalogCandidate in possibleDatalogPaths) {
    if (datalogCandidate == null) continue;

    final joinRows = extractJoinRows(datalogCandidate, log: log);
    if (joinRows.isNotEmpty) {
      final entities =
          parseJoinRowsToEntities(joinRows, attributeCache, log: log);
      groupEntitiesByType(
        entities,
        convertedData,
        defaultType: queryEntityType,
        log: log,
      );
      log?.debug(
        'Successfully converted datalog format to ${convertedData.length} entity types',
      );
      return convertedData;
    }
  }

  // Try simple collection format as fallback - check for the query entity type first
  if (queryEntityType != null && resultMap[queryEntityType] is List) {
    convertedData[queryEntityType] = List<Map<String, dynamic>>.from(
      resultMap[queryEntityType] as List,
    );
    log?.debug('Using simple $queryEntityType format fallback');
    return convertedData;
  }

  // Legacy fallback for todos
  if (resultMap['todos'] is List) {
    convertedData['todos'] = List<Map<String, dynamic>>.from(
      resultMap['todos'] as List,
    );
    log?.debug('Using simple todos format fallback');
    return convertedData;
  }

  // Try any other collection-like arrays
  for (final entry in resultMap.entries) {
    if (entry.value is List && (entry.value as List).isNotEmpty) {
      final list = entry.value as List;
      if (list.first is Map) {
        convertedData[entry.key] = List<Map<String, dynamic>>.from(list);
        log?.debug(
          'Found collection format for entity type: ${entry.key}',
        );
      }
    }
  }

  return convertedData;
}

/// Robust join-rows extraction that handles multiple format variations
List<List<dynamic>> extractJoinRows(dynamic datalogCandidate, {Logger? log}) {
  if (datalogCandidate is! Map<String, dynamic>) {
    log?.debug(
      'Datalog candidate is not a Map: ${datalogCandidate.runtimeType}',
    );
    return [];
  }

  final joinRowsCandidates = [
    datalogCandidate['join-rows'],
    datalogCandidate['joinRows'],
    datalogCandidate['rows'],
  ];

  for (final candidate in joinRowsCandidates) {
    if (candidate is List) {
      // Handle nested array structures: [[[row1], [row2]]] vs [[row1], [row2]]
      if (candidate.isNotEmpty &&
          candidate[0] is List &&
          candidate[0].isNotEmpty &&
          candidate[0][0] is List) {
        log?.debug(
          'Found nested join-rows structure with ${candidate[0].length} rows',
        );
        return List<List<dynamic>>.from(candidate[0]);
      }
      log?.debug(
        'Found direct join-rows structure with ${candidate.length} rows',
      );
      return List<List<dynamic>>.from(candidate);
    }
  }

  log?.debug('No valid join-rows found in datalog candidate');
  return [];
}

/// Parse join-rows into entity objects
List<Map<String, dynamic>> parseJoinRowsToEntities(
  List<List<dynamic>> joinRows,
  Map<String, Map<String, String>> attributeCache, {
  Logger? log,
}) {
  final entityMap = <String, Map<String, dynamic>>{};
  log?.info('Parsing ${joinRows.length} join-rows into entities');

  for (final row in joinRows) {
    if (row.length >= 3) {
      // Entity ID might be a string or an array - handle both cases
      String entityId;
      if (row[0] is List) {
        // If entity ID is an array, use the first element as the actual ID
        entityId = (row[0] as List)[0].toString();
      } else {
        entityId = row[0].toString();
      }

      final attributeId = row[1].toString();
      final value = row[2];

      // Initialize entity map if needed
      entityMap.putIfAbsent(entityId, () => {'id': entityId});

      // Find attribute name from cache
      String? attrName;
      for (final nsEntry in attributeCache.entries) {
        for (final attrEntry in nsEntry.value.entries) {
          if (attrEntry.value == attributeId) {
            attrName = attrEntry.key;
            break;
          }
        }
        if (attrName != null) break;
      }

      if (attrName != null) {
        entityMap[entityId]![attrName] = value;
      } else {
        // For unknown attribute IDs, try to infer based on common patterns
        // This is a workaround for missing attribute definitions
        if (value is bool) {
          // Boolean values are likely 'completed' for todos
          entityMap[entityId]!['completed'] = value;
          log?.debug(
            'Inferred attribute "completed" for unknown ID: $attributeId',
          );
        } else {
          log?.debug(
            'Unknown attribute ID in query response: $attributeId with value: $value',
          );
        }
      }
    }
  }

  final entities = entityMap.values.toList();
  log?.info('Reconstructed ${entities.length} entities from join-rows');
  return entities;
}

/// Group entities by type for collection format
void groupEntitiesByType(
  List<Map<String, dynamic>> entities,
  Map<String, List<Map<String, dynamic>>> convertedData, {
  String? defaultType,
  Logger? log,
}) {
  final typeCount = <String, int>{};
  for (final entity in entities) {
    // Use __type field if present, otherwise use the query's entity type, fallback to 'todos'
    final entityType = entity['__type'] as String? ?? defaultType ?? 'todos';
    convertedData.putIfAbsent(entityType, () => []);
    convertedData[entityType]!.add(entity);
    typeCount[entityType] = (typeCount[entityType] ?? 0) + 1;
  }

  if (typeCount.isNotEmpty) {
    log?.info(
      '📊 Grouped entities by type: ${typeCount.entries.map((e) => '${e.key}(${e.value})').join(', ')}',
    );
  }
}
