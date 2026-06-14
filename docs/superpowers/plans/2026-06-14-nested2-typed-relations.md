# Plan — nested-2: typed relation accessors & typed `include`

Spec: `docs/superpowers/specs/2026-06-14-nested2-typed-relations-design.md`.
Branch off `main` (phases 1–6b + nested-1 merged). TDD per task: failing test →
run → confirm fail → implement → confirm pass → commit. **No Co-Authored-By /
Claude trailer in any commit.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (or `fvm flutter`). Generator
unit tests: `cd flutter_instantdb_generator && dart test` (no build_runner).
Baseline: full `flutter test` has exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — those must stay the only
failures.

**DISK ~10 GiB free / 98% used.** If any command ENOSPCs, STOP and report BLOCKED
with the failing command — do NOT delete files to free space.

---

## Task 1 — Typed `.include` + serialization (pure Dart)

**Files**: `lib/src/typed/typed_query.dart`, `test/typed_query_test.dart`.

### 1a. Failing tests first (`test/typed_query_test.dart`)

Add a group `Typed include (nested-2)`:

```dart
test('include serializes nested where/order/limit under the $ options', () {
  final goals = _GoalsTable();
  final q = goals.query().include(
        (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
            .where((t) => t.n.gte(2))
            .order((t) => t.n.asc())
            .limit(1),
      );
  final m = q.toQuery();
  final opts = (m['goals'] as Map)[r'$'] as Map;
  final inc = opts['include'] as Map;
  expect(inc.keys, ['todos']);
  final todos = inc['todos'] as Map;
  expect(todos['where'], {'n': {r'$gte': 2}});
  expect(todos['order'], {'n': 'asc'});
  expect(todos['limit'], 1);
});

test('include nests recursively', () {
  final goals = _GoalsTable();
  final q = goals.query().include(
        (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
            .include((t) =>
                TypedQuery<_TagsTable>(_TagsTable(), relationAttr: 'tags')),
      );
  final inc = (((q.toQuery()['goals'] as Map)[r'$'] as Map)['include']) as Map;
  expect(((inc['todos'] as Map)['include'] as Map).keys, ['tags']);
});

test('include does not mutate the source query', () {
  final goals = _GoalsTable();
  final base = goals.query();
  base.include((g) =>
      TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos'));
  expect((base.toQuery()['goals'] as Map)[r'$'], isNot(contains('include')));
});
```

Add minimal local tables near the other test tables in the file (match the
existing hand-written table style — `InstantTable` subclasses with `Col` fields):

```dart
class _GoalsTable extends InstantTable<_GoalsTable> { _GoalsTable() : super('goals'); }
class _TodosTable extends InstantTable<_TodosTable> {
  _TodosTable() : super('todos');
  final n = const Col<int>('n');
}
class _TagsTable extends InstantTable<_TagsTable> { _TagsTable() : super('tags'); }
```

(If the file already defines comparable tables, reuse them — check the top of
`test/typed_query_test.dart` first.)

Run `flutter test test/typed_query_test.dart` → confirm the new tests FAIL to
compile (`include`/`relationAttr` undefined).

### 1b. Implement (`lib/src/typed/typed_query.dart`)

- Add fields after `_fields` (line ~91): `final String? _relationAttr;` and
  `final Map<String, dynamic>? _includes;`.
- Main ctor (line 93): change signature to
  `TypedQuery(this.table, {String? relationAttr})`, init
  `_relationAttr = relationAttr`, `_includes = null` (add both to the
  initializer list).
- Private `_` ctor (line 106): add `required String? relationAttr,` and
  `required Map<String, dynamic>? includes,` params + initializers.
- `_copyWith` (line 131): add `String? relationAttr,` and
  `Map<String, dynamic>? includes,` params; pass
  `relationAttr: relationAttr ?? _relationAttr` and
  `includes: includes ?? _includes` to `TypedQuery._`.
- Add the `include` method + `_includeOptions()` exactly as in the spec
  (§Design 2).
- In `toQuery()` `options` map (line 188), add:
  `if (_includes != null) 'include': _includes,`.

