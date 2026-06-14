# Design: nested-1 — Engine relational read fix

**Date:** 2026-06-13
**Status:** Approved (brainstorming) — pending spec review
**Part of:** Phase 6 nested support, decomposed. This is **nested-1** (engine
foundation); **nested-2** (typed nested layer) follows.

## Context

`db.tx.goals[g].link({todos: [t1, t2]})` persists relationships as triples
`(g, 'todos', t1)` and `(g, 'todos', t2)`. Two engine bugs make these
relationships unreadable through `include`:

1. **Reconstruction collapses multi-value attributes.** In
   `TripleStore.queryEntities` the entity-build loop does
   `entity[triple.attribute] = triple.value` (last-write-wins), so the two
   `todos` triples collapse to a single value — the to-many link is lost.
2. **`_processIncludes` guesses foreign keys** (`authorId`, `${parent}Id`,
   special-cases `posts`) on the *child* instead of reading the relation triples
   the parent actually holds. `link()`-created relations are never found.

nested-1 fixes the engine so relations created by `link()` resolve correctly.
It benefits the existing string-map API and is the foundation the typed nested
layer (nested-2) builds on.

## Goal

```dart
await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
await db.transact(db.tx['todos']['t1'].update({'title': 'Run'}));
await db.transact(db.tx['todos']['t2'].update({'title': 'Lift'}));
await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));

final r = await db.queryOnce({'goals': {'include': {'todos': {}}}});
// r.documents.first['todos'] == [ {id:'t1',title:'Run'}, {id:'t2',title:'Lift'} ]
```

## Non-goals (nested-1)

- Typed API (annotations/generated relation accessors/recursive typed mapping) →
  nested-2.
- Reverse-only links (child holds the FK, parent has no relation triple) — the
  existing FK-convention heuristic stays as a fallback; full reverse/back-ref
  resolution is deferred.
- Cursor pagination on the nested set (nested `where`/`order`/`limit`/`offset`
  are supported via the existing in-memory filter; cursors on relations later).

## Architecture

Two focused changes, both behind the existing `include` API — no public API
change.

### A. Faithful multi-value reconstruction

**File:** `lib/src/storage/triple_store.dart`, the entity-build loop in
`queryEntities` (currently `entity[triple.attribute] = triple.value`).

Accumulate repeated non-retracted attributes into a `List`:
```dart
for (final triple in triples) {
  final attr = triple.attribute;
  if (entity.containsKey(attr)) {
    final existing = entity[attr];
    if (existing is List) {
      existing.add(triple.value);
    } else {
      entity[attr] = [existing, triple.value];
    }
  } else {
    entity[attr] = triple.value;
  }
}
```
Safety: scalar attributes carry exactly one non-retracted triple (`update`
retracts the prior value before inserting), so they stay scalar. Only `link()`
(repeated `insert`, no retract) yields multiple triples for an attribute → a
to-many link correctly surfaced as a list of target ids. Triples are ordered by
`created_at ASC` (existing `queryByEntity` ordering), so list order is stable.

### B. Include resolution via relation triples

**File:** `lib/src/query/query_engine.dart`, `_processIncludes`.

At the **start** of the per-relation loop body (before the `relationName.endsWith('s')`
forward-convention branch and the one-to-one `else`), add a forward-triple path:

```dart
final relValue = entity[relationName];
if (relValue != null) {
  // Forward link: the parent holds the relation triples (target ids).
  final ids = relValue is List
      ? relValue.map((e) => e.toString()).toList()
      : [relValue.toString()];

  final related = <Map<String, dynamic>>[];
  for (final id in ids) {
    related.addAll(await _store.queryEntities(entityId: id));
  }

  var out = related;
  if (relationQuery != null) {
    out = _applyQueryFilters(related, relationQuery); // where/order/limit/offset
  }
  final nestedInclude = relationQuery?['include'] as Map<String, dynamic>?;
  if (nestedInclude != null) {
    out = await _processIncludes(out, nestedInclude); // recurse
  }
  entity[relationName] = out;
  continue; // handled — skip the FK-convention heuristics
}
```

- Target entities are fetched by id via `_store.queryEntities(entityId: id)`
  (no entity-type needed), so the relation's target namespace is irrelevant.
- The nested query's `where`/`order`/`limit`/`offset` are applied with the
  existing `_applyQueryFilters` (already used by the cache path). Nested `fields`
  projection and cursor pagination on relations were deferred here — implemented
  in nested-3 (see `docs/superpowers/specs/2026-06-14-nested3-relation-pagination-design.md`).
- Deeper `include`s recurse through the same method.
- If the parent holds no value for `relationName`, control falls through to the
  **unchanged** FK-convention branches → no regression for convention-based data.

### Data flow

`link()` → relation triples on parent → (A) reconstruction surfaces
`parent[relationName] = [ids]` → (B) include fetches each id as a full entity,
filters/orders per the nested query, recurses → `parent[relationName] = [ {…} ]`.

## Error handling

- A target id with no stored entity → `queryEntities(entityId: id)` returns an
  empty list; that id contributes nothing (no throw).
- A relation value that is neither scalar nor list is coerced via `toString()`
  into a single id (defensive).
- Existing FK-convention paths and their error behavior are untouched.

## Testing (offline, syncEnabled:false)

New `test/relational_include_test.dart`:
- **to-many link**: create goal + two todos, `link({todos:[t1,t2]})`, query goal
  with `include: {todos: {}}` → `todos` is a 2-element list of the full entities.
- **to-one link**: `link({owner: u1})` → `owner` resolves to the single entity
  (list of one; document the shape).
- **nested where/order/limit**: `include: {todos: {where:{done:true}, order:{n:'asc'}, limit:1}}`
  filters/orders/limits the related set (nested `fields`/cursors added in nested-3).
- **deep nested**: goal → todos → tags, two levels of include populate.
- **reconstruction**: a linked entity exposes the relation attribute as a list;
  a scalar attribute stays scalar (regression guard for change A).
- **FK-convention fallback** still resolves when the parent has no relation
  triple (regression guard for the untouched heuristic).
- Full suite stays at the 5 known pre-existing `database_closed` failures.

## File structure

- Modify: `lib/src/storage/triple_store.dart` (reconstruction loop — change A).
- Modify: `lib/src/query/query_engine.dart` (`_processIncludes` — change B).
- Create: `test/relational_include_test.dart`.
- Modify: `CHANGELOG.md`.

## Backward compatibility

Additive behavior fix. No public API change. The only behavioral change is that
to-many `link()` relations now (a) reconstruct as lists and (b) resolve through
`include`. Scalars and FK-convention includes are unchanged. Risk is contained
by the retract-on-update invariant (scalars stay single) and verified by the
full suite.

## Next

**nested-2**: `@InstantLink` annotation declaring relation fields →
generated typed relation accessors, `.include((g) => g.todos.where(...))`
composition on `TypedQuery`, and recursive typed `fromRow` populating
`List<Todo>` on the parent model. Builds directly on this engine fix.
