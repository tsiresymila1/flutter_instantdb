# phase 6d — Whole-model typed writes + typed relation link

Status: design. Extends 6c (typed tx builder) with generator-backed ergonomics:
(1) `createModel(Model)`/`updateModel(id, Model)` via a generated `toMap`;
(2) typed relation link via a generated `RelationRef` handle. The low-value
`Table().tx(db)` sugar is **trimmed** (`db.txFor(table)` already covers it).

## Goal

```dart
// Feature 1 — whole-model writes (scalars; relations are separate link ops)
await db.transact(
  db.txFor(todos).createModel(Todo(id: db.id(), title: 'Run', priority: 1)),
);
await db.transact(
  db.txFor(todos).updateModel('t1', Todo(id: 't1', title: 'Run', priority: 2)),
);

// Feature 2 — typed relation link
await db.transact(db.txFor(goals).linkRel('g1', GoalTable.todosRel, ['t1', 't2']));
await db.transact(db.txFor(goals).unlinkRel('g1', GoalTable.todosRel, 't1'));
```

## Decisions (locked)

- **`toMap` = scalar fields only** (incl. `id`); relations excluded (writes go
  through `linkRel`/`unlinkRel`). The generator emits `toMap(Model m)` on the
  table + a `${Model}TxX` extension calling new runtime primitives.
- **No base-class / `TypedTx` generic change.** `createModel`/`updateModel` live
  in the *generated* `${Model}TxX` extension on `TypedTx<${Model}Table>`,
  delegating to new runtime methods `createFromMap`/`updateFromMap`. Hand-written
  `InstantModelTable` subclasses (in tests) are untouched.
- **Typed link via `RelationRef<R>`** (a small public handle holding the relation
  `attr`), generated as a `static const` per relation. `linkRel`/`unlinkRel` are
  runtime methods on `TypedTx`.
- **`Table().tx(db)` sugar trimmed** → 6e if ever wanted.

## Existing code facts (verified — trust these)

- **Generator `_generateForClass`** (`flutter_instantdb_generator/lib/src/instant_generator.dart`
  ~lines 108-205): builds `cols` (scalar `Col`s, line 114), `linkAccessors`
  (relation getters, line 126), `ctorArgs` (fromRow), assembles `classBody`
  (cols + blank + linkAccessors), then returns a template with the class
  (`fromRow`) + `${modelName}QueryX` extension (getAll/watchAll). The relation
  accessor emit (line 126-129):
  `TypedQuery<${l.relatedTableName}> get ${l.fieldName} =>
   TypedQuery<${l.relatedTableName}>(${l.relatedTableName}(), relationAttr: '${l.attr}');`
- **`_FieldInfo`** (~339-350): `fieldName`, `attr`, `dartType`, `nullable` — `id`
  is collected as a normal scalar field (model has `final String id`). So
  `toMap` emitting `'${attr}': m.${fieldName}` over `fields` naturally includes
  `id`.
- **`_LinkInfo`** (~352-367): `fieldName`, `attr`, `relatedTypeName`,
  `relatedTableName`, `toMany`, `nullable`.
- **6c runtime** (`lib/src/typed/typed_tx.dart`): `TypedTx<E extends InstantTable<E>>`
  holds `final E _table; String get _type => _table.entityType;` and delegates to
  `EntityBuilder(_type)` / `EntityInstanceBuilder(_type, id)` (imported from
  `transaction_builder.dart`). `TypedWrite.toTransactionChunk()` already copies
  the field map for update/merge. `Col<T>` + `InstantTable<Self>` are in
  `typed_query.dart` (both exported).
- **`db.txFor`** (`instant_db.dart` ~246):
  `TypedTx<E> txFor<E extends InstantTable<E>>(E table) => TypedTx<E>(table);`.
- **Golden fixtures** (`flutter_instantdb_generator/test/src/model_fixtures.dart`,
  exact-string `@ShouldGenerate`): `Todo`(todos), `Profile`(profiles),
  `Author`(authors), `Goal`(goals, to-many `todos`), `Post`(posts, to-one
  `author`). Plus the hand-maintained `test/fixtures/sample.instant.dart`
  (`Gadget`, `Widget2` with to-many `gadgets`). ALL must be regenerated to add
  `toMap` + (where relations exist) `RelationRef` consts + the `${Model}TxX`
  extension.
- build_runner is blocked by an unrelated pigeon error → `sample.instant.dart` is
  hand-maintained to match the generator's `dart_style` output.

## Design

### 1. Runtime (`lib/src/typed/typed_query.dart` + `lib/src/typed/typed_tx.dart`)

`typed_query.dart` — add a public relation handle:
```dart
/// A typed handle to a relation attribute, used by typed link/unlink writes.
/// Generated as `static const ${field}Rel = RelationRef<${Target}Table>('${attr}')`.
class RelationRef<R extends InstantTable<R>> {
  final String attr;
  const RelationRef(this.attr);
}
```