Run `flutter test test/typed_query_test.dart` → all pass. Run `flutter analyze
lib/src/typed/typed_query.dart` → clean.

**Commit**: `feat(typed): add include() to TypedQuery serializing nested relation queries`

---

## Task 2 — Typed include integration (real DB, hand-written tables)

**Files**: new `test/typed_relations_test.dart` only (no lib change — exercises
Task 1 + the nested-1 engine through `queryOnceTyped`).

### 2a. Failing test first

Mirror `test/model_table_test.dart` setup (sqflite-ffi, `InstantDB.init` with
`syncEnabled:false`, unique `persistenceDir`). Define hand-written
`InstantModelTable` subclasses for `goals` and `todos` with a `fromRow` that maps
the nested relation list using the **same dart:core-only guard** the generator
will emit (so this test also validates that mapping shape):

```dart
class _Todo { final String id; final String title; final int n;
  _Todo({required this.id, required this.title, required this.n}); }
class _TodoTable extends InstantModelTable<_TodoTable, _Todo> {
  _TodoTable() : super('todos');
  final n = const Col<int>('n');
  @override _Todo fromRow(Map<String, dynamic> m) =>
      _Todo(id: m['id'] as String, title: m['title'] as String, n: m['n'] as int);
}
class _Goal { final String id; final String title; final List<_Todo> todos;
  _Goal({required this.id, required this.title, required this.todos}); }
class _GoalTable extends InstantModelTable<_GoalTable, _Goal> {
  _GoalTable() : super('goals');
  TypedQuery<_TodoTable> get todos =>
      TypedQuery<_TodoTable>(_TodoTable(), relationAttr: 'todos');
  @override _Goal fromRow(Map<String, dynamic> m) => _Goal(
        id: m['id'] as String,
        title: m['title'] as String,
        todos: (m['todos'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(_TodoTable().fromRow)
                .toList() ??
            const <_Todo>[],
      );
}
```

Tests (seed with `db.tx['goals'/'todos'][id].update(...)` + `.link({'todos': [...]})`):

```dart
test('typed include populates a typed to-many relation', () async {
  // seed g1 + t1/t2 (n:1,2) + link
  final q = _GoalTable().query().include((g) => g.todos);
  final r = await db.queryOnceTyped(q);
  final goal = r.documents.firstWhere((d) => d['id'] == 'g1');
  final todos = _GoalTable().fromRow(goal).todos;
  expect(todos.map((t) => t.title).toSet(), {'Run', 'Lift'});
});

test('typed nested where narrows the included set', () async {
  // same seed
  final q = _GoalTable().query()
      .include((g) => g.todos.where((t) => t.n.gte(2)));
  final r = await db.queryOnceTyped(q);
  final todos = _GoalTable().fromRow(
      r.documents.firstWhere((d) => d['id'] == 'g1')).todos;
  expect(todos.map((t) => t.title), ['Lift']);
});

test('fromRow on an un-included parent yields an empty relation, not a crash',
    () async {
  // seed + link but query WITHOUT include
  final r = await db.queryOnceTyped(_GoalTable().query());
  final todos = _GoalTable().fromRow(
      r.documents.firstWhere((d) => d['id'] == 'g1')).todos;
  expect(todos, isEmpty);
});
```

Run → confirm FAIL (compile error on `g.todos` accessor return until Task-1
`include` exists; if Task 1 already landed, the accessor is local so these should
exercise real behavior — confirm they fail only if behavior is wrong). Since
Task 1 is merged, the realistic failure mode is none — if all pass immediately,
that's acceptable (the test still locks behavior); note it in the report.

### 2b. No implementation needed beyond Task 1

This task is a behavioral lock on the engine+typed seam. If a test fails,
systematic-debug it (do NOT loosen the assertion to pass).

Run `flutter test test/typed_relations_test.dart` → all pass. `flutter analyze
test/typed_relations_test.dart` → clean.

**Commit**: `test(typed): cover typed include populating relations end-to-end`

---

## Task 3 — `@InstantLink` annotation + generator support

**Files**: `lib/src/typed/annotations.dart`,
`flutter_instantdb_generator/lib/src/instant_generator.dart`,
`flutter_instantdb_generator/test/src/model_fixtures.dart`.

