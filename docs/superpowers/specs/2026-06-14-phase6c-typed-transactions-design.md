# phase 6c — Typed transactions

Status: implemented. The typed layer (phase6a query DSL, 6b codegen, nested-1..4
relational reads) covers READS. Writes are still untyped string-maps
(`db.tx['todos'][id].update({...})`). 6c adds compile-time-checked typed writes.

## Goal

A fluent, type-safe write builder per table, delegating to the existing untyped
transaction machinery:

```dart
final todos = TodoTable();
await db.transact(
  db.txFor(todos).create()
    ..set(todos.title, 'Run')      // String ✓
    ..set(todos.priority, 1),      // int ✓ — wrong type won't compile
);
await db.transact(db.txFor(todos).update('t1')..set(todos.priority, 2));
await db.transact(db.txFor(todos).delete('t1'));
await db.transact(
  db.txFor(profiles).lookup(profiles.email, 'a@b.com')   // upsert-by-unique
    ..set(profiles.name, 'Ana'),
);
```

`set<T>(Col<T> col, T value)` ties each value's type to its column's `T` — the
real type-safety win. No `Map<Col,dynamic>` (which would lose value typing and
need a `Col ==/hashCode` override).

## Decisions (locked)

- **Surface = fluent `set<T>(Col<T>, T)` builder**, cascade-friendly
  (`..set(..)..set(..)`). Pure runtime — no generator change, no `Col` equality
  change.
- **Whole-model writes deferred to 6d** (`createModel(Todo(...))` needs a
  generated `toMap` — separate generator phase).
- **Ops covered**: `create`, `update`, `merge`, `delete`, `link`, `unlink`, and
  typed `lookup` (upsert-by-unique-attr). `link`/`unlink` take a `String`
  relation name in v1 (no typed relation Col); the scalar `set` is where typing
  lands. Document.
- **Seam**: a tiny `ToTransaction` interface in core lets `transact` accept the
  typed builder without core importing the typed layer.

## Existing code facts (verified — trust these)

- **Untyped builders** (`lib/src/core/transaction_builder.dart`):
  - `EntityBuilder(entityType).create(Map data) → TransactionChunk` (lines 41-57):
    uses `data['id']` or generates a uuid; injects `__type`.
  - `EntityInstanceBuilder(entityType, id)` and
    `EntityInstanceBuilder.lookup(entityType, attribute, value)` (lines 66-89).
    Methods: `update(data, {TxOpts? opts})` (84), `merge(data, {opts})` (175),
    `link(Map)` (98), `unlink(Map)` (136), `delete()` (189) — each returns a
    `TransactionChunk`. `link`/`unlink` value may be a single id or a `List`.
- **`TransactionChunk`** (`lib/src/core/types.dart` lines 441-465): `const
  TransactionChunk(this.operations)`; has `merge`, `ruleParams`. Adding an
  instance method (interface impl) does not break the const ctor.
- **`Operation` / `OperationType`** (types.dart 233-341 / 215-230):
  `enum {add, update, delete, retract, link, unlink, merge}`; `Operation` has
  `type, entityType, entityId, data?, options?, lookupRef?`.
- **`LookupRef`** (types.dart 422-438): `{entityType, attribute, value}`.
  **`TxOpts`** (470-477): `{bool upsert = true}` → `toOptions()`.
- **`transact`** (`lib/src/core/instant_db.dart` line 265): `Future<TransactionResult>
  transact(dynamic transaction)`. Current unwrap (≈282-294):
  `if (transaction is TransactionChunk) operations = transaction.operations;
  else if (transaction is List<Operation>) operations = transaction; else throw`.
  Then `resolveTargetLookups` resolves `lookupRef` ops to concrete ids.
