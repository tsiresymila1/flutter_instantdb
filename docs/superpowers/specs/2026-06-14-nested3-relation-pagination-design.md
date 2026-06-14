# nested-3 — Cursor pagination & `fields` projection on relations

Status: implemented. Lifts the limitation deferred by nested-1/nested-2: the engine's
`_processIncludes` only applied `where`/`order`/`limit`/`offset` to a nested
related set. nested-3 also applies **cursor pagination**
(`first`/`last`/`after`/`before`/`afterInclusive`/`beforeInclusive`) and
**`fields` projection** to the nested set, and serializes the cursor keys on the
typed `.include` DSL.

## Goal

1. **Engine**: in `_processIncludes`' forward-triple path, run the existing
   `paginate(...)` helper on the nested related list (after `where`/`order`),
   so untyped `include` maps support `first`/`after`/…/`fields` on relations —
   exactly like the top-level path.
2. **Typed**: `TypedQuery._includeOptions()` serializes the cursor keys so
   `q.include((g) => g.todos.first(5).order((t) => t.n.asc()))` works.
3. **Guard the typed↔`fromRow` tension**: typed `.select()` (fields projection)
   on a relation sub-query **throws fail-fast** in `.include` — the generated
   `fromRow` hard-casts every field, so a projected map would `TypeError`.
   Untyped callers may still project relation fields (no `fromRow`).

## Decisions (locked)

- **Typed `.select()` on a relation** ⇒ `.include` throws `ArgumentError`
  pointing to the untyped map API. Engine still supports `fields` on relations
  for the untyped path.
- **Per-relation `pageInfo` is deferred** — v1 applies the cursor *window* to the
  nested list but surfaces no per-relation `startCursor`/`hasNextPage` (no
  structural slot in the parent map without a wrapper type). Documented limit.
- Engine change benefits **both** APIs; the typed layer omits only `fields`.

## Existing code facts (verified — trust these)

- **`paginate(...)`** (`lib/src/query/pagination.dart` line 28) — reusable on any
  `List<Map<String,dynamic>>`. Signature:
  ```dart
  PageResult paginate(List<Map<String, dynamic>> ordered, {
    int? first, int? last, String? after, String? before,
    bool afterInclusive = false, bool beforeInclusive = false,
    int? offset, int? limit, List<String>? fields,
  })
  ```
  Returns `PageResult{ items, pageInfo }`. **Needs the full ordered set** (no
  store-side limit) to compute the window — that's why the top-level path nulls
  `limit`/`offset` when paginating. `fields` projection is internal via
  `_project` (lines 20-26): always keeps `id`, plus each whitelisted key that
  exists. Already imported by `query_engine.dart` (called at line ~318).
- **Top-level pattern** (`query_engine.dart` `_queryEntities`):
  - `usePaginate = fields != null || first != null || last != null || after != null || before != null` (lines 287-291).
  - when paginating, `limit`/`offset` are nulled before the store query
    (lines 295-296) and passed to `paginate` instead.