### 3a. Failing golden fixtures first (`model_fixtures.dart`)

- Add the `InstantLink` stand-in class (same shape as the runtime one — see 3b).
- Add a to-many fixture and pin its output:

```dart
@ShouldGenerate(r'''
class GoalTable extends InstantModelTable<GoalTable, Goal> {
  GoalTable() : super('goals');

  final id = const Col<String>('id');
  final title = const Col<String>('title');

  TypedQuery<TodoTable> get todos =>
      TypedQuery<TodoTable>(TodoTable(), relationAttr: 'todos');

  @override
  Goal fromRow(Map<String, dynamic> m) => Goal(
        id: m['id'] as String,
        title: m['title'] as String,
        todos: (m['todos'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(TodoTable().fromRow)
                .toList() ??
            const <Todo>[],
      );
}

extension GoalQueryX on TypedQuery<GoalTable> {
  Future<List<Goal>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(GoalTable().fromRow)
          .toList();

  ReadonlySignal<List<Goal>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(GoalTable().fromRow).toList());
  }
}
''')
@InstantModel('goals')
class Goal {
  final String id;
  final String title;
  @InstantLink()
  final List<Todo> todos;
  const Goal({required this.id, required this.title, required this.todos});
}
```

  > IMPORTANT: `@ShouldGenerate` is an exact-string match. The generator's emit
  > MUST match this byte-for-byte after `dart format`. Iterate the emit template
  > (3b) until the golden passes; if dartfmt would reflow the long `??`/`.map`
  > chain differently, adjust the **fixture string** to match the formatter's
  > actual output (run the generator, copy its exact output into the fixture).
  > The `Todo` model (the to-many target) must also be defined & `@InstantModel`
  > in this file so `TodoTable` resolves — reuse the existing `Todo` fixture.

- Add a to-one fixture (`Post` with `@InstantLink() Author? author`, target
  `Author` an `@InstantModel`) pinning the IIFE `fromRow` arm + `get author`
  accessor.
- Add a `@ShouldThrow` for `@InstantLink` on a target that is **not** an
  `@InstantModel`.
- Leave `BadModel` (non-nullable `Profile`, no `@InstantLink`) asserting its
  existing throw.

Run `cd flutter_instantdb_generator && dart test` → confirm the new fixtures FAIL
(generator does not yet emit accessors / still throws on the relation).

### 3b. Implement annotation + generator

`lib/src/typed/annotations.dart` — append:

```dart
/// Marks a relation field on an `@InstantModel`. Cardinality is inferred from the
/// field type (`List<T>` to-many, bare `T` to-one); the target table is
/// `${T}Table` (T must be an `@InstantModel`). [attr] overrides the stored
/// relation attribute (include key), defaulting to the field name.
class InstantLink {
  final String? attr;
  const InstantLink({this.attr});
}
```

`flutter_instantdb_generator/lib/src/instant_generator.dart`:

- Add `_LinkInfo { fieldName, attr, relatedTypeName, relatedTableName, toMany, nullable }`.
- Split field collection: keep `_modelFields` for scalars but make it also detect
  `@InstantLink` (metadata class name `'InstantLink'`) and route those into a
  links list. Add `_modelLinks(element)` returning `List<_LinkInfo>` (or return
  both from one pass). Key logic per linked field:
  - read `field.type`; if `type is InterfaceType && type.isDartCoreList` →
    `toMany = true`, `related = type.typeArguments.first`; else `toMany = false`,
    `related = type`.
  - `relatedTypeName = related.element!.name!`; `relatedTableName =
    '${relatedTypeName}Table'`.
  - verify `related.element` (ClassElement) has `@InstantModel` (reuse
    `_instantModelAnnotation` logic by name) → else
    `InvalidGenerationSourceError('Relation field "<f>" on <Model> targets
    "<T>", which is not an @InstantModel.', element: field)`.
  - `attr = <InstantLink.attr> ?? field.name` (read the annotation's `attr`
    field via `value.getField('attr')?.toStringValue()`).
  - `nullable = field.type.nullabilitySuffix == question`.
  - A non-scalar field WITHOUT `@InstantLink` keeps the existing throw/skip path.