- **`db.id()`** (instant_db.dart 166) = `_uuid.v4()`.
- **Typed layer**: `Col<T>` (`typed_query.dart` 32) has `final String name`.
  `InstantTable<Self>` (65) has `entityType`. Generated `${Model}Table` exposes
  each scalar field as `final x = const Col<T>('attr')` and (post nested-2)
  relation accessors. **No `toMap`/`toRow` exists** (that's 6d).
- **Public barrel** (`lib/flutter_instantdb.dart`): exports
  `src/core/transaction_builder.dart` (4), `src/typed/typed_query.dart` (22),
  `annotations.dart` (23), `model_table.dart` (24). 6c adds a `typed_tx.dart`
  export.
- **Tests**: untyped tx tests in `test/transaction_builder_test.dart` (unit) +
  `test/tx_completeness_test.dart` (integration). Typed tests in
  `test/typed_*_test.dart`. New 6c tests → `test/typed_transaction_test.dart`.

## Design

### 1. Core seam — `ToTransaction` (`lib/src/core/types.dart`)

```dart
/// Anything convertible to a TransactionChunk, accepted by `db.transact`.
abstract interface class ToTransaction {
  TransactionChunk toTransactionChunk();
}
```
Make `TransactionChunk implements ToTransaction` with
`TransactionChunk toTransactionChunk() => this;`.

`transact` (instant_db.dart) — replace the `is TransactionChunk` branch:
```dart
if (transaction is ToTransaction) {
  operations = transaction.toTransactionChunk().operations;
} else if (transaction is List<Operation>) {
  operations = transaction;
} else { ...throw... }
```
(Existing `TransactionChunk` callers keep working — it now implements the
interface. No core→typed import.)

### 2. Typed builder (`lib/src/typed/typed_tx.dart`, new)

```dart
import '../core/types.dart';
import '../core/transaction_builder.dart';
import 'typed_query.dart';

enum _WriteKind { create, update, merge }

/// Typed transaction entry point for a table [E]. Delegates to the untyped
/// builder; `set<T>(Col<T>, T)` gives compile-time field/value checking.
class TypedTx<E extends InstantTable<E>> {
  final E _table;
  TypedTx(this._table);
  String get _type => _table.entityType;

  TypedWrite create({String? id}) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.create);
  TypedWrite update(String id) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.update);
  TypedWrite merge(String id) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.merge);

  /// Upsert-by-unique-attribute target (delegates to EntityInstanceBuilder.lookup).
  TypedWrite lookup<T>(Col<T> col, T value, {bool merge = false}) =>
      TypedWrite._(_type,
          lookupRef: LookupRef(entityType: _type, attribute: col.name, value: value),
          kind: merge ? _WriteKind.merge : _WriteKind.update);

  TransactionChunk delete(String id) =>
      EntityInstanceBuilder(_type, id).delete();
  TransactionChunk link(String id, String relation, Object targetId) =>
      EntityInstanceBuilder(_type, id).link({relation: targetId});
  TransactionChunk unlink(String id, String relation, Object targetId) =>
      EntityInstanceBuilder(_type, id).unlink({relation: targetId});
}

/// A pending typed write. Cascade `..set(col, value)` to fill fields, pass to
/// `db.transact` directly (implements [ToTransaction]).
class TypedWrite implements ToTransaction {
  final String _type;
  final String? _id;
  final LookupRef? _lookupRef;
  final _WriteKind _kind;
  final Map<String, dynamic> _fields = {};
  TxOpts? _opts;

  TypedWrite._(this._type, {String? id, LookupRef? lookupRef, required _WriteKind kind})
      : _id = id, _lookupRef = lookupRef, _kind = kind;

  /// Set a typed field. The value type is bound to the column's `T`.
  TypedWrite set<T>(Col<T> col, T value) { _fields[col.name] = value; return this; }

  /// Strict/upsert control for update/merge (ignored for create).
  TypedWrite opts(TxOpts o) { _opts = o; return this; }

  @override
  TransactionChunk toTransactionChunk() {
    switch (_kind) {
      case _WriteKind.create:
        return EntityBuilder(_type).create({if (_id != null) 'id': _id, ..._fields});
      case _WriteKind.update:
        return _instance().update(_fields, opts: _opts);
      case _WriteKind.merge:
        return _instance().merge(_fields, opts: _opts);
    }
  }

  EntityInstanceBuilder _instance() => _lookupRef != null
      ? EntityInstanceBuilder.lookup(_type, _lookupRef.attribute, _lookupRef.value)
      : EntityInstanceBuilder(_type, _id!);
}
```

### 3. `db.txFor` + export

`instant_db.dart`:
```dart
TypedTx<E> txFor<E extends InstantTable<E>>(E table) => TypedTx<E>(table);
```
`lib/flutter_instantdb.dart`: `export 'src/typed/typed_tx.dart';`.

Generated tables work as-is (`TodoTable() is InstantTable<TodoTable>`). A
generated `TodoTable().tx(db)` convenience accessor is deferred (would be a
generator change; `db.txFor(table)` covers it pure-runtime).

## Tests (`test/typed_transaction_test.dart`)

- **Unit (no DB)** — assert the built chunk:
  - `create()..set(t.title,'x')..set(t.priority,1)` → one `add` op, data has
    `title/priority/__type`, generated/explicit id.
  - `update('t1')..set(t.priority,2)` → one `update` op, entityId 't1',
    data `{priority:2}`.
  - `merge`, `delete`, `link`, `unlink` produce the right `OperationType` + data.
  - `lookup(t.email,'a@b').set(...)` → op carries a `lookupRef`.
- **Integration (sqflite-ffi, real `db.transact`)**:
  - typed create → `queryOnce` → fields present & typed values round-trip.
  - typed update by id changes the field.
  - typed lookup upsert creates-then-updates by unique attr (mirror
    `tx_completeness_test.dart`).
  - typed delete removes the entity.
- **Compile-time safety** is inherent (`set(t.priority, 'x')` won't compile); add
  a comment test documenting it (can't assert a compile error at runtime).
- Root suite stays at the **5 pre-existing** `database_closed` failures. Generator
  suite untouched/green (no generator change).

## Risks

- **`transact` accepts `ToTransaction`**: a `List<Operation>` still works; the
  else-branch error message should mention the accepted types. Existing
  `TransactionChunk` callers are unaffected (it now implements the interface).
- **`link`/`unlink` untyped relation name**: no compile-time check on the
  relation string in v1. Documented; typed relation writes can come with 6d.
- **Cascade returns**: `set`/`opts` return `this` so both chaining and cascade
  work; `db.transact(builder)` relies on `ToTransaction` — covered by the seam.

## Next

**6d**: whole-model writes (`createModel(Todo(...))`) via a generated `toMap`,
typed relation `link` via the relation accessor, and a generated
`Table().tx(db)` convenience.
