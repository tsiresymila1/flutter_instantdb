/// Pure cursor-pagination + field-projection over an already-ordered list.
///
/// Cursors are modeled offline as an entity `id`'s position in the ordered set
/// (the server issues opaque cursors; offline we use id-position, which is
/// stable for a given order). Returns the sliced window plus a `pageInfo` map
/// matching @instantdb/core `PageInfoResponse`.
class PageResult {
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> pageInfo;
  const PageResult(this.items, this.pageInfo);
}

int _indexOfId(List<Map<String, dynamic>> rows, String id) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i]['id'] == id) return i;
  }
  return -1;
}

Map<String, dynamic> _project(Map<String, dynamic> row, List<String> fields) {
  final out = <String, dynamic>{'id': row['id']};
  for (final f in fields) {
    if (row.containsKey(f)) out[f] = row[f];
  }
  return out;
}

PageResult paginate(
  List<Map<String, dynamic>> ordered, {
  int? first,
  int? last,
  String? after,
  String? before,
  bool afterInclusive = false,
  bool beforeInclusive = false,
  int? offset,
  int? limit,
  List<String>? fields,
}) {
  final total = ordered.length;
  final hasCursorKeys =
      first != null || last != null || after != null || before != null;

  var startIdx = 0;
  var endIdx = total; // exclusive

  // Unknown cursors (id not found in the ordered set) are ignored: the window keeps its default bound.
  if (after != null) {
    final i = _indexOfId(ordered, after);
    if (i >= 0) startIdx = afterInclusive ? i : i + 1;
  }
  if (before != null) {
    final i = _indexOfId(ordered, before);
    if (i >= 0) endIdx = beforeInclusive ? i + 1 : i;
  }
  if (startIdx > endIdx) startIdx = endIdx;

  // first/last narrow the [startIdx, endIdx) window.
  if (first != null && first >= 0 && (endIdx - startIdx) > first) {
    endIdx = startIdx + first;
  }
  if (last != null && last >= 0 && (endIdx - startIdx) > last) {
    startIdx = endIdx - last;
  }

  // offset/limit only when no cursor keys are used.
  if (!hasCursorKeys) {
    if (offset != null && offset > 0) {
      startIdx = (startIdx + offset).clamp(0, endIdx);
    }
    if (limit != null && limit > 0 && (endIdx - startIdx) > limit) {
      endIdx = startIdx + limit;
    }
  }

  final window = ordered.sublist(startIdx, endIdx);
  final items = fields == null
      ? window
      : window.map((r) => _project(r, fields)).toList();

  final pageInfo = <String, dynamic>{
    'startCursor': window.isNotEmpty ? window.first['id'] : null,
    'endCursor': window.isNotEmpty ? window.last['id'] : null,
    'hasNextPage': endIdx < total,
    'hasPreviousPage': startIdx > 0,
  };

  return PageResult(items, pageInfo);
}
