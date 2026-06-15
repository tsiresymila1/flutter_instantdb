
## 2.1.0 - 2026-06-15

### Aggregations
- **`db.count(entityType, {where})`** and **`db.aggregate(entityType, {aggregates, where, groupBy})`** convenience APIs (`count`/`sum`/`avg`/`min`/`max`, optional `groupBy`). Fixed the cache/sync query path so `$aggregate`/`$groupBy` are honored over cached data instead of returning raw rows.

### Storage
- **`db.storage.list({where, order, limit, offset})`** lists files via the `$files` namespace (requires sync enabled).

### Auth / OAuth
- **`db.auth.createAuthorizationUrl({clientName, redirectUri, usePKCE, scopes})`** builds the OAuth redirect-flow URL with PKCE (S256), returning `OAuthFlow{url, codeVerifier, state}`.
- **Provider helpers**: `signInWithGoogle` / `signInWithApple` / `signInWithClerk` / `signInWithFirebase` (wrap `signInWithIdToken`).

### Reactive widgets
- New collaboration widgets (Flutter equivalents of React hooks): **`PresenceBuilder`** (`usePresence`), **`TopicListener`** (`useTopicEffect`), **`TypingIndicatorBuilder`**, **`ReactionsBuilder`**, **`CursorOverlay`** (`<Cursors>`), and **`OAuthButton`** (provider sign-in).

### Docs
- Documentation site now serves `/llms.txt` (index) and `/llms-full.txt` (full docs) generated from the docs content. Rewrote the README. Documented the typed link API without code generation.

## 2.0.0 - 2026-06-14

### Internal: store/sync refactor (no behavior change)
- Split `triple_store.dart` and `sync_engine.dart` into focused files (pure restructure, no behavior change). Extracted and added unit tests for the pure query/aggregate helpers (`triple_query_eval.dart`) and the datalog-conversion helpers (`datalog_convert.dart`); moved large private clusters into `part of` extensions.

### Schema converter (schema-io)
- **`bin/schema.dart` now converts `instant.schema.ts` ⇆ `@InstantModel` Dart** with a pure-Dart converter (no analyzer, no new dependencies). `pull` runs `instant-cli pull` then converts TS → Dart to `--schema-file`; `push` converts the Dart schema → `instant.schema.ts` then runs `instant-cli push`. New offline subcommands `to-dart <input.ts>` and `to-ts` convert without touching the cloud, and `diff` now does a best-effort normalized line diff.
- **`@InstantField` gains `unique`/`indexed` flags** (additive named params) so Dart → TS preserves constraints. The code generator ignores them (no codegen/golden impact).
- **Type mapping**: `i.string()`↔`String`, `i.number()`↔`num` (int/double/num all collapse to `i.number()` on the way back — documented), `i.boolean()`↔`bool`, `i.json()`↔`Map<String, dynamic>?`, `i.date()`↔`DateTime?`. json/date are always nullable + optional ctor params so the generated `fromRow` (which skips them) still compiles. Every entity gets a required `final String id`. `$`-prefixed system entities are not emitted as Dart classes (only resolved as link targets).
- **Links**: TS `links` forward/reverse ⇆ paired `@InstantLink` fields (`has:'one'`→`T?`, `has:'many'`→`List<T>`). The side landing on a system entity is skipped; Dart → TS dedupes reciprocal links and synthesizes a `has:'many'` reverse when only one side is declared (hand-tuned link names may change — documented).

### mergeModel + Table().tx(db) sugar (6e)
- **`mergeModel(id, Model)`**: deep-merges a whole model's scalar attributes (mirrors `updateModel` but uses `merge`). Backed by the new runtime primitive `TypedTx.mergeFromMap(id, map, {opts})`, which copies the map and delegates to `EntityInstanceBuilder.merge`.
- **`Table().tx(db)` sugar**: each generated table now emits `TypedTx<${Model}Table> tx(InstantDB db) => db.txFor(this)`, so `table.tx(db).createModel(...)` is shorthand for `db.txFor(table).createModel(...)`. A model field literally named `tx` would collide with this method (documented edge, extremely rare).
- **Generator**: emits the `tx` method on each table (after `toMap`) and `mergeModel` in each `${Model}TxX` extension (after `updateModel`). No public API removed.

### Whole-model writes + typed relation link (6d)
- **Whole-model writes**: `db.txFor(table).createModel(Model)` and `updateModel(id, Model)` write a model's scalar fields in one call via a generated `toMap`. The generator emits `Map<String, dynamic> toMap(Model m)` on the table plus a `${Model}TxX` extension on `TypedTx<${Model}Table>`.
- **`toMap` is scalar-only**: every scalar field is included (`id` too); relation fields are excluded. A model's relations are therefore **not** persisted by `createModel` — write them with `linkRel`/`unlinkRel`. For `createModel`, `data['id']` from the model is used as the entity id; for `updateModel`, the `id` attribute in the update map is harmless (it equals the entity id and reconstruction skips it).
- **Typed relation link**: the generator emits a `static const ${field}Rel = RelationRef<${Target}Table>('${attr}')` per relation. `db.txFor(table).linkRel(id, Table.relRel, ids)` / `unlinkRel(id, Table.relRel, ids)` write typed links (`ids` is a single id or a `List`).
- **Runtime primitives**: new `RelationRef<R>` handle in `typed_query.dart`; new `TypedTx` methods `createFromMap(map, {id})`, `updateFromMap(id, map, {opts})` (copies the map), `linkRel`/`unlinkRel`. All delegate to the existing untyped `EntityBuilder`/`EntityInstanceBuilder`. No base-class or `TypedTx` generic change; no public API removed.
- **Deferred to 6e**: `mergeModel`, the `Table().tx(db)` sugar, and richer typed relation handles that also carry the target table factory.

