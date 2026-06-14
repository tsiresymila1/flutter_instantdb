# Plan — nested-3: cursor pagination & `fields` projection on relations

Spec: `docs/superpowers/specs/2026-06-14-nested3-relation-pagination-design.md`.
Branch off `main` (nested-1/nested-2 merged). TDD per task: failing test → run →
confirm fail → implement → confirm pass → commit. **No Co-Authored-By / Claude
trailer in any commit.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (prepend to PATH) or `fvm`.
Baseline: full root `flutter test` has exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — those stay the ONLY failures.
No generator change in this phase (generator suite must stay green, untouched).

**DISK ~10 GiB free / 98% used.** If any command ENOSPCs, STOP and report BLOCKED
with the failing command — do NOT delete files.

---

## Task 1 — Engine: nested cursor pagination + `fields` (untyped)

**Files**: `lib/src/query/query_engine.dart`, `test/relational_include_test.dart`.

### 1a. Failing tests first (`test/relational_include_test.dart`)

Add a group `Include cursor pagination + fields (nested-3)` (mirror the existing
`Include via relation triples (change B)` setup — sqflite-ffi, unique
`persistenceDir`). Seed a goal linked to several ordered todos, then:

```dart
test('nested first windows the related set after order', () async {
  // seed g1 + t1..t3 (n:1,2,3) all linked to g1
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'first': 1}}},
  });
  final todos = (r.documents.firstWhere((g) => g['id'] == 'g1')['todos']
          as List)
      .cast<Map<String, dynamic>>();
  expect(todos.length, 1);
  expect(todos.single['n'], 1);
});

test('nested after cursor advances the window', () async {
  // same seed; cursor = id of the n:1 todo
  final firstId = /* the t1 id */;
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'after': firstId, 'first': 1}}},
  });
  final todos = (r.documents.firstWhere((g) => g['id'] == 'g1')['todos']
          as List).cast<Map<String, dynamic>>();
  expect(todos.single['n'], 2);
});

test('nested fields projection drops non-whitelisted attrs (untyped)', () async {
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'fields': ['title']}}},
  });
  final t = (r.documents.firstWhere((g) => g['id'] == 'g1')['todos']
          as List).cast<Map<String, dynamic>>().first;
  expect(t.keys.toSet(), {'id', 'title'}); // 'n' dropped, id always kept
});

test('nested cursor does not double-apply limit', () async {
  // seed 3 todos; first:2 + limit:2 must yield 2 (not fewer from double-window)
  final r = await db.queryOnce({
    'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'first': 2}}},
  });
  final todos = (r.documents.firstWhere((g) => g['id'] == 'g1')['todos']
          as List).cast<Map<String, dynamic>>();
  expect(todos.map((t) => t['n']), [1, 2]);
});
```

(Use real seeded ids for the cursor — capture them from a prior `queryOnce` or
construct deterministic ids in the seed.)

Run `flutter test test/relational_include_test.dart` → confirm the new tests FAIL
(cursor/fields currently ignored on the nested set: `first`/`after` return all,
`fields` returns full maps).

### 1b. Implement (`query_engine.dart`, forward-triple path ~lines 369-373)

Replace the `if (relationQuery != null) { out = _applyQueryFilters(related,
relationQuery); }` block with the spec §Design 1 logic: compute
`useNestedPaginate`, strip `limit`/`offset` from the filter pass when paginating,
`_applyQueryFilters` for where/order, then `paginate(out, …)` owning
limit/offset/cursor/fields; `out = page.items`. Keep the nested-include recursion
AFTER, unchanged, operating on the windowed `out`. Update the stale "deferred"
comment (lines 370-372). `paginate` is already imported.

Run `flutter test test/relational_include_test.dart` → all pass (incl. the
pre-existing nested-1 tests). Run the FULL `flutter test` → confirm only the 5
pre-existing failures. `flutter analyze lib/src/query/query_engine.dart` → clean.

**Commit**: `feat(query): apply cursor pagination and fields to included relations`

---

## Task 2 — Typed: serialize cursors + forbid relation `.select()`

**Files**: `lib/src/typed/typed_query.dart`, `test/typed_query_test.dart`,
`test/typed_relations_test.dart`.

