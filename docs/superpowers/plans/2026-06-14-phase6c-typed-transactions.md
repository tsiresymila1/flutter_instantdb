# Plan — phase 6c: typed transactions

Spec: `docs/superpowers/specs/2026-06-14-phase6c-typed-transactions-design.md`.
Branch off `main` (nested-1..4 merged + pushed). TDD per task: failing test → run
→ confirm fail → implement → confirm pass → commit. **No Co-Authored-By / Claude
trailer in any commit.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (prepend to PATH) or `fvm`.
Baseline: full root `flutter test` has exactly **5 pre-existing** `database_closed`
failures in `test/query_engine_advanced_test.dart` — stay the ONLY failures. No
generator change (generator suite stays green, untouched).

**DISK ~10 GiB free / 98% used.** If any command ENOSPCs, STOP and report BLOCKED
with the failing command — do NOT delete files.

---

## Task 1 — Core seam: `ToTransaction` interface

**Files**: `lib/src/core/types.dart`, `lib/src/core/instant_db.dart`,
`test/transaction_builder_test.dart`.

### 1a. Failing test first (`test/transaction_builder_test.dart`)

```dart
test('transact accepts any ToTransaction', () {
  // a tiny fake implementing ToTransaction returns a known chunk
  final chunk = TransactionChunk([
    Operation(type: OperationType.add, entityType: 'todos', entityId: 'x',
        data: {'title': 'hi', '__type': 'todos'}),
  ]);
  expect(chunk, isA<ToTransaction>());
  expect(chunk.toTransactionChunk().operations, chunk.operations);
});
```

Run `flutter test test/transaction_builder_test.dart` → FAILS to compile
(`ToTransaction` / `toTransactionChunk` undefined).

### 1b. Implement

- `types.dart`: add
  ```dart
  abstract interface class ToTransaction {
    TransactionChunk toTransactionChunk();
  }
  ```
  and make `class TransactionChunk implements ToTransaction { ... TransactionChunk
  toTransactionChunk() => this; ... }`.
- `instant_db.dart` `transact` (~line 282): replace the `is TransactionChunk`
  branch with `is ToTransaction` → `operations = transaction.toTransactionChunk()
  .operations;`. Keep the `List<Operation>` branch and the else-throw (update the
  message to mention `ToTransaction`).

Run `flutter test test/transaction_builder_test.dart test/tx_completeness_test.dart`
→ pass (existing chunk-based transacts still work). `flutter analyze
lib/src/core/types.dart lib/src/core/instant_db.dart` → clean.

**Commit**: `feat(core): accept ToTransaction in transact via a small interface`

---

## Task 2 — Typed write builder + `db.txFor`

**Files**: new `lib/src/typed/typed_tx.dart`, `lib/src/core/instant_db.dart`
(add `txFor`), `lib/flutter_instantdb.dart` (export),
`test/typed_transaction_test.dart`.

### 2a. Failing tests first (`test/typed_transaction_test.dart`)

Define a hand-written table for unit tests (mirror `model_table_test.dart`):
```dart
class _Todos extends InstantTable<_Todos> {
  _Todos() : super('todos');
  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final priority = const Col<int>('priority');
  final email = const Col<String>('email');
}
```

Unit tests (no DB) — assert the chunk shape via `toTransactionChunk()`:
```dart
final t = _Todos();

test('typed create builds an add op with typed fields', () {
  final chunk = db_or_txFor(t).create(id: 't1')
      ..set(t.title, 'Run')
      ..set(t.priority, 1);
  final ops = chunk.toTransactionChunk().operations;
  expect(ops.single.type, OperationType.add);
  expect(ops.single.entityId, 't1');
  expect(ops.single.data, containsPair('title', 'Run'));
  expect(ops.single.data, containsPair('priority', 1));
  expect(ops.single.data, containsPair('__type', 'todos'));
});

test('typed update builds an update op', () {
  final w = TypedTx(t).update('t1')..set(t.priority, 2);
  final op = w.toTransactionChunk().operations.single;
  expect(op.type, OperationType.update);
  expect(op.entityId, 't1');
  expect(op.data, {'priority': 2});
});

test('typed merge / delete / link / unlink map to the right op types', () { ... });

test('typed lookup carries a lookupRef', () {
  final w = TypedTx(t).lookup(t.email, 'a@b.com')..set(t.title, 'X');
  final op = w.toTransactionChunk().operations.single;
  expect(op.type, OperationType.update);
  expect(op.lookupRef?.attribute, 'email');
  expect(op.lookupRef?.value, 'a@b.com');
});
```