### Typed transactions (6c)
- **Typed write builder**: `db.txFor(table)` returns a `TypedTx<E>` whose fluent `set<T>(Col<T>, T)` binds each value's type to its column — wrong-typed writes (`set(t.priority, 'x')`) no longer compile. Cascade-friendly (`..set(..)..set(..)`).
- **Ops**: `create({id})`, `update(id)`, `merge(id)`, `delete(id)`, `link(id, relation, target)`, `unlink(id, relation, target)`, plus typed `lookup(Col, value)` upsert-by-unique-attribute. `opts(TxOpts(...))` controls upsert/strict on update/merge. All delegate to the existing untyped `EntityBuilder`/`EntityInstanceBuilder` — no op-construction is reimplemented.
- **Core seam**: new `abstract interface class ToTransaction { TransactionChunk toTransactionChunk(); }` in core; `TransactionChunk implements ToTransaction`, and `db.transact` now accepts any `ToTransaction` (so `db.transact(db.txFor(t).create()..set(...))` works) while `List<Operation>` and existing `TransactionChunk` callers are unchanged. No core→typed import.
- **Landed in 6d**: whole-model writes (`createModel(Todo(...))` via a generated `toMap`) and typed relation `link`/`unlink` (`RelationRef` consts). The generated `Table().tx(db)` convenience is deferred to 6e.

### Per-relation pageInfo (nested-4)
- **Engine**: cursor-paginated nested `include` relations now surface `pageInfo` at `QueryResult.pageInfo['<parentType>.<relation>']` (e.g. `result.pageInfo['goals.todos']`). Deeper nesting produces dotted keys (`'goals.todos.tags'`). The existing read API is unchanged — composite keys (containing `.`) coexist with top-level namespace keys in the same `pageInfo` map.
- **Mechanism**: a pageInfo sink (the fresh per-query `pageInfo` map) and a dotted `pathPrefix` are threaded through `_processIncludes` on the forward-triple path. Writes go directly into the map — no `_lastPageInfo` shared state, no race for nested relations.
- **Typed exposure**: `queryOnceTyped`/`queryTyped` return `QueryResult` unchanged, so `result.pageInfo?['goals.todos']` is readable from the typed path with no code change.
- **Non-paginated includes** add no composite pageInfo key (sink only written when pagination parameters are present).
- **Limitations**: pageInfo is per relation path, not per parent entity (with multiple parents the key reflects the last parent's window). FK-convention path not threaded (forward-triple / InstantLink only). A fully-typed `RelationPage<T>` accessor is deferred to a later generator follow-up.

### Relation pagination (nested-3)
- **Engine**: nested `include` maps now support cursor pagination (`first`/`last`/`after`/`before`/`afterInclusive`/`beforeInclusive`) and `fields` projection on the related set (forward-triple path). The cursor window is computed via `paginate()` — `limit`/`offset` are stripped from the `_applyQueryFilters` pass when any cursor/fields key is present, preventing double-windowing.
- **Typed DSL**: `TypedQuery._includeOptions()` now serializes `first`/`last`/`after`/`before`/`afterInclusive`/`beforeInclusive` and `limit`/`offset`. `fields` is intentionally not serialized on the typed path.
- **Guard**: `TypedQuery.include()` now throws `ArgumentError` if the relation sub-query carries `.select()` (fields projection). The generated `fromRow` hard-casts every field, so a projected map would cause a `TypeError`. Use the untyped map API for projected relations.
- **Deferred**: per-relation `pageInfo` (needs a typed relation-page wrapper — targeted at nested-4).
- **Known interaction (untyped only)**: `fields` projection on a relation strips all attributes from nested maps before deeper `include` recursion runs. If a projected relation also has a deeper `include`, the nested relation attribute is dropped unless it is among the projected fields. Rare combination; typed path forbids relation `fields`.

### Typed relations (nested-2)
- Added `@InstantLink` annotation for marking relation fields on `@InstantModel` classes. Cardinality is inferred from the field type (`List<T>` → to-many, `T` → to-one); the target must itself be an `@InstantModel`.
- Generator now emits a typed accessor getter per `@InstantLink` field (e.g. `TypedQuery<TodoTable> get todos => ...`) and a recursively-typed `fromRow` arm that maps included relation maps to `List<T>` (to-many) or `T?` (to-one). Un-included relations safely yield `[]` / `null` via `whereType<Map>` guard.
- Added `TypedQuery<E>.include((t) => t.relation.where(...).limit(n))` — serializes to the nested-1 engine's `include` map inside the `$` options, supporting nested `where`/`order`/`limit`/`offset` and recursive includes. Immutable: the source query is never mutated.
- Implemented in nested-3: typed cursor pagination on relation sub-queries; typed `fields` projection on relations is intentionally forbidden (see nested-3 section above).

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
