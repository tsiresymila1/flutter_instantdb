# nested-1: Engine Relational Read Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `link()`-created relations readable through `include` by (A) reconstructing repeated attributes as lists and (B) resolving includes via the parent's relation triples (fetch targets by id), falling back to the existing FK heuristic.

**Architecture:** Two focused edits behind the existing `include` API. `TripleStore.queryEntities` accumulates multi-value attributes into a `List`; `QueryEngine._processIncludes` gains a forward-triple resolution path that runs before the FK-convention branches. No public API change.

**Tech Stack:** Dart, `flutter_test`, `sqflite_common_ffi`. No new dependencies.

**Source of truth:** Spec `docs/superpowers/specs/2026-06-13-nested1-relational-read-design.md`. Builds on `main`. Flutter binary at `/Users/tsiresymila/DevTools/flutter/bin` or `fvm flutter`.

---

## Existing code facts (verified — rely on these)

- `lib/src/storage/triple_store.dart`, in `queryEntities`, the entity-build loop is exactly:
  ```dart
      for (final triple in triples) {
        entity[triple.attribute] = triple.value;
      }
  ```
  `triple.value` is already JSON-decoded; `queryByEntity` returns triples ordered by `created_at ASC`. Scalars carry one non-retracted triple (because `update`/`merge` retract the prior value before inserting); `link()` inserts without retracting, so a to-many link has multiple non-retracted triples for the same attribute.
- `lib/src/query/query_engine.dart`, `_processIncludes(List<Map<String,dynamic>> entities, Map<String,dynamic> includes)`. Its loop body starts:
  ```dart
      for (final entity in entities) {
        for (final includeEntry in includes.entries) {
          final relationName = includeEntry.key;
          final relationQuery = includeEntry.value is Map
              ? Map<String, dynamic>.from(includeEntry.value as Map)
              : null;

          // Simple relation resolution based on naming conventions
          if (relationName.endsWith('s')) {
  ```
  The FK-convention branches follow (`if endsWith('s')` … `else` one-to-one). `_processIncludes` is invoked from `_queryEntities` only when `query['include'] != null`.