### 2a. Failing tests first

`test/typed_query_test.dart` — add to the nested-2 include group:

```dart
test('include serializes nested cursor keys', () {
  final goals = _GoalsTable();
  final q = goals.query().include(
        (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
            .order((t) => t.n.asc())
            .first(2)
            .after('cursor-1')
            .afterInclusive(true),
      );
  final todos = ((((q.toQuery()['goals'] as Map)[r'$'] as Map)['include'])
      as Map)['todos'] as Map;
  expect(todos['first'], 2);
  expect(todos['after'], 'cursor-1');
  expect(todos['afterInclusive'], true);
  expect(todos['order'], {'n': 'asc'});
  expect(todos.containsKey('fields'), isFalse); // never serialized
});

test('include throws if the relation sub-query uses select()', () {
  final goals = _GoalsTable();
  expect(
    () => goals.query().include(
          (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
              .select((t) => [t.n]),
        ),
    throwsArgumentError,
  );
});
```

(Ensure `_TodosTable` in this file exposes `n` — the nested-2 helper already
defines it; reuse it.)

`test/typed_relations_test.dart` — add:

```dart
test('typed include applies nested cursor window', () async {
  // seed g1 + t1..t3 (n:1,2,3) linked
  final q = _GoalTable().query()
      .include((g) => g.todos.order((t) => t.n.asc()).first(1));
  final r = await db.queryOnceTyped(q);
  final todos = _GoalTable().fromRow(
      r.documents.firstWhere((d) => d['id'] == 'g1')).todos;
  expect(todos.map((t) => t.n), [1]);
});
```

(The `_TodoTable` in that file needs an `n` Col + the `_Todo` model an `n`
field/ctor param — extend the nested-2 helper if absent.)

Run both test files → confirm the new tests FAIL (cursor keys absent from
`_includeOptions`; `.include` does not yet throw on `.select`).

### 2b. Implement (`lib/src/typed/typed_query.dart`)

- In `include<R>`, before building `merged`, add the `sub._fields != null` →
  `throw ArgumentError(...)` guard (spec §Design 2).
- Extend `_includeOptions()` to emit `first`/`last`/`after`/`before`/
  `afterInclusive`/`beforeInclusive` (NOT `fields`) — spec §Design 2.

Run both test files → pass. Run FULL `flutter test` → only the 5 pre-existing
failures. `flutter analyze lib/src/typed/typed_query.dart` → clean.

**Commit**: `feat(typed): serialize nested cursors; reject select() on relations`

---

## Task 3 — Docs

**Files**: `CHANGELOG.md`, the nested-3 spec status, and the stale "deferred"
notes in code/specs.

- `CHANGELOG.md`: add a "Relation pagination (nested-3)" section — nested cursor
  pagination + `fields` projection on the untyped path; typed `.include`
  serializes cursors; typed `.select()` on a relation throws; note the deferred
  per-relation `pageInfo` and the `fields`+deeper-include strip interaction.
- Flip the nested-3 spec `Status: design` → `Status: implemented`.
- Update the nested-1 spec line that says cursors on relations are deferred (it's
  now done) — leave a one-line pointer to nested-3. (Light touch; optional.)
- Confirm the `query_engine.dart` forward-triple comment no longer says
  "deferred" (done in Task 1).

Run the FULL suites: root `flutter test` (only the 5 pre-existing failures) and
`cd flutter_instantdb_generator && /Users/tsiresymila/DevTools/flutter/bin/dart
test` (still green — no generator change).

**Commit**: `docs: document nested-3 relation pagination`

---

## Definition of done

- Untyped `include` maps apply `first`/`last`/`after`/`before`/inclusive +
  `fields` to the nested set (forward-triple path); FK path already inherited it.
- Typed `.include` serializes nested cursor keys; typed `.select()` on a relation
  throws fail-fast; `fields` never serialized on the typed include.
- No double limit/offset (filter pass strips them when paginating).
- Root `flutter test`: only the 5 pre-existing failures. Generator suite green,
  untouched. No public API removed.
- No Co-Authored-By / Claude trailer in any commit. `example/pubspec.lock` not
  committed.
