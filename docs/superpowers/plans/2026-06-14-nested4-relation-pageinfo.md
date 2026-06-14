# Plan — nested-4: per-relation pageInfo

Spec: `docs/superpowers/specs/2026-06-14-nested4-relation-pageinfo-design.md`.
Branch off `main` (nested-1/2/3 merged + pushed). TDD per task: failing test →
run → confirm fail → implement → confirm pass → commit. **No Co-Authored-By /
Claude trailer in any commit.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (prepend to PATH) or `fvm`.
Baseline: full root `flutter test` has exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — stay the ONLY failures. No
generator change (generator suite stays green, untouched).

**DISK ~10 GiB free / 98% used.** If any command ENOSPCs, STOP and report BLOCKED
with the failing command — do NOT delete files.

---

## Task 1 — Engine: thread per-relation pageInfo sink (composite key)

**Files**: `lib/src/query/query_engine.dart`, `test/relational_include_test.dart`.

### 1a. Failing tests first (`test/relational_include_test.dart`)

Add a group `Include per-relation pageInfo (nested-4)` (mirror the nested-3 group
setup). **Use a SINGLE parent** so the composite key is deterministic (with
multiple parents the key reflects the last parent — see spec risk). Seed g1 +
t1/t2/t3 (n:1,2,3) all linked to g1, with deterministic ids:

```dart
test('paginated relation surfaces composite pageInfo', () async {
  // seed g1 + t1(n1)/t2(n2)/t3(n3) linked to g1
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'first': 1}}},
  });
  final pi = r.pageInfo?['goals.todos'];
  expect(pi, isNotNull);
  expect(pi!['hasNextPage'], true);
  expect(pi['hasPreviousPage'], false);
  expect(pi['startCursor'], 't1');
  expect(pi['endCursor'], 't1');
});

test('second page via after cursor flips hasPreviousPage', () async {
  // same seed
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'after': 't1', 'first': 1}}},
  });
  final todos = (r.documents.firstWhere((g) => g['id'] == 'g1')['todos']
          as List).cast<Map<String, dynamic>>();
  expect(todos.single['n'], 2);
  final pi = r.pageInfo!['goals.todos']!;
  expect(pi['hasPreviousPage'], true);
});

test('non-paginated include produces no composite pageInfo key', () async {
  final r = await db.queryOnce({'goals': {'include': {'todos': {}}}});
  expect(r.pageInfo?['goals.todos'], isNull);
});

test('deep nested paginated relation surfaces a dotted-path key', () async {
  // seed g9 + td9 linked to g9; tg9..tg11 linked to td9
  final r = await db.queryOnce({
    'goals': {
      'include': {
        'todos': {'include': {'tags': {'first': 1, 'order': {'label': 'asc'}}}},
      },
    },
  });
  expect(r.pageInfo?['goals.todos.tags'], isNotNull);
  expect(r.pageInfo!['goals.todos.tags']!['hasNextPage'], true);
});
```

(Adjust ids/fields to whatever the existing nested-3 seed helpers use; keep ids
literal so the cursor assertions are stable.)

Run `flutter test test/relational_include_test.dart` → confirm the new tests FAIL
(`r.pageInfo['goals.todos']` is null today — nested pageInfo discarded).

### 1b. Implement (`query_engine.dart`) — spec §Design

Apply the 6 edits in spec §Design exactly:
1. `_queryEntities` gains `Map<String, dynamic>? relationPageInfo` named param.
2. The `_processIncludes` call inside `_queryEntities` (line ~314) passes
   `pathPrefix: entityType, relationPageInfo: relationPageInfo`.
3. `_processIncludes` gains `{String? pathPrefix, Map<String, dynamic>? relationPageInfo}`.
4. After `out = page.items;` in the forward-triple paginate block, write
   `relationPageInfo['$pathPrefix.$relationName'] = page.pageInfo` when both
   non-null; drop the "deferred" comment.
5. The nested-include recursion threads the extended `pathPrefix` + sink.
6. `_processQuery` passes the fresh `pageInfo` map as `relationPageInfo:` to
   `_queryEntities`.

Run `flutter test test/relational_include_test.dart` → all pass (incl. nested-1/2/3
groups). Run FULL `flutter test` → only the 5 pre-existing failures.
`flutter analyze lib/src/query/query_engine.dart` → clean.

**Commit**: `feat(query): surface per-relation pageInfo under composite keys`

---

## Task 2 — Typed pass-through lock

**Files**: `test/typed_relations_test.dart` only (no lib change — `queryOnceTyped`
already returns `QueryResult` unchanged; this locks that pageInfo survives).

### 2a. Test

```dart
test('per-relation pageInfo is reachable through the typed path', () async {
  // seed g1 + t1/t2/t3 (n:1,2,3) linked
  final q = _GoalTable().query()
      .include((g) => g.todos.order((t) => t.n.asc()).first(1));
  final r = await db.queryOnceTyped(q);
  expect(r.pageInfo?['goals.todos']?['hasNextPage'], true);
});
```

Run `flutter test test/typed_relations_test.dart` → should pass once Task 1 is in
(no code change). If it FAILS, the typed path is dropping pageInfo — systematic-
debug rather than weakening the assertion.

**Commit**: `test(typed): lock per-relation pageInfo reachable via queryOnceTyped`

---

## Task 3 — Docs

**Files**: `CHANGELOG.md`, nested-4 spec status, nested-3 spec "Next" pointer.

- `CHANGELOG.md`: add a "Per-relation pageInfo (nested-4)" section — composite
  `pageInfo['<path>.<relation>']` read API, forward-triple only, typed exposure +
  per-parent windows deferred.
- Flip nested-4 spec `Status: design` → `Status: implemented`.
- Update the nested-3 spec "Next" line (pageInfo now done → point to 6c).

Run FULL suites: root `flutter test` (only the 5 pre-existing failures) and
`cd flutter_instantdb_generator && /Users/tsiresymila/DevTools/flutter/bin/dart
test` (green, untouched).

**Commit**: `docs: document nested-4 per-relation pageInfo`

---

## Definition of done

- Cursor-paginated nested relation surfaces pageInfo at
  `QueryResult.pageInfo['<parentType>.<relation>']`, dotted for depth.
- Non-paginated includes add no pageInfo key. Typed path preserves it.
- No `_lastPageInfo` race for nested (writes into the fresh per-query map).
- Root `flutter test`: only the 5 pre-existing failures. Generator green,
  untouched. No public API removed. No Claude trailer. `example/pubspec.lock` not
  committed.
