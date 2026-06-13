# Phase 1: Query Operators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add InstaQL `$like`, `$ilike`, `$not` operators plus `and`/`or` logical combinators and dot-notation nested field matching to the query engine's where-evaluation, matching `@instantdb/core`.

**Architecture:** Extract the current private `_evaluateWhereCondition` logic out of `QueryEngine` into a pure, top-level function `evaluateWhere(doc, where)` in a new file `lib/src/query/where_matcher.dart`. Pure function = directly unit-testable with no DB/sync setup. `QueryEngine` delegates to it. Existing operators (`$eq $ne $gt $gte $lt $lte $in $nin $exists $isNull`) are preserved with identical behavior; new ones are added alongside.

**Tech Stack:** Dart, `flutter_test`. No new dependencies.

**Source of truth:** `@instantdb/core/src/queryTypes.ts` (operator list), `@instantdb/core/src/instaql.ts` (semantics). Spec: `docs/superpowers/specs/2026-06-13-instantdb-parity-design.md` (Phase 1).

---

## File Structure

- **Create:** `lib/src/query/where_matcher.dart` — pure where-evaluation. One responsibility: given a document map and a where map, return whether the doc matches. Exposes `evaluateWhere(Map<String,dynamic> doc, Map<String,dynamic> where) -> bool`.
- **Create:** `test/where_matcher_test.dart` — unit tests for the matcher.
- **Modify:** `lib/src/query/query_engine.dart` — `_evaluateWhereCondition` (around line 511) becomes a thin delegator to `evaluateWhere`; add import.

---

## Task 1: Create the where matcher with existing-operator parity

**Files:**
- Create: `lib/src/query/where_matcher.dart`
- Test: `test/where_matcher_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/where_matcher_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/query/where_matcher.dart';

void main() {
  group('evaluateWhere - direct equality', () {
    test('matches direct field equality', () {
      expect(evaluateWhere({'title': 'Run'}, {'title': 'Run'}), isTrue);
      expect(evaluateWhere({'title': 'Run'}, {'title': 'Walk'}), isFalse);
    });

    test('empty where matches everything', () {
      expect(evaluateWhere({'a': 1}, {}), isTrue);
    });
  });

  group('evaluateWhere - comparison operators', () {
    test(r'$eq / $ne', () {
      expect(evaluateWhere({'n': 5}, {'n': {r'$eq': 5}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$ne': 5}}), isFalse);
      expect(evaluateWhere({'n': 5}, {'n': {r'$ne': 6}}), isTrue);
    });

    test(r'$gt / $gte / $lt / $lte', () {
      expect(evaluateWhere({'n': 5}, {'n': {r'$gt': 4}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$gt': 5}}), isFalse);
      expect(evaluateWhere({'n': 5}, {'n': {r'$gte': 5}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$lt': 6}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$lte': 5}}), isTrue);
    });

    test(r'$in / $nin', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$in': ['a', 'b']}}), isTrue);
      expect(evaluateWhere({'t': 'c'}, {'t': {r'$in': ['a', 'b']}}), isFalse);
      expect(evaluateWhere({'t': 'c'}, {'t': {r'$nin': ['a', 'b']}}), isTrue);
    });

    test(r'$exists / $isNull', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$exists': true}}), isTrue);
      expect(evaluateWhere({}, {'t': {r'$exists': false}}), isTrue);
      expect(evaluateWhere({'t': null}, {'t': {r'$isNull': true}}), isTrue);
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$isNull': false}}), isTrue);
    });

    test('non-comparable types do not throw, return false', () {
      expect(evaluateWhere({'n': 'abc'}, {'n': {r'$gt': 5}}), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/where_matcher_test.dart`
Expected: FAIL — `where_matcher.dart` does not exist / `evaluateWhere` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/query/where_matcher.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/where_matcher_test.dart`
Expected: PASS (all tests in Task 1 green).

- [ ] **Step 5: Commit**

```bash
git add lib/src/query/where_matcher.dart test/where_matcher_test.dart
git commit -m "feat(query): add pure where-matcher with existing-operator parity

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Add $like / $ilike / $not tests and verify

**Files:**
- Test: `test/where_matcher_test.dart` (append group)

