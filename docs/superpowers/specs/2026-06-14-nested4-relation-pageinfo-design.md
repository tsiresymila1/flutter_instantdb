# nested-4 — Per-relation pageInfo

Status: implemented. Lifts the limitation deferred by nested-3: cursor pagination on a
nested relation applies the window but **discards `page.pageInfo`**. nested-4
surfaces per-relation `startCursor`/`endCursor`/`hasNextPage`/`hasPreviousPage`
so a caller can page through a relation.

## Goal

For a cursor-paginated nested relation, expose its pageInfo at
`QueryResult.pageInfo['<parentType>.<relation>']` — the **same read API** as
existing top-level pagination (`result.pageInfo['todos']`), just under a
dotted composite key.

```dart
final r = await db.queryOnce({'goals': {'include': {'todos': {'first': 1, 'order': {'n': 'asc'}}}}});
final pi = r.pageInfo?['goals.todos'];   // {startCursor,endCursor,hasNextPage,hasPreviousPage}
pi?['hasNextPage'];                       // bool
pi?['endCursor'];                         // cursor for the next page
```

## Decisions (locked)

- **Representation = Option B**: per-relation pageInfo lives in
  `QueryResult.pageInfo` under a dotted composite key `'<path>.<relation>'`
  (e.g. `'goals.todos'`, deep: `'goals.todos.tags'`). Entity data maps stay
  clean (no `$pageInfo` sibling key) — `fromRow` is unaffected.
- **Typed exposure deferred**: no `RelationPage<T>` generator change in v1. Typed
  callers read per-relation pageInfo via `QueryResult.pageInfo` (preserved
  through `queryOnceTyped`/`queryTyped`).
- **Forward-triple path only**: nested pageInfo is collected on the InstantLink /
  relation-triple path (nested-1/2/3). The legacy FK-convention branches are not
  threaded (documented limitation).

## Existing code facts (verified — trust these)

- **`QueryResult`** (`lib/src/core/types.dart` lines 107-158): fields
  `isLoading`, `data` (`Map<String,dynamic>?`), `error`, and
  `pageInfo` (`Map<String,dynamic>?`, runtime-only `@JsonKey(include*: false)`).
  Shape: `{ namespace: {startCursor,endCursor,hasNextPage,hasPreviousPage} }`.
  `QueryResult.success(data, {pageInfo})`.
- **`PageResult`** (`lib/src/query/pagination.dart` lines 7-11, ~81-88):
  `{ items, pageInfo }` where `pageInfo` is a flat map with exactly
  `startCursor`(String?), `endCursor`(String?), `hasNextPage`(bool),
  `hasPreviousPage`(bool). Cursors are entity ids.
- **`query_engine.dart`** (post-nested-3, current line numbers):
  - `_processQuery` calls `_queryEntities(entityType, entityQuery, syncedOnly: …)`
    (lines 223-227), then collects top-level pageInfo:
    `final pi = _lastPageInfo[entityType]; if (pi != null) pageInfo[entityType] = pi;`
    (lines 229-230). `pageInfo` is created fresh per `_processQuery` (line 199)
    and returned (line 233). No `_lastPageInfo` race here for nested — we will
    write nested keys directly into this fresh `pageInfo` map.
  - `_queryEntities` signature (lines 236-240): `(String entityType,
    Map<String,dynamic> query, {bool syncedOnly = false})`.
  - `_processIncludes` is called from exactly TWO sites: `_queryEntities`
    line 314 (`entities = await _processIncludes(entities, include);`) and its own
    forward-triple recursion (~line 406: `out = await _processIncludes(out,
    nestedInclude);`). FK branches call `_queryEntities(...)` instead, NOT
    `_processIncludes`.
  - `_processIncludes` signature (~lines 341-343): `(List<Map> entities,
    Map<String,dynamic> includes)`.
  - The nested-3 paginate block sets `out = page.items;` and drops `page.pageInfo`
    with the comment "per-relation page.pageInfo deferred (nested-4)" (~line 401).
  - Forward-triple relation value set at `entity[relationName] = out;` (~line 408).
- **`queryOnceTyped`/`queryTyped`** (`lib/src/core/instant_db.dart` ~227-241)
  delegate to `queryOnce`/`query` and return `QueryResult` unchanged — so
  `pageInfo` (incl. composite keys) survives the typed path with no change.
