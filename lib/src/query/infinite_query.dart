import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';

/// Accumulating infinite-query helper built on cursor pagination. Holds the
/// concatenated items across pages and advances via [loadMore], mirroring
/// @instantdb/react-common `useInfiniteQuery`.
class InstantInfiniteQuery {
  final Future<QueryResult> Function(Map<String, dynamic> query) _runOnce;
  final Map<String, dynamic> _baseQuery;
  final String _entityType;
  final int _pageSize;

  final Signal<List<Map<String, dynamic>>> items = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> hasMore = signal(true);

  String? _endCursor;
  bool _disposed = false;

  InstantInfiniteQuery({
    required Future<QueryResult> Function(Map<String, dynamic>) runOnce,
    required Map<String, dynamic> baseQuery,
    required String entityType,
    required int pageSize,
  })  : _runOnce = runOnce,
        _baseQuery = baseQuery,
        _entityType = entityType,
        _pageSize = pageSize {
    _loadFirst();
  }

  Map<String, dynamic> _queryWith({String? after}) {
    // Deep-ish copy of the base query, injecting first/after into the entity's
    // `$` options.
    final query = <String, dynamic>{};
    for (final entry in _baseQuery.entries) {
      query[entry.key] = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : entry.value;
    }
    final entity = Map<String, dynamic>.from(
      (query[_entityType] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final opts = Map<String, dynamic>.from(
      (entity[r'$'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    opts['first'] = _pageSize;
    if (after != null) opts['after'] = after;
    entity[r'$'] = opts;
    query[_entityType] = entity;
    return query;
  }

  Future<void> _loadFirst() async {
    isLoading.value = true;
    final result = await _runOnce(_queryWith());
    if (_disposed) return;
    final docs = _docsOf(result);
    items.value = docs;
    _updateCursor(result);
    isLoading.value = false;
  }

  /// Load the next page and append it. No-op when [hasMore] is false or a load
  /// is already in flight.
  Future<void> loadMore() async {
    if (!hasMore.value || isLoading.value || _endCursor == null) return;
    isLoading.value = true;
    final result = await _runOnce(_queryWith(after: _endCursor));
    if (_disposed) return;
    final docs = _docsOf(result);
    items.value = [...items.value, ...docs];
    _updateCursor(result);
    isLoading.value = false;
  }

  void _updateCursor(QueryResult result) {
    final pi = result.pageInfo?[_entityType] as Map?;
    _endCursor = pi?['endCursor'] as String?;
    hasMore.value = (pi?['hasNextPage'] as bool?) ?? false;
  }

  List<Map<String, dynamic>> _docsOf(QueryResult result) {
    final list = result.data?[_entityType];
    if (list is List) {
      return List<Map<String, dynamic>>.from(
        list.whereType<Map<String, dynamic>>(),
      );
    }
    return [];
  }

  void dispose() {
    _disposed = true;
    items.dispose();
    isLoading.dispose();
    hasMore.dispose();
  }
}
