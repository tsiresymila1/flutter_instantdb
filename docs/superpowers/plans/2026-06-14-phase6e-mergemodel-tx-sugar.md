# Plan — phase 6e: `mergeModel` + `Table().tx(db)` sugar

Spec: `docs/superpowers/specs/2026-06-14-phase6e-mergemodel-tx-sugar-design.md`.
Branch off `main` (6d merged + pushed). TDD per task: failing test → run → confirm
fail → implement → confirm pass → commit. **No Co-Authored-By / Claude trailer.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin`. Generator: `cd
flutter_instantdb_generator && /Users/tsiresymila/DevTools/flutter/bin/dart test`.
Baseline: full root `flutter test` = exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — stay the ONLY failures.

**DISK ~10 GiB free / 98% used.** ENOSPC → STOP + report BLOCKED, don't delete
files. build_runner known-blocked by pigeon → `sample.instant.dart` hand-maintained.

---

## Task 1 — Runtime: `mergeFromMap`

**Files**: `lib/src/typed/typed_tx.dart`, `test/typed_transaction_test.dart`.

### 1a. Failing test first

```dart
test('mergeFromMap builds a merge op and copies the map', () {
  final src = {'priority': 1};
  final chunk = TypedTx(t).mergeFromMap('t1', src);
  src['priority'] = 99; // must not leak
  final op = chunk.operations.single;
  expect(op.type, OperationType.merge);
  expect(op.entityId, 't1');
  expect(op.data, {'priority': 1});
});
```

Run `flutter test test/typed_transaction_test.dart` → FAIL (`mergeFromMap`
undefined).

### 1b. Implement

Add `mergeFromMap(String id, Map<String,dynamic> data, {TxOpts? opts})` to
`TypedTx<E>` (spec §Design 1) — delegates to
`EntityInstanceBuilder(_type, id).merge(Map.from(data), opts: opts)`.

Run → pass. Run FULL `flutter test` → only the 5 pre-existing failures.
`flutter analyze lib/src/typed/typed_tx.dart` → clean.

**Commit**: `feat(typed): add mergeFromMap whole-map deep-merge primitive`

---

## Task 2 — Generator: `tx(db)` method + `mergeModel`

**Files**: `flutter_instantdb_generator/lib/src/instant_generator.dart`,
`flutter_instantdb_generator/test/src/model_fixtures.dart`.

### 2a + 2b. Implement emit, then update goldens to actual output

- Emit a `tx` method in the class body after `toMap`:
  `TypedTx<$tableName> tx(InstantDB db) => db.txFor(this);`
- Emit `mergeModel` in the `${modelName}TxX` extension after `updateModel`:
  ```dart
  TransactionChunk mergeModel(String id, $modelName m) =>
      mergeFromMap(id, $tableName().toMap(m));
  ```

Exact-string goldens: implement emit, run `cd flutter_instantdb_generator && dart
test`, paste the generator's ACTUAL output into each of the 5 `@ShouldGenerate`
strings (Todo, Profile, Author, Goal, Post). The 3 `@ShouldThrow` are unaffected.
Iterate until green. `dart analyze lib` in the generator → clean.

**Commit**: `feat(codegen): emit Table.tx(db) sugar and mergeModel`

---

## Task 3 — Codegen runtime fixture + round-trip + docs

**Files**: `test/fixtures/sample.instant.dart`, `test/codegen_runtime_test.dart`,
`CHANGELOG.md`, 6e spec status.

### 3a. Update hand-maintained generated file

Add to `sample.instant.dart`, matching the Task-2 emit exactly: the `tx` method on
`GadgetTable` + `Widget2Table`, and `mergeModel` in `GadgetTxX` + `Widget2TxX`.
(Try build_runner once; if it ENOSPCs / pigeon-errors, hand-write to match the
Task-2 golden. Report which path.)

### 3b. Failing tests first (`test/codegen_runtime_test.dart`)

```dart
test('Table().tx(db) sugar createModel round-trips', () async {
  await db.transact(
    Widget2Table().tx(db).createModel(
          const Widget2(id: 'ws', name: 'S', weight: 4, gadgets: []),
        ),
  );
  final got =
      await Widget2Table().query().where((t) => t.id.eq('ws')).getAll(db);
  expect(got.single.name, 'S');
});

test('mergeModel merges a field', () async {
  await db.transact(Widget2Table().tx(db).createModel(
        const Widget2(id: 'wg', name: 'Before', weight: 1, gadgets: []),
      ));
  await db.transact(Widget2Table().tx(db).mergeModel(
        'wg', const Widget2(id: 'wg', name: 'After', weight: 5, gadgets: []),
      ));
  final got =
      await Widget2Table().query().where((t) => t.id.eq('wg')).getAll(db);
  expect(got.single.name, 'After');
  expect(got.single.weight, 5);
});
```

Run `flutter test test/codegen_runtime_test.dart` → fail before fixture update,
pass after. Run FULL `flutter test` → only the 5 pre-existing failures.

### 3c. Docs

- `CHANGELOG.md`: "mergeModel + Table().tx(db) sugar (6e)".
- Flip 6e spec `Status: design` → `Status: implemented`.

Run FULL suites: root `flutter test` (only 5 pre-existing failures) + generator
`dart test` (green).

**Commit**: `feat(codegen): tx sugar + mergeModel end-to-end + docs`

---

## Definition of done

- `Table().tx(db)` returns the typed builder; `mergeModel(id, Model)` deep-merges
  a whole model's scalar attrs; both round-trip through `db.transact`.
- Generator golden suite green (all 5 fixtures + sample regenerated). Root `flutter
  test`: only the 5 pre-existing failures. No public API removed. No Claude
  trailer. `example/pubspec.lock` not committed.
