/// Pure InstaQL where-clause evaluator.
///
/// Given a document map and an InstaQL `where` map, returns whether the
/// document satisfies the clause. No DB/sync dependencies — directly testable.
///
/// Supported operators: $eq $ne $not $gt $gte $lt $lte $in $nin $exists
/// $isNull $like $ilike. Supported combinators: `and`, `or`. Field keys may
/// use dot-notation (e.g. 'todos.title') to match nested maps/lists; for a
/// list-valued segment, the clause matches if ANY element satisfies it.
bool evaluateWhere(Map<String, dynamic> doc, Map<String, dynamic> where) {
  for (final entry in where.entries) {
    final key = entry.key;
    final cond = entry.value;

    if (key == 'and') {
      if (cond is! List) return false;
      for (final sub in cond) {
        if (sub is Map<String, dynamic> && !evaluateWhere(doc, sub)) {
          return false;
        }
      }
      continue;
    }

    if (key == 'or') {
      if (cond is! List) return false;
      var any = false;
      for (final sub in cond) {
        if (sub is Map<String, dynamic> && evaluateWhere(doc, sub)) {
          any = true;
          break;
        }
      }
      if (!any) return false;
      continue;
    }

    final candidates = _resolveValues(doc, key);
    if (cond is Map) {
      final condMap = Map<String, dynamic>.from(cond);
      final matched = candidates.any(
        (v) => condMap.entries.every((op) => _matchOne(v, op.key, op.value)),
      );
      if (!matched) return false;
    } else {
      if (!candidates.contains(cond)) return false;
    }
  }
  return true;
}

/// Resolve a (possibly dotted) field path to the list of candidate values.
/// Missing paths resolve to `[null]` so presence operators behave correctly.
List<dynamic> _resolveValues(dynamic node, String path) {
  final parts = path.split('.');
  List<dynamic> current = [node];
  for (final part in parts) {
    final next = <dynamic>[];
    for (final n in current) {
      if (n is Map) {
        next.add(n.containsKey(part) ? n[part] : null);
      } else if (n is List) {
        for (final e in n) {
          if (e is Map) next.add(e.containsKey(part) ? e[part] : null);
        }
      }
    }
    current = next.isEmpty ? [null] : next;
  }
  return current;
}

bool _matchOne(dynamic v, String op, dynamic cmp) {
  switch (op) {
    case r'$eq':
      return v == cmp;
    case r'$ne':
    case r'$not':
      return v != cmp;
    case r'$gt':
      return _compare(v, cmp, (c) => c > 0);
    case r'$gte':
      return _compare(v, cmp, (c) => c >= 0);
    case r'$lt':
      return _compare(v, cmp, (c) => c < 0);
    case r'$lte':
      return _compare(v, cmp, (c) => c <= 0);
    case r'$in':
      return cmp is List && cmp.contains(v);
    case r'$nin':
      return cmp is List && !cmp.contains(v);
    case r'$exists':
      return cmp == true ? v != null : v == null;
    case r'$isNull':
      return cmp == true ? v == null : v != null;
    case r'$like':
      return _likeMatch(v, cmp, caseSensitive: true);
    case r'$ilike':
      return _likeMatch(v, cmp, caseSensitive: false);
    default:
      // Unknown operator — ignore (does not exclude the doc).
      return true;
  }
}

bool _compare(dynamic v, dynamic cmp, bool Function(int) test) {
  if (v is! Comparable || cmp is! Comparable) return false;
  try {
    return test(v.compareTo(cmp));
  } catch (_) {
    return false;
  }
}

bool _likeMatch(dynamic v, dynamic pattern, {required bool caseSensitive}) {
  if (v == null || pattern is! String) return false;
  // `%` and `_` are not regex metacharacters, so RegExp.escape leaves them
  // intact; translate them to regex wildcards afterwards.
  final escaped = RegExp.escape(pattern)
      .replaceAll('%', '.*')
      .replaceAll('_', '.');
  final re = RegExp('^$escaped\$', caseSensitive: caseSensitive);
  return re.hasMatch(v.toString());
}
