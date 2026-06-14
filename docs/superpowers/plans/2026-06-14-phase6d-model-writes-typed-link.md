# Plan — phase 6d: whole-model typed writes + typed relation link

Spec: `docs/superpowers/specs/2026-06-14-phase6d-model-writes-typed-link-design.md`.
Branch off `main` (6c merged + pushed). TDD per task: failing test → run → confirm
fail → implement → confirm pass → commit. **No Co-Authored-By / Claude trailer.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (prepend to PATH) or `fvm`.
Generator: `cd flutter_instantdb_generator && /Users/tsiresymila/DevTools/flutter/bin/dart test`.
Baseline: full root `flutter test` has exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — stay the ONLY failures.

**DISK ~10 GiB free / 98% used.** If any command ENOSPCs, STOP and report BLOCKED
with the failing command — do NOT delete files. build_runner is known-blocked by
a pigeon error; `sample.instant.dart` is hand-maintained to match goldens.

---

## Task 1 — Runtime: `RelationRef` + whole-map / link primitives

**Files**: `lib/src/typed/typed_query.dart`, `lib/src/typed/typed_tx.dart`,
`test/typed_transaction_test.dart`. No generator change in this task.

### 1a. Failing tests first (`test/typed_transaction_test.dart`)

In the unit group (hand-written `_Todos extends InstantTable` already exists; add
a manual `RelationRef`):

```dart
test('createFromMap builds an add op with the whole map', () {
  final chunk = TypedTx(t).createFromMap({'id': 't1', 'title': 'Run', 'priority': 1});
  final op = chunk.operations.single;
  expect(op.type, OperationType.add);
  expect(op.entityId, 't1');
  expect(op.data, containsPair('title', 'Run'));
  expect(op.data, containsPair('__type', 'todos'));
});

test('updateFromMap builds an update op and copies the map', () {
  final src = {'priority': 1};
  final chunk = TypedTx(t).updateFromMap('t1', src);
  src['priority'] = 99; // must not leak into the built op
  expect(chunk.operations.single.data, {'priority': 1});
});

test('linkRel / unlinkRel build link/unlink ops via the RelationRef attr', () {
  const rel = RelationRef<_Todos>('todos');
  final linkOps = TypedTx(_Goals()).linkRel('g1', rel, ['t1', 't2']).operations;
  expect(linkOps.length, 2);
  expect(linkOps.every((o) => o.type == OperationType.link), isTrue);
  final unlinkOps = TypedTx(_Goals()).unlinkRel('g1', rel, 't1').operations;
  expect(unlinkOps.single.type, OperationType.unlink);
  expect(unlinkOps.single.data, {'todos': 't1'});
});
```

(Add a `_Goals extends InstantTable<_Goals>` helper if not present:
`class _Goals extends InstantTable<_Goals> { _Goals() : super('goals'); }`.)

Run `flutter test test/typed_transaction_test.dart` → confirm FAIL
(`RelationRef`/`createFromMap`/`linkRel` undefined).

### 1b. Implement

- `typed_query.dart`: add the `RelationRef<R extends InstantTable<R>>` class
  (spec §Design 1).
- `typed_tx.dart`: add `createFromMap`, `updateFromMap`, `linkRel`, `unlinkRel`
  to `TypedTx<E>` (spec §Design 1). `RelationRef` is reachable via the existing
  `typed_query.dart` import.

Run `flutter test test/typed_transaction_test.dart` → pass. Run FULL `flutter test`
→ only the 5 pre-existing failures. `flutter analyze lib/src/typed/typed_query.dart
lib/src/typed/typed_tx.dart` → clean.

**Commit**: `feat(typed): add RelationRef + whole-map create/update/link primitives`

---

## Task 2 — Generator: `toMap` + RelationRef consts + `${Model}TxX`

**Files**: `flutter_instantdb_generator/lib/src/instant_generator.dart`,
`flutter_instantdb_generator/test/src/model_fixtures.dart`.

### 2a. Failing golden fixtures first

Update EVERY `@ShouldGenerate` in `model_fixtures.dart` to the NEW expected output
(add `toMap`, the `${Model}TxX` extension, and — for Goal/Post — the
`RelationRef` static consts). Because this is exact-string, the practical TDD
loop is:
1. Write the emit code (2b) FIRST in a scratch form, OR
2. Update one fixture by hand-reasoning, run, read the harness diff, paste actual.

Recommended order: implement 2b, run `cd flutter_instantdb_generator && dart test`,
and for each failing golden copy the generator's ACTUAL output into its
`@ShouldGenerate` string. The `@ShouldThrow` fixtures are unaffected.

Expected additions per fixture (shape — match dart_style exactly):
- In the class, after `fromRow`:
  ```dart
  Map<String, dynamic> toMap(Todo m) => {
        'id': m.id,
        'title': m.title,
        'priority': m.priority,
      };
  ```