The implementation from Task 1 already covers these operators; this task locks
them in with tests (TDD-after for code that was written minimal-complete in
Task 1 — these tests must pass immediately, proving the behavior).

- [ ] **Step 1: Add the test group**

Append to the `main()` body in `test/where_matcher_test.dart`:

```dart
  group('evaluateWhere - string match operators', () {
    test(r'$like is case-sensitive, % = any run', () {
      expect(evaluateWhere({'t': 'You got promoted!'},
          {'t': {r'$like': '%promoted!'}}), isTrue);
      expect(evaluateWhere({'t': 'Code a bunch'},
          {'t': {r'$like': '%promoted!'}}), isFalse);
      expect(evaluateWhere({'t': 'Hello'},
          {'t': {r'$like': 'hello'}}), isFalse); // case-sensitive
    });

    test(r'$like with _ matches single char', () {
      expect(evaluateWhere({'t': 'cat'}, {'t': {r'$like': 'c_t'}}), isTrue);
      expect(evaluateWhere({'t': 'cart'}, {'t': {r'$like': 'c_t'}}), isFalse);
    });

    test(r'$ilike is case-insensitive', () {
      expect(evaluateWhere({'t': 'Hello'},
          {'t': {r'$ilike': '%ELLO'}}), isTrue);
    });

    test(r'$like on null field returns false', () {
      expect(evaluateWhere({'t': null}, {'t': {r'$like': '%x'}}), isFalse);
      expect(evaluateWhere({}, {'t': {r'$like': '%x'}}), isFalse);
    });

    test(r'$not is alias of $ne', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$not': 'a'}}), isFalse);
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$not': 'b'}}), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/where_matcher_test.dart`
Expected: PASS (string-operator group green; proves Task 1 impl is correct).

- [ ] **Step 3: Commit**

```bash
git add test/where_matcher_test.dart
git commit -m "test(query): cover \$like/\$ilike/\$not operators

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Add and/or combinator tests and verify

**Files:**
- Test: `test/where_matcher_test.dart` (append group)

- [ ] **Step 1: Add the test group**

Append to the `main()` body:

```dart
  group('evaluateWhere - logical combinators', () {
    test('and requires all sub-clauses', () {
      final w = {'and': [{'a': 1}, {'b': 2}]};
      expect(evaluateWhere({'a': 1, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'a': 1, 'b': 9}, w), isFalse);
    });

    test('or requires at least one sub-clause', () {
      final w = {'or': [{'a': 1}, {'b': 2}]};
      expect(evaluateWhere({'a': 1, 'b': 9}, w), isTrue);
      expect(evaluateWhere({'a': 9, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'a': 9, 'b': 9}, w), isFalse);
    });

    test('logical keys AND with sibling field keys', () {
      final w = {'status': 'open', 'or': [{'p': 1}, {'p': 2}]};
      expect(evaluateWhere({'status': 'open', 'p': 1}, w), isTrue);
      expect(evaluateWhere({'status': 'closed', 'p': 1}, w), isFalse);
    });

    test('nested and/or', () {
      final w = {'or': [{'and': [{'a': 1}, {'b': 2}]}, {'c': 3}]};
      expect(evaluateWhere({'a': 1, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'c': 3}, w), isTrue);
      expect(evaluateWhere({'a': 1, 'b': 9, 'c': 9}, w), isFalse);
    });
  });
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/where_matcher_test.dart`
Expected: PASS (combinator group green).

- [ ] **Step 3: Commit**

```bash
git add test/where_matcher_test.dart
git commit -m "test(query): cover and/or logical combinators

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add dot-notation nested-field tests and verify

**Files:**
- Test: `test/where_matcher_test.dart` (append group)

- [ ] **Step 1: Add the test group**

Append to the `main()` body:

```dart
  group('evaluateWhere - dot-notation nested fields', () {
    test('matches nested map value', () {
      final doc = {'meta': {'priority': 'high'}};
      expect(evaluateWhere(doc, {'meta.priority': 'high'}), isTrue);
      expect(evaluateWhere(doc, {'meta.priority': 'low'}), isFalse);
    });

    test('matches if any element in a nested list satisfies', () {
      final doc = {'todos': [{'title': 'Run'}, {'title': 'Code'}]};
      expect(evaluateWhere(doc, {'todos.title': 'Code'}), isTrue);
      expect(evaluateWhere(doc, {'todos.title': 'Swim'}), isFalse);
    });

    test('missing nested path does not throw', () {
      expect(evaluateWhere({'a': 1}, {'x.y.z': 'v'}), isFalse);
      expect(evaluateWhere({'a': 1}, {'x.y': {r'$isNull': true}}), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/where_matcher_test.dart`
