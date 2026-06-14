# Changelog

## 0.2.0

- Emit `toMap(Model)` (scalar fields) on each generated table.
- Emit a `${Model}TxX` extension with `createModel` / `updateModel` /
  `mergeModel` for whole-model typed writes.
- Emit `static const ${field}Rel = RelationRef<...>(...)` per relation for typed
  `linkRel` / `unlinkRel`.
- Emit a `Table().tx(db)` convenience returning `db.txFor(this)`.
- Pairs with `flutter_instantdb` `^2.0.0`.

## 0.1.0

Initial release.

- Generates a typed `InstantModelTable` + a `${Model}QueryX` extension
  (`getAll`/`watchAll`) for every class annotated with `@InstantModel`.
- `@InstantField` overrides the stored attribute name for a field.
- `@InstantLink` declares relation fields: cardinality is inferred from the field
  type (`List<T>` → to-many, `T` → to-one), and the generator emits a typed
  relation accessor, a recursively-typed `fromRow` (`List<T>` / `T?`), and a
  `static const ${field}Rel = RelationRef<...>(...)` per relation.
- Typed writes: emits `toMap(Model)`, a `${Model}TxX` extension
  (`createModel` / `updateModel` / `mergeModel`), and a `Table().tx(db)`
  convenience.
- Pairs with the `flutter_instantdb` runtime package.