- `StorageInterface.queryEntities({String? entityType, String? entityId, ...})` fetches a single entity when `entityId` is passed (returns a list of 0 or 1). `_store` is the `StorageInterface`.
- `_applyQueryFilters(List<Map<String,dynamic>> data, Map<String,dynamic> query)` applies `where`/`order`/`limit`/`offset` to an in-memory list (pure; already used by the cache path).
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId:'test-app-id', config: InstantConfig(syncEnabled:false, persistenceDir:'test_db_<unique>'))`. The query format uses an `include` key: `db.queryOnce({'goals': {'include': {'todos': {}}}})`.
- **Commit messages must contain NO Co-Authored-By / Claude trailer.** Use the exact messages below.
- If `example/pubspec.lock` is dirtied, leave/revert it — never commit it.

---

## File Structure

- Modify: `lib/src/storage/triple_store.dart` — change A (reconstruction loop).
- Modify: `lib/src/query/query_engine.dart` — change B (`_processIncludes` forward path).
- Create: `test/relational_include_test.dart` — all behavior tests.
- Modify: `CHANGELOG.md`.

---

## Task 1: Faithful multi-value reconstruction (change A)

**Files:**
- Modify: `lib/src/storage/triple_store.dart`
- Test: `test/relational_include_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/relational_include_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Relational reconstruction (change A)', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_rel_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
    });

    tearDown(() async => db.dispose());

    test('a to-many link surfaces as a list of target ids', () async {
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(db.tx['todos']['t1'].update({'title': 'Run'}));
      await db.transact(db.tx['todos']['t2'].update({'title': 'Lift'}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));

      final r = await db.queryOnce({'goals': {}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = goal['todos'];
      expect(todos, isA<List>());
      expect((todos as List).map((e) => e.toString()).toSet(), {'t1', 't2'});
    });

    test('a scalar attribute stays scalar', () async {
      await db.transact(db.tx['goals']['g2'].update({'title': 'Solo'}));
      final r = await db.queryOnce({'goals': {}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g2');
      expect(goal['title'], 'Solo'); // not a list
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/relational_include_test.dart`
Expected: FAIL — the to-many test fails because reconstruction currently
collapses `todos` to a single id (last-write-wins).

- [ ] **Step 3: Change the reconstruction loop**

In `lib/src/storage/triple_store.dart`, find:

```dart
      for (final triple in triples) {
        entity[triple.attribute] = triple.value;
      }
```

Replace with:

```dart
      for (final triple in triples) {
        final attr = triple.attribute;
        if (entity.containsKey(attr)) {
          final existing = entity[attr];
          if (existing is List) {
            existing.add(triple.value);
          } else {
            entity[attr] = <dynamic>[existing, triple.value];
          }
        } else {
          entity[attr] = triple.value;
        }
      }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/relational_include_test.dart`
Expected: PASS (to-many surfaces as list; scalar stays scalar).

- [ ] **Step 5: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing `database_closed`
teardown ones in `test/query_engine_advanced_test.dart`. (If a previously-passing
test now sees a list where it expected a scalar, that indicates an unintended
multi-triple attribute — investigate, but the retract-on-update invariant should
keep scalars single.)

- [ ] **Step 6: Commit**

```bash
git add lib/src/storage/triple_store.dart test/relational_include_test.dart
git commit -m "fix(store): reconstruct repeated attributes as lists (to-many links)"
```

---

## Task 2: Include resolution via relation triples (change B)

**Files:**
- Modify: `lib/src/query/query_engine.dart`
- Test: `test/relational_include_test.dart` (append)

- [ ] **Step 1: Add failing tests**

Append to the `main()` body of `test/relational_include_test.dart` (a new group;
the first group has its own setUp/tearDown, so this group repeats the harness):

```dart
  group('Include via relation triples (change B)', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_inc_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
    });

    tearDown(() async => db.dispose());

    Future<void> seed() async {
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(db.tx['todos']['t1'].update({'title': 'Run', 'n': 1}));
      await db.transact(db.tx['todos']['t2'].update({'title': 'Lift', 'n': 2}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));
    }

    test('to-many include populates full related entities', () async {
      await seed();
      final r = await db.queryOnce({'goals': {'include': {'todos': {}}}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      expect(todos.length, 2);
      expect(todos.map((t) => t['title']).toSet(), {'Run', 'Lift'});
    });

    test('nested where/order/limit filters the related set', () async {
      await seed();
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {
              'where': {'n': {r'$gte': 2}},
              'order': {'n': 'asc'},
              'limit': 1,
            },
          },
        },
      });
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      expect(todos.length, 1);
      expect(todos.single['title'], 'Lift');
    });

    test('to-one link resolves to a single-element related list', () async {
      await db.transact(db.tx['posts']['p1'].update({'title': 'Hello'}));
      await db.transact(db.tx['users']['u1'].update({'name': 'Ana'}));
      await db.transact(db.tx['posts']['p1'].link({'owner': 'u1'}));

      final r = await db.queryOnce({'posts': {'include': {'owner': {}}}});
      final post = r.documents.firstWhere((p) => p['id'] == 'p1');
      final owner = (post['owner'] as List).cast<Map<String, dynamic>>();
      expect(owner.single['name'], 'Ana');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/relational_include_test.dart`
Expected: FAIL — `include` currently uses FK guessing and does not read the
relation triples, so `todos`/`owner` resolve to nothing (or the raw ids).

- [ ] **Step 3: Add the forward-triple path in `_processIncludes`**

In `lib/src/query/query_engine.dart`, find the loop body opening:

```dart
      for (final entity in entities) {
        for (final includeEntry in includes.entries) {
          final relationName = includeEntry.key;
          final relationQuery = includeEntry.value is Map
              ? Map<String, dynamic>.from(includeEntry.value as Map)
              : null;

          // Simple relation resolution based on naming conventions
          if (relationName.endsWith('s')) {
```

Insert the forward-triple block **between** the `relationQuery` assignment and
the `// Simple relation resolution based on naming conventions` comment:

```dart
          // Forward link: the parent already holds the relation triples (target
          // ids) — resolve by fetching those targets directly. Falls through to
          // the FK-convention heuristics below only when there is no such value.
          final relValue = entity[relationName];
          if (relValue != null) {
            final ids = relValue is List
                ? relValue.map((e) => e.toString()).toList()
                : [relValue.toString()];

            final related = <Map<String, dynamic>>[];
            for (final id in ids) {
              related.addAll(await _store.queryEntities(entityId: id));
            }

            var out = related;
            if (relationQuery != null) {
              out = _applyQueryFilters(related, relationQuery);
            }
            final nestedInclude =
                relationQuery?['include'] as Map<String, dynamic>?;
            if (nestedInclude != null) {
              out = await _processIncludes(out, nestedInclude);
            }
            entity[relationName] = out;
            continue;
          }

```

(The `continue` skips the FK-convention branches for this relation. The blank
line before `// Simple relation resolution` stays.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/relational_include_test.dart`
Expected: PASS (to-many populate, nested where/order/limit, to-one single).

- [ ] **Step 5: Add a deep-nested test**

Append to the same `group('Include via relation triples (change B)', ...)`:

```dart
    test('deep nested include populates two levels', () async {
      await db.transact(db.tx['goals']['g9'].update({'title': 'G'}));
      await db.transact(db.tx['todos']['td9'].update({'title': 'T'}));
      await db.transact(db.tx['tags']['tg9'].update({'label': 'urgent'}));
      await db.transact(db.tx['todos']['td9'].link({'tags': ['tg9']}));
      await db.transact(db.tx['goals']['g9'].link({'todos': ['td9']}));

      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {'include': {'tags': {}}},
          },
        },
      });
      final goal = r.documents.firstWhere((g) => g['id'] == 'g9');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      final tags = (todos.single['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.single['label'], 'urgent');
    });
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/relational_include_test.dart`
Expected: PASS (deep nesting recurses).

- [ ] **Step 7: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing ones. The FK-convention
include path is unchanged (it only runs when the parent has no relation value).

- [ ] **Step 8: Verify analysis**

Run: `flutter analyze lib/src/query/query_engine.dart lib/src/storage/triple_store.dart`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
git add lib/src/query/query_engine.dart test/relational_include_test.dart
git commit -m "fix(query): resolve includes via relation triples with FK fallback"
```

---

## Task 3: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the Unreleased section in `CHANGELOG.md`:

```markdown
### Relational reads (nested-1)
- Fixed `include` to resolve `link()`-created relations: an entity's relation triples are read directly and the targets fetched by id (with nested `where`/`order`/`limit` and recursive includes). The previous foreign-key-convention heuristic remains as a fallback.
- To-many links now reconstruct as a list of related entities/ids.
```

- [ ] **Step 2: Verify and commit**

Run: `flutter analyze`
Expected: only pre-existing `info`/`warning` issues outside the files this change
touched.

```bash
git add CHANGELOG.md
git commit -m "docs: document relational include fix (nested-1)"
```

---

## Done criteria

- `flutter test test/relational_include_test.dart` — all green (reconstruction, to-many include, nested filters, to-one, deep nested).
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones.
- `flutter analyze` — no issues in the two modified lib files.
- `link()`-created relations resolve through `include`; to-many links reconstruct as lists; FK-convention includes still work; deep nesting recurses.
- No breaking public API change.
- No commit carries a Co-Authored-By / Claude trailer.

## Next

**nested-2**: `@InstantLink` annotation → generated typed relation accessors, `.include((g) => g.todos.where(...))` composition on `TypedQuery`, recursive typed `fromRow` populating `List<Todo>`.