- In `_generateForClass`: after the scalar `cols`/`ctorArgs` loops, emit a link
  accessor per `_LinkInfo` into a `links` buffer, and a `fromRow` arg per link
  into `ctorArgs`, using the spec templates (§Design 3). Splice the `links`
  buffer into the class body between the `Col` fields and `fromRow`. Make sure
  linked fields are included in the **named-ctor-param** validation (line 90-99)
  the same way scalars are — collect `{...scalarFieldNames, ...linkFieldNames}`.

Run `cd flutter_instantdb_generator && dart test` → iterate emit until all golden
fixtures pass (match dartfmt output exactly). Run `dart analyze` in the generator
package → clean.

**Commit**: `feat(codegen): generate typed relation accessors from @InstantLink`

---

## Task 4 — Codegen runtime end-to-end + docs

**Files**: `test/fixtures/sample.dart`, `test/fixtures/sample.instant.dart`,
`test/codegen_runtime_test.dart`, `CHANGELOG.md`, and the nested-2 spec's status.

### 4a. Extend the runtime fixture

- In `sample.dart`, add a second `@InstantModel` with a relation, e.g.:

```dart
@InstantModel('gadgets')
class Gadget {
  final String id;
  final String label;
  const Gadget({required this.id, required this.label});
}

@InstantModel('widgets')
class Widget2 {
  final String id;
  final String name;
  final int weight;
  @InstantLink()
  final List<Gadget> gadgets;
  const Widget2({
    required this.id,
    required this.name,
    required this.weight,
    required this.gadgets,
  });
}
```

- Regenerate `sample.instant.dart`:
  `flutter packages pub run build_runner build --delete-conflicting-outputs`.
  **If this ENOSPCs**, hand-write `sample.instant.dart` to match the generator's
  emit (now pinned by the Task-3 golden) — both `Widget2Table` (with `gadgets`
  accessor + nested `fromRow`) and `GadgetTable`. Report which path you took.

### 4b. Failing test first (`test/codegen_runtime_test.dart`)

Add a test (seed widgets + gadgets, link, include):

```dart
test('getAll with include populates typed nested relation', () async {
  await db.transact(db.tx['gadgets']['g1'].update({'label': 'A'}));
  await db.transact(db.tx['widgets']['w0'].link({'gadgets': ['g1']}));
  final widgets = await Widget2Table()
      .query()
      .include((w) => w.gadgets)
      .getAll(db);
  final w0 = widgets.firstWhere((w) => w.id == 'w0');
  expect(w0.gadgets.map((g) => g.label), ['A']);
});
```

(The existing `getAll` test must still pass — but note `Widget2`'s ctor now
requires `gadgets`; the un-included `getAll` path yields `gadgets: []` via the
guard, so the existing assertions are unaffected.)

Run `flutter test test/codegen_runtime_test.dart` → confirm the new test fails
before regeneration, passes after.

### 4c. Docs

- `CHANGELOG.md`: add a "Typed relations (nested-2)" section — `@InstantLink`,
  typed `.include`, nested `fromRow`; note deferred typed cursor/fields on
  relations.
- Flip the spec header `Status: design` → `Status: implemented`.

Run the FULL suite: `flutter test` (root) and `cd flutter_instantdb_generator &&
dart test`. Confirm root suite = prior pass count + new tests, with ONLY the 5
pre-existing `database_closed` failures; generator suite fully green.

**Commit**: `feat(codegen): typed include end-to-end + document nested-2`

---

## Definition of done

- `@InstantLink` generates relation accessors + recursively-typed `fromRow`.
- `TypedQuery.include(...)` compiles to the nested-1 `include` map; nested
  where/order/limit/offset + recursion serialize; cursors/fields deferred.
- Generator golden suite green (to-many, to-one, not-@InstantModel throw,
  BadModel unchanged). Runtime codegen test populates a typed nested list.
- Root `flutter test`: only the 5 pre-existing failures. No public API removed.
- No Co-Authored-By / Claude trailer in any commit. `example/pubspec.lock` not
  committed.