- **Reserved-key conventions**: existing reserved keys are `__type`, `$`-clause,
  `$aggregate`, `$groupBy` — none collide with a dotted composite pageInfo key
  (which lives in `QueryResult.pageInfo`, not in entity maps or query maps).

## Design

Thread an optional pageInfo **sink** (the live `pageInfo` map) down the
forward-triple include path, plus a dotted `pathPrefix`. Writes go directly into
the fresh-per-query `pageInfo` map — no shared `_lastPageInfo`, no race.

### `query_engine.dart`

1. `_queryEntities` — add an optional named param:
   ```dart
   Future<List<Map<String, dynamic>>> _queryEntities(
     String entityType,
     Map<String, dynamic> query, {
     bool syncedOnly = false,
     Map<String, dynamic>? relationPageInfo,
   }) async {
   ```
2. The `_processIncludes` call inside `_queryEntities` (line 314):
   ```dart
   entities = await _processIncludes(
     entities, include,
     pathPrefix: entityType,
     relationPageInfo: relationPageInfo,
   );
   ```
3. `_processIncludes` — add optional named params:
   ```dart
   Future<List<Map<String, dynamic>>> _processIncludes(
     List<Map<String, dynamic>> entities,
     Map<String, dynamic> includes, {
     String? pathPrefix,
     Map<String, dynamic>? relationPageInfo,
   }) async {
   ```
4. In the forward-triple paginate block, after `out = page.items;`, record the
   pageInfo (and drop the "deferred" comment):
   ```dart
   if (relationPageInfo != null && pathPrefix != null) {
     relationPageInfo['$pathPrefix.$relationName'] = page.pageInfo;
   }
   ```
5. The nested-include recursion (~line 406) threads the extended path + sink:
   ```dart
   out = await _processIncludes(
     out, nestedInclude,
     pathPrefix: pathPrefix != null ? '$pathPrefix.$relationName' : relationName,
     relationPageInfo: relationPageInfo,
   );
   ```
6. `_processQuery` passes the fresh `pageInfo` map as the sink (line 223):
   ```dart
   final entities = await _queryEntities(
     entityType, entityQuery,
     syncedOnly: syncedOnly,
     relationPageInfo: pageInfo,
   );
   ```
   Composite keys (contain `.`) never collide with the top-level entityType key
   (a bare namespace). Both coexist in the same map.

No FK-branch change (legacy path not threaded). No typed/generator change.

## Tests

- **Engine** (`test/relational_include_test.dart`, new group
  "Include per-relation pageInfo (nested-4)"):
  - paginated relation populates `r.pageInfo['goals.todos']` with
    `hasNextPage == true`, `hasPreviousPage == false`, `endCursor == <t1 id>`
    (seed 3 ordered todos, `first: 1`).
  - second page via `after: endCursor` → `hasPreviousPage == true`, window
    advanced.
  - a NON-paginated include (no cursor/fields) produces NO
    `r.pageInfo['goals.todos']` key (sink only written when paginating).
  - deep nested paginated relation surfaces `r.pageInfo['goals.todos.tags']`.
- **Typed pass-through** (`test/typed_relations_test.dart`):
  - `db.queryOnceTyped(goals.query().include((g) => g.todos.order(...).first(1)))`
    — assert `r.pageInfo?['goals.todos']?['hasNextPage']` is readable (pageInfo
    survives the typed path). No typed model field needed.
- Full root suite stays at the **5 pre-existing** `database_closed` failures.
  Generator suite untouched/green.

## Risks

- **Dotted separator assumption**: composite keys assume entity types / relation
  names contain no `.`. True for Dart-identifier namespaces. Document.
- **Per-parent semantics**: pageInfo is per *query*, not per parent entity. With
  multiple parents each holding the same relation, the composite key reflects the
  LAST parent's window (each parent paginates independently; nested-4 surfaces one
  pageInfo per relation path, matching how the typed/untyped result is consumed
  per included relation). Document; surfacing per-parent windows is out of scope.
- **FK-convention path** not threaded — nested pageInfo only on the forward-triple
  (InstantLink) path. Documented.

## Next

**6c — typed transactions** (typed `create`/`update`/`lookup`) is the next major
gap (named in phase6a/6b "Next"). A fully-typed `RelationPage<T>` accessor for
per-relation pageInfo remains a later generator follow-up.