- For relation-bearing models (Goal: to-many `todos`; Post: to-one `author`),
  a static const in the class body (after the relation accessor):
  ```dart
  static const todosRel = RelationRef<TodoTable>('todos');
  ```
- After the QueryX extension:
  ```dart
  extension TodoTxX on TypedTx<TodoTable> {
    TransactionChunk createModel(Todo m) => createFromMap(TodoTable().toMap(m));
    TransactionChunk updateModel(String id, Todo m) =>
        updateFromMap(id, TodoTable().toMap(m));
  }
  ```

### 2b. Implement generator emit (`instant_generator.dart`)

In `_generateForClass`:
- Build a `relationRefs` buffer: for each `_LinkInfo`,
  `static const ${l.fieldName}Rel = RelationRef<${l.relatedTableName}>('${_escape(l.attr)}');`
  Splice into the class body AFTER the link accessors (extend the existing
  `classBody` assembly).
- Build a `toMapEntries` buffer over scalar `fields`:
  `"        '${_escape(f.attr)}': m.${f.fieldName},"`. Emit a `toMap` method
  after `fromRow` in the class template:
  ```
    Map<String, dynamic> toMap($modelName m) => {
  ${toMapEntries}
        };
  ```
- Append the `${modelName}TxX` extension after the `${modelName}QueryX` extension
  in the returned template.

Iterate until `cd flutter_instantdb_generator && dart test` is fully green (paste
actual output into goldens). `dart analyze` in the generator package → clean.

**Commit**: `feat(codegen): emit toMap, RelationRef consts, and createModel/updateModel`

---

## Task 3 — Codegen runtime fixture + round-trip

**Files**: `test/fixtures/sample.instant.dart` (regenerate to match Task-2 emit),
`test/codegen_runtime_test.dart`.

### 3a. Update the hand-maintained generated file

Add to `sample.instant.dart`, matching the generator's exact output from Task 2:
- `GadgetTable.toMap` + `GadgetTxX` extension.
- `Widget2Table.toMap` + `Widget2Table.gadgetsRel` (RelationRef) + `Widget2TxX`.

> If build_runner works (try once): regenerate. If it ENOSPCs or hits the pigeon
> error, hand-write to match the Task-2 golden shape. Report which path.

### 3b. Failing test first (`test/codegen_runtime_test.dart`)

```dart
test('createModel round-trips a whole model', () async {
  await db.transact(
    db.txFor(Widget2Table()).createModel(
      const Widget2(id: 'wm', name: 'M', weight: 7, gadgets: []),
    ),
  );
  final got = await Widget2Table().query().where((t) => t.id.eq('wm')).getAll(db);
  expect(got.single.name, 'M');
  expect(got.single.weight, 7);
});

test('linkRel links via the generated RelationRef', () async {
  await db.transact(db.tx['gadgets']['g1'].update({'label': 'A'}));
  await db.transact(
    db.txFor(Widget2Table()).createModel(
      const Widget2(id: 'wl', name: 'L', weight: 1, gadgets: []),
    ),
  );
  await db.transact(
    db.txFor(Widget2Table()).linkRel('wl', Widget2Table.gadgetsRel, ['g1']),
  );
  final w = (await Widget2Table().query()
          .where((t) => t.id.eq('wl'))
          .include((x) => x.gadgets)
          .getAll(db))
      .single;
  expect(w.gadgets.map((g) => g.label), ['A']);
});
```

Run `flutter test test/codegen_runtime_test.dart` → fail before the fixture
update, pass after. Run FULL `flutter test` → only the 5 pre-existing failures.

**Commit**: `test(codegen): cover createModel + linkRel end-to-end`

---

## Task 4 — Docs

- `CHANGELOG.md`: "Whole-model writes + typed relation link (6d)" — `createModel`/
  `updateModel` via generated `toMap`, `RelationRef` + `linkRel`/`unlinkRel`, the
  `createFromMap`/`updateFromMap` runtime primitives. Note `toMap` is scalar-only
  (relations via `linkRel`), `id` included, `Table().tx(db)` sugar deferred to 6e.
- Flip 6d spec `Status: design` → `Status: implemented`.

Run FULL suites: root `flutter test` (only 5 pre-existing failures) and generator
`dart test` (green).

**Commit**: `docs: document phase 6d model writes and typed link`

---

## Definition of done

- `db.txFor(table).createModel(Model)`/`updateModel(id, Model)` write scalar
  fields via a generated `toMap`; round-trip through `db.transact`.
- `db.txFor(table).linkRel(id, Table.relRel, ids)` / `unlinkRel` write typed
  relation links via generated `RelationRef` consts.
- Generator golden suite green (all 5 fixtures + sample regenerated). No public API
  removed. Root `flutter test`: only the 5 pre-existing failures. No Claude
  trailer. `example/pubspec.lock` not committed.