> Use `TypedTx(t)` directly in unit tests (no DB needed). The `db.txFor(t)`
> convenience is exercised in the integration tests.

Integration tests (sqflite-ffi, real `db.transact` — mirror
`tx_completeness_test.dart` setup):
```dart
test('typed create round-trips through the DB', () async {
  await db.transact(db.txFor(t).create(id: 't1')
      ..set(t.title, 'Run')..set(t.priority, 3));
  final r = await db.queryOnce({'todos': {}});
  final todo = r.documents.firstWhere((d) => d['id'] == 't1');
  expect(todo['title'], 'Run');
  expect(todo['priority'], 3);
});

test('typed update changes a field', () async { /* create then update t1 */ });

test('typed lookup upserts by unique attr', () async {
  await db.transact(db.txFor(t).lookup(t.email, 'a@b.com')..set(t.title, 'First'));
  await db.transact(db.txFor(t).lookup(t.email, 'a@b.com')..set(t.title, 'Second'));
  final r = await db.queryOnce({'todos': {}});
  final matches = r.documents.where((d) => d['email'] == 'a@b.com').toList();
  expect(matches.length, 1);            // upsert, not duplicate
  expect(matches.single['title'], 'Second');
});

test('typed delete removes the entity', () async { /* create t1, delete t1, assert gone */ });
```

Run `flutter test test/typed_transaction_test.dart` → FAILS (TypedTx/txFor
undefined).

### 2b. Implement

- Create `lib/src/typed/typed_tx.dart` exactly per spec §Design 2 (`TypedTx<E>`,
  `TypedWrite implements ToTransaction`, `_WriteKind`). Imports: `../core/types.dart`,
  `../core/transaction_builder.dart`, `typed_query.dart`.
- `instant_db.dart`: add
  `TypedTx<E> txFor<E extends InstantTable<E>>(E table) => TypedTx<E>(table);`
  (near `queryTyped`/`queryOnceTyped`). Import `../typed/typed_tx.dart`.
- `lib/flutter_instantdb.dart`: add `export 'src/typed/typed_tx.dart';` in the
  typed-exports block.

Run `flutter test test/typed_transaction_test.dart` → all pass. Run FULL
`flutter test` → only the 5 pre-existing failures. `flutter analyze
lib/src/typed/typed_tx.dart lib/src/core/instant_db.dart` → clean.

**Commit**: `feat(typed): add typed transaction builder (txFor / set<T>)`

---

## Task 3 — Docs

**Files**: `CHANGELOG.md`, 6c spec status, nested-4 spec "Next" pointer.

- `CHANGELOG.md`: "Typed transactions (6c)" — `db.txFor(table)`,
  `set<T>(Col<T>,T)` fluent writes (create/update/merge/delete/link/unlink), typed
  `lookup` upsert, the `ToTransaction` seam. Note whole-model writes + typed
  relation link deferred to 6d.
- Flip 6c spec `Status: design` → `Status: implemented`.
- Update nested-4 spec "Next" line (6c now done → point to 6d).

Run FULL suites: root `flutter test` (only the 5 pre-existing failures) and
`cd flutter_instantdb_generator && /Users/tsiresymila/DevTools/flutter/bin/dart
test` (green, untouched).

**Commit**: `docs: document phase 6c typed transactions`

---

## Definition of done

- `db.txFor(table)` yields a typed builder; `set<T>(Col<T>,T)` gives compile-time
  field/value checking; create/update/merge/delete/link/unlink + typed lookup all
  produce correct ops and round-trip through `db.transact`.
- `transact` accepts `ToTransaction` (TransactionChunk + TypedWrite); List<Operation>
  still works.
- No generator change; generator suite green. Root `flutter test`: only the 5
  pre-existing failures. No public API removed. No Claude trailer.
  `example/pubspec.lock` not committed.