`typed_tx.dart` — add to `TypedTx<E>`:
```dart
/// Build a create op from a whole attribute map (e.g. a generated toMap).
/// `data['id']` (if present) is used as the entity id; [id] overrides it.
TransactionChunk createFromMap(Map<String, dynamic> data, {String? id}) =>
    EntityBuilder(_type).create({...data, if (id != null) 'id': id});

/// Build an update op from a whole attribute map.
TransactionChunk updateFromMap(String id, Map<String, dynamic> data,
        {TxOpts? opts}) =>
    EntityInstanceBuilder(_type, id)
        .update(Map<String, dynamic>.from(data), opts: opts);

/// Typed relation link/unlink. [targetIds] is one id or a List of ids.
TransactionChunk linkRel<R extends InstantTable<R>>(
        String id, RelationRef<R> rel, Object targetIds) =>
    EntityInstanceBuilder(_type, id).link({rel.attr: targetIds});
TransactionChunk unlinkRel<R extends InstantTable<R>>(
        String id, RelationRef<R> rel, Object targetIds) =>
    EntityInstanceBuilder(_type, id).unlink({rel.attr: targetIds});
```
(`RelationRef` reachable via the `typed_query.dart` import already in `typed_tx.dart`.)

### 2. Generator (`instant_generator.dart`)

Within `_generateForClass`, additionally emit:

- **`RelationRef` static consts** — one per `_LinkInfo`, placed in the class body
  after the relation accessors:
  ```dart
  static const ${l.fieldName}Rel =
      RelationRef<${l.relatedTableName}>('${escape(l.attr)}');
  ```
- **`toMap`** — a method in the class body after `fromRow`, over the scalar
  `fields` only (relations excluded):
  ```dart
  Map<String, dynamic> toMap($modelName m) => {
        for each scalar f: '${escape(f.attr)}': m.${f.fieldName},
      };
  ```
- **`${modelName}TxX` extension** — after the `${modelName}QueryX` extension:
  ```dart
  extension ${modelName}TxX on TypedTx<$tableName> {
    TransactionChunk createModel($modelName m) =>
        createFromMap($tableName().toMap(m));
    TransactionChunk updateModel(String id, $modelName m) =>
        updateFromMap(id, $tableName().toMap(m));
  }
  ```

The exact whitespace must match `dart_style` output — implement, run the
generator golden suite, and paste the generator's ACTUAL output into each
`@ShouldGenerate` string (and into `sample.instant.dart`).

### 3. `db` + exports

No `db` change (`txFor` already returns `TypedTx`). `RelationRef` is exported via
`typed_query.dart` (already in the barrel); the new `TypedTx` methods ship with
the existing `typed_tx.dart` export.

## Tests

- **Runtime unit** (`test/typed_transaction_test.dart`): with a hand-written
  table + a manual `RelationRef`:
  - `createFromMap({...})` → an `add` op with the data + `__type`.
  - `updateFromMap('t1', {...})` → an `update` op; mutating the source map after
    build does not leak (copy).
  - `linkRel('g1', RelationRef('todos'), ['t1','t2'])` → two `link` ops;
    `unlinkRel(... , 't1')` → one `unlink` op.
- **Generator golden** (`model_fixtures.dart`): every `@ShouldGenerate` updated to
  include `toMap`, the `${Model}TxX` extension, and (Goal/Post) `RelationRef`
  consts. Generator suite green.
- **Codegen runtime** (`test/codegen_runtime_test.dart` + `sample.instant.dart`
  regenerated): `db.txFor(Widget2Table()).createModel(Widget2(...))` round-trips;
  `db.txFor(Widget2Table()).linkRel('w0', Widget2Table.gadgetsRel, ['g1'])` links
  and a subsequent `include` shows the linked gadget.
- Root suite stays at the **5 pre-existing** `database_closed` failures. Generator
  suite green.

## Risks

- **Golden churn (main risk)**: 5 `@ShouldGenerate` fixtures + `sample.instant.dart`
  are exact-string. A single whitespace mismatch fails the golden test. Mitigation:
  run the generator, copy ACTUAL output. The runtime task (1) lands first and is
  independently testable.
- **`id` in `toMap`**: included. For `createModel`, `EntityBuilder.create` uses
  `data['id']` as the id (the model carries it). For `updateModel`, an `id`
  attribute in update data is harmless (the id triple equals the entity id;
  reconstruction already skips `id`). Document.
- **`createModel` ignores relations**: a model's relation fields are NOT written
  (links are separate `linkRel` ops). Documented.

## Next

**6e** (optional): `mergeModel`, `Table().tx(db)` sugar, typed relation handles
that also carry the target table factory for richer link ergonomics.