Expected: PASS (dot-notation group green).

- [ ] **Step 3: Commit**

```bash
git add test/where_matcher_test.dart
git commit -m "test(query): cover dot-notation nested field matching

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire QueryEngine to delegate to the matcher

**Files:**
- Modify: `lib/src/query/query_engine.dart` (import + `_evaluateWhereCondition` body around line 511-645)

- [ ] **Step 1: Add the import**

At the top of `lib/src/query/query_engine.dart`, after the existing
`import '../sync/sync_engine.dart';` line, add:

```dart
import 'where_matcher.dart';
```

- [ ] **Step 2: Replace the `_evaluateWhereCondition` method body**

Find the method that currently starts at:

```dart
  bool _evaluateWhereCondition(
    Map<String, dynamic> doc,
    Map<String, dynamic> where,
  ) {
```

Replace the ENTIRE method (from that signature through its closing `}` — it ends
just before `bool _queryAffectedByChange(`) with this delegating version:

```dart
  bool _evaluateWhereCondition(
    Map<String, dynamic> doc,
    Map<String, dynamic> where,
  ) {
    return evaluateWhere(doc, where);
  }
```

- [ ] **Step 3: Verify static analysis is clean**

Run: `flutter analyze lib/src/query/query_engine.dart lib/src/query/where_matcher.dart`
Expected: "No issues found!" (no unused-import warning — the import is used by Step 2; the old inline operator code is gone).

- [ ] **Step 4: Run the existing query engine test suite**

Run: `flutter test test/query_engine_advanced_test.dart`
Expected: PASS — existing where/filter behavior is preserved by the delegation (this is the regression guard for the refactor).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS — all suites green.

- [ ] **Step 6: Commit**

```bash
git add lib/src/query/query_engine.dart
git commit -m "refactor(query): delegate where-eval to pure where_matcher

Replaces inline operator switch in QueryEngine with the testable
evaluateWhere() function, adding \$like/\$ilike/\$not + and/or + dot-notation.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md` (top)
- Modify: `README.md` (query operators section, if present)

- [ ] **Step 1: Add a CHANGELOG entry**

Add to the top of `CHANGELOG.md` (below any existing unreleased header; use the
current package version line style already in the file):

```markdown
### Query operators (InstaQL parity)
- Added `$like` (case-sensitive) and `$ilike` (case-insensitive) string match operators with SQL `%`/`_` wildcards.
- Added `$not` operator (alias of `$ne`).
- Added `and` / `or` logical combinators in `where` clauses.
- Added dot-notation nested-field matching (e.g. `where: { 'todos.title': 'Run' }`).
- Existing `$nin` / `$exists` / `$eq` extensions remain supported.
```

- [ ] **Step 2: Update README query examples (only if a "where"/operators section exists)**

Run: `grep -n '\$in\|where:\|operators' README.md`
If a query/operators section exists, add a short example block near it:

````markdown
```dart
// String match + logical combinators
db.query({
  'todos': {
    'where': {
      'or': [
        {'title': {r'$ilike': '%urgent%'}},
        {'priority': {r'$gte': 8}},
      ],
    },
  },
});
```
````

If `grep` finds no such section, skip this step (do not invent a new section).

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: "No issues found!"

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document new query operators (\$like/\$ilike/\$not, and/or)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter test` — all green, including the new `test/where_matcher_test.dart`.
- `flutter analyze` — no issues.
- `QueryEngine._evaluateWhereCondition` delegates to `evaluateWhere`; no behavior regression in `query_engine_advanced_test.dart`.
- New operators (`$like`, `$ilike`, `$not`), `and`/`or`, and dot-notation all covered by passing tests.

## Next phase

Phase 2 (Tx completeness: chainable `lookup`, `ruleParams`, `upsert`) gets its
own plan, written just-in-time before execution per the spec's phase ordering.