- **`_processIncludes` forward-triple path** (`query_engine.dart` lines 352-381):
  fetches targets by id → `related`; if `relationQuery != null`, applies
  `out = _applyQueryFilters(related, relationQuery)` (lines 369-373,
  where/order/**limit/offset**); then recurses `relationQuery['include']`
  (lines 375-378); sets `entity[relationName] = out`. **No cursor, no fields.**
  This is the **only** path needing the new code.
- **FK-convention branches** (lines 383-466): both build a `queryMap` that copies
  every `relationQuery` key except `where` into it and delegate to
  `_queryEntities(...)` (lines 416-424, 449-461) — which already has full
  cursor+fields support. So nested cursor/fields on the FK path is **already
  inherited**; no change needed there.
- **`_applyQueryFilters`** (line ~508): handles `where`/`order`/`limit`/`offset`
  only; silently ignores `first`/`after`/`fields`.
- **Typed `TypedQuery<E>`** (`lib/src/typed/typed_query.dart`):
  - All cursor methods already exist: `select`→`_fields` (178), `first` (181),
    `last` (182), `after` (189), `before` (190), `afterInclusive` (193),
    `beforeInclusive` (195).
  - `include<R>` (lines ~202-209) builds the include map via `sub._includeOptions()`.
  - `_includeOptions()` (lines ~212-218) currently emits ONLY
    where/order/limit/offset/include.
  - `toQuery()` (lines ~221-239) shows the full top-level serialization incl.
    `'fields': _fields.map((c) => c.name).toList()`.
- **Generated `fromRow` hard-casts** (`test/fixtures/sample.instant.dart`,
  `flutter_instantdb_generator/test/src/model_fixtures.dart`):
  `id: m['id'] as String, label: m['label'] as String` — a dropped field ⇒
  `Null` cast `TypeError`. This is why typed `.select()` on a relation is unsafe.
- **Tests**: top-level cursor unit tests `test/pagination_test.dart` +
  `test/pagination_integration_test.dart`; nested include tests
  `test/relational_include_test.dart`; typed `test/typed_query_test.dart` +
  `test/typed_relations_test.dart`. No nested-cursor tests exist yet.

## Design

### 1. Engine — nested cursor + fields (`query_engine.dart`, forward-triple path)

Replace the `if (relationQuery != null) { out = _applyQueryFilters(...) }` block
(lines 369-373) with logic mirroring the top-level path — when any cursor/`fields`
key is present, `_applyQueryFilters` applies **where/order only** (drop
limit/offset) and `paginate` owns limit/offset/cursor/fields:

```dart
var out = related;
if (relationQuery != null) {
  final useNestedPaginate = relationQuery['fields'] != null ||
      relationQuery['first'] != null ||
      relationQuery['last'] != null ||
      relationQuery['after'] != null ||
      relationQuery['before'] != null;

  // When paginating, let paginate() own limit/offset (it needs the full ordered
  // set to compute the window) — strip them from the filter pass.
  final filterQuery = useNestedPaginate
      ? (Map<String, dynamic>.from(relationQuery)
        ..remove('limit')
        ..remove('offset'))
      : relationQuery;
  out = _applyQueryFilters(related, filterQuery);

  if (useNestedPaginate) {
    final page = paginate(
      out,
      first: relationQuery['first'] as int?,
      last: relationQuery['last'] as int?,
      after: relationQuery['after'] as String?,
      before: relationQuery['before'] as String?,
      afterInclusive: relationQuery['afterInclusive'] == true,
      beforeInclusive: relationQuery['beforeInclusive'] == true,
      offset: relationQuery['offset'] as int?,
      limit: relationQuery['limit'] as int?,
      fields: (relationQuery['fields'] as List?)?.cast<String>(),
    );
    out = page.items; // per-relation page.pageInfo deferred (not surfaced)
  }
}
// nested include recursion stays AFTER, on the windowed `out` (lines 375-378).
```

Update the stale comment (lines 370-372) — no longer "deferred".

> **Known interaction (document, don't fix)**: `fields` projection strips a
> nested map to `{id} ∪ projected`. If the same relation also has a deeper
> nested `include`, the deeper relation attribute is stripped before recursion,
> so it won't resolve unless that attribute is among the projected fields. Rare
> combo (untyped only — typed forbids relation `fields`). Note in the changelog.

### 2. Typed — serialize cursors + forbid relation `.select()`

`lib/src/typed/typed_query.dart`:

- In `include<R>` (before building `merged`), fail fast:
  ```dart
  if (sub._fields != null) {
    throw ArgumentError(
      'select()/fields projection is not supported on a typed relation '
      'include: the generated fromRow requires every field. Use the untyped '
      'query-map API if you need a projected relation.');
  }
  ```
- Extend `_includeOptions()` to also emit the cursor keys (NOT `fields`):
  ```dart
  Map<String, dynamic> _includeOptions() => {
        if (_where != null) 'where': _where.toMap(),
        if (_order != null) 'order': _order.toMap(),
        if (_first != null) 'first': _first,
        if (_last != null) 'last': _last,
        if (_after != null) 'after': _after,
        if (_before != null) 'before': _before,
        if (_afterInclusive != null) 'afterInclusive': _afterInclusive,
        if (_beforeInclusive != null) 'beforeInclusive': _beforeInclusive,
        if (_limit != null) 'limit': _limit,
        if (_offset != null) 'offset': _offset,
        if (_includes != null) 'include': _includes,
      };
  ```

No generator change (relation `fields` is forbidden on the typed path; nothing
new to emit).

## Tests

- **Engine** (`test/relational_include_test.dart`, new group
  "Include cursor pagination + fields (nested-3)"):
  - nested `first: 1` after `order` returns the first windowed target.
  - nested `after: '<id>'` cursor advances the window.
  - nested `fields: ['title']` returns maps of exactly `{id, title}` (other attrs
    dropped) — untyped path.
  - nested cursor + `limit` interplay: assert paginate owns the window (no double
    limit).
- **Typed unit** (`test/typed_query_test.dart`):
  - `_includeOptions` now serializes `first`/`after`/`afterInclusive`/etc when set
    on a relation sub-query (assert the `$.include.<attr>` map).
  - `.include` with a relation sub-query carrying `.select(...)` **throws
    ArgumentError**.
- **Typed integration** (`test/typed_relations_test.dart`):
  - `q.include((g) => g.todos.order((t) => t.n.asc()).first(1))` returns a
    single windowed typed nested element.
- Full root suite stays at the **5 pre-existing** `database_closed` failures.
  Generator suite untouched (still green).

## Risks

- **Double limit/offset**: mitigated by stripping limit/offset from the filter
  pass when paginating (mirrors top-level). Test the cursor+limit interplay.
- **`fields` + deeper nested include** (untyped): projection strips the deeper
  relation key. Documented, not fixed in v1.
- **Cursor stability under a relation `where`**: a cursor id filtered out by the
  nested `where` is silently ignored by `paginate` (`_indexOfId` → -1). Expected
  pagination semantics; document.

## Next

**nested-4** (done): per-relation `pageInfo` is now surfaced at
`QueryResult.pageInfo['<parentType>.<relation>']` (composite dotted key).
A fully-typed `RelationPage<T>` accessor remains a later generator follow-up.

**6c** (next): typed transactions (`create`/`update`/`lookup` via the typed DSL).
