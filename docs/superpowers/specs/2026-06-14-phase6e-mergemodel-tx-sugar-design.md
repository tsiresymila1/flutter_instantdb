# phase 6e — `mergeModel` + `Table().tx(db)` sugar

Status: design. Small ergonomic round-off of the typed-write layer (6c/6d):
(1) `mergeModel(id, Model)` (deep-merge a whole model); (2) a generated
`Table().tx(db)` convenience returning `db.txFor(table)`.

## Goal

```dart
final todos = TodoTable();
// (2) sugar: todos.tx(db) == db.txFor(todos)
await db.transact(todos.tx(db).createModel(Todo(id: db.id(), title: 'Run', priority: 1)));
// (1) deep-merge a whole model (only provided scalar attrs merged)
await db.transact(todos.tx(db).mergeModel('t1', Todo(id: 't1', title: 'Run', priority: 9)));
```

## Decisions (locked)

- **`mergeModel`** mirrors `updateModel` but uses `merge` (deep merge) — runtime
  `mergeFromMap` + generated `mergeModel` in the `${Model}TxX` extension.
- **`tx(InstantDB db)`** = a generated instance method on each table returning
  `db.txFor(this)`. Pure sugar; the table already imports `InstantDB`.
- **Name `tx`** (matches the API preview). A model field literally named `tx`
  would collide with this method — documented edge (same class as any reserved
  member name); extremely rare.

## Existing code facts (verified — trust these)

- **Generator `_generateForClass`** (`flutter_instantdb_generator/lib/src/instant_generator.dart`):
  class body assembles cols + accessors + `relationRefs` (line ~46:
  `static const ${l.fieldName}Rel = RelationRef<...>('${attr}')`), then the
  template (line ~71) emits the class with `fromRow` + `toMap` (line ~82) and the
  `${modelName}QueryX` + `${modelName}TxX` extensions. The `TxX` extension
  (line ~101) currently emits `createModel` + `updateModel`:
  ```dart
  extension ${modelName}TxX on TypedTx<$tableName> {
    TransactionChunk createModel($modelName m) =>
        createFromMap($tableName().toMap(m));
    TransactionChunk updateModel(String id, $modelName m) =>
        updateFromMap(id, $tableName().toMap(m));
  }
  ```
  The generated file already references `InstantDB` (QueryX `getAll`/`watchAll`).
- **6d runtime** (`lib/src/typed/typed_tx.dart`): `TypedTx<E>` has
  `createFromMap`/`updateFromMap`/`linkRel`/`unlinkRel` delegating to
  `EntityBuilder`/`EntityInstanceBuilder`. `EntityInstanceBuilder.merge(data,
  {opts})` exists (transaction_builder.dart line 175). `db.txFor<E extends
  InstantTable<E>>(E table)` returns `TypedTx<E>`.
- **Goldens** (`model_fixtures.dart`, exact-string): Todo, Profile, Author, Goal,
  Post — each `@ShouldGenerate` must gain the `tx` method (in class) + `mergeModel`
  line (in TxX). Hand-maintained `test/fixtures/sample.instant.dart` (Gadget,
  Widget2) likewise. 3 `@ShouldThrow` unaffected.

## Design

### 1. Runtime (`lib/src/typed/typed_tx.dart`)

Add to `TypedTx<E>` (next to `updateFromMap`):
```dart
/// Build a deep-merge op from a whole attribute map (e.g. a generated toMap).
TransactionChunk mergeFromMap(String id, Map<String, dynamic> data,
        {TxOpts? opts}) =>
    EntityInstanceBuilder(_type, id)
        .merge(Map<String, dynamic>.from(data), opts: opts);
```

### 2. Generator (`instant_generator.dart`)

- **`tx` method** — emit in the class body after `toMap`:
  ```dart
  TypedTx<$tableName> tx(InstantDB db) => db.txFor(this);
  ```
- **`mergeModel`** — emit in the `${Model}TxX` extension after `updateModel`:
  ```dart
  TransactionChunk mergeModel(String id, $modelName m) =>
      mergeFromMap(id, $tableName().toMap(m));
  ```

Match `dart_style` exactly — implement, run the golden suite, paste the actual
output into each `@ShouldGenerate` (and `sample.instant.dart`).

### 3. Exports / db

No change — `tx` lives on the generated table; `mergeFromMap` ships with the
existing `typed_tx.dart` export; `db.txFor` unchanged.

## Tests

- **Runtime unit** (`test/typed_transaction_test.dart`): `mergeFromMap('t1', {...})`
  → a `merge` op; mutating the source map after build does not leak (copy).
- **Generator golden**: all 5 `@ShouldGenerate` updated with the `tx` method +
  `mergeModel`; suite green.
- **Codegen runtime** (`test/codegen_runtime_test.dart` + regenerated
  `sample.instant.dart`): `Widget2Table().tx(db).createModel(...)` round-trips
  (sugar path); `tx(db).mergeModel(id, model)` updates a field.
- Root suite stays at the **5 pre-existing** `database_closed` failures. Generator
  green.

## Risks

- **Golden churn** (small): 5 fixtures + sample, exact-string. Run generator, paste
  actual output.
- **`tx` name collision**: a model field named `tx` collides with the generated
  method — documented edge, extremely rare.

## Next

Typed layer is feature-complete for reads + writes. Future work is non-typed
(sync robustness, schema parity) — out of this arc.
