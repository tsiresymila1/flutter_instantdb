
## Unreleased

### Typed relations (nested-2)
- Added `@InstantLink` annotation for marking relation fields on `@InstantModel` classes. Cardinality is inferred from the field type (`List<T>` → to-many, `T` → to-one); the target must itself be an `@InstantModel`.
- Generator now emits a typed accessor getter per `@InstantLink` field (e.g. `TypedQuery<TodoTable> get todos => ...`) and a recursively-typed `fromRow` arm that maps included relation maps to `List<T>` (to-many) or `T?` (to-one). Un-included relations safely yield `[]` / `null` via `whereType<Map>` guard.
- Added `TypedQuery<E>.include((t) => t.relation.where(...).limit(n))` — serializes to the nested-1 engine's `include` map inside the `$` options, supporting nested `where`/`order`/`limit`/`offset` and recursive includes. Immutable: the source query is never mutated.
- Deferred: typed cursor pagination and `fields` projection on relation sub-queries (the engine ignores them on nested sets in nested-1 anyway).

### Relational reads (nested-1)
- Fixed `include` to resolve `link()`-created relations: an entity's relation triples are read directly and the targets fetched by id (with nested `where`/`order`/`limit` and recursive includes). The previous foreign-key-convention heuristic remains as a fallback.
- To-many links now reconstruct as a list of related entities/ids.

### Typed model codegen (Phase 6b)
- Added `@InstantModel`/`@InstantField` annotations and the `InstantModelTable<Self, Row>` base.
- Added a `flutter_instantdb_generator` package (build_runner) that emits a typed table + `getAll`/`watchAll` extension from an annotated model class, returning typed `List<Model>`.
- Flat models (primitive fields) for now; relation/nested fields are deferred (non-nullable relations are rejected with guidance).

### Typed query DSL (Phase 6a)
- Added a type-safe query builder: `Col<T>`, `Filter` (combine with `&`/`|`), `Order`, `InstantTable<Self>`, `TypedQuery<E>`.
- Added `db.queryTyped(...)` (reactive) and `db.queryOnceTyped(...)` (one-shot), compiling to the existing InstaQL maps.
- Compile-time safety: `$like`/`$ilike` only on `Col<String>`, comparisons only on `Col<Comparable>`, value types checked against the column type.

### Query operators (InstaQL parity)
- Added `$like` (case-sensitive) and `$ilike` (case-insensitive) string match operators with SQL `%`/`_` wildcards.
- Added `$not` operator (alias of `$ne`).
- Added `and` / `or` logical combinators in `where` clauses.
- Added dot-notation nested-field matching (e.g. `where: { 'todos.title': 'Run' }`).
- Existing `$nin` / `$exists` / `$eq` extensions remain supported.

### Query pagination & fields
- Added cursor pagination: `first`/`after`/`last`/`before` (+ `afterInclusive`/`beforeInclusive`) under a namespace's `$` options.
- Added `pageInfo` on `QueryResult` (`startCursor`/`endCursor`/`hasNextPage`/`hasPreviousPage` per namespace).
- Added `fields` projection: `$: { fields: ['title', 'status'] }` (id always included).
- Added `db.infiniteQuery(...)` accumulator + `InstantInfiniteBuilder` widget.

### Transactions (InstaML parity)
- Added chainable `lookup` target: `db.tx.profiles.lookup('email', 'a@b.com').update({...})` — upsert by unique attribute (also works with `merge`, `delete`, `link`, `unlink`).
- Added `{upsert: false}` strict mode: `db.tx.goals[id].update({...}, opts: TxOpts(upsert: false))` does not create the entity if it does not exist.
- Added `ruleParams`: `db.tx.docs[id].update({...}).ruleParams({...})`, forwarded to the server for permission rules.

### Connection status & local id
- Added `ConnectionStatus` enum (`connecting`/`opened`/`authenticated`/`closed`/`errored`) exposed via `db.connectionStatus` and the new `ConnectionStateBuilder` widget.
- Added persistent `db.getLocalId(name)` — a stable id per name that survives restarts (matches `useLocalId`).
- Deprecated `db.isOnline` (use `connectionStatus`; online == `authenticated`) and `db.getAnonymousUserId()` (use `getLocalId`). Both still work.

### Files & storage
- Added `db.storage` (`InstantStorage`): `uploadFile(path, bytes, {contentType, contentDisposition})`, `getDownloadUrl(path)`, `delete(path)`.
- Added the `InstantFile` model.
- `$files` is queryable like any namespace (`db.query({r'$files': {}})`); local file refs can be removed with `db.tx[r'$files'][id].delete()`.

## 1.1.2+1
### 🎉 Docs
Update docs
## 1.1.2
### 🎉 Docs
Full update docs
## 1.1.1
### 🎉 Docs
Partial update docs
## 1.1.0
### 🎉 Auth manager
Use runtime api url

## 1.0.0
### 🎉 Initial Release
