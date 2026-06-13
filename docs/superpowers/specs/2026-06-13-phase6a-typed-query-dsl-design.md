# Design: Phase 6a — Typed Query DSL core

**Date:** 2026-06-13
**Status:** Approved (brainstorming) — pending spec review
**Part of:** Phase 6 (typed, Prisma-style API), staged. This is sub-phase **6a**.

## Context

Phases 1–5 brought `flutter_instantdb` to parity with the InstantDB JS clients,
but the query/transaction API is stringly-typed maps
(`db.query({'todos': {r'$': {'where': {'title': {r'$ilike': '%x%'}}}}})`).
The goal of Phase 6 is a typed, Prisma/drift-style API. The agreed architecture
is **annotation codegen (full Prisma feel), reached in stages**:

- **6a (this spec):** the typed DSL core — `Col<T>`, `Filter`, `Order`,
  `InstantTable`, `TypedQuery` — that compiles to the existing InstaQL maps.
  Usable today with hand-written table classes.
- **6b (later):** a build_runner generator that emits the per-entity table
  classes from annotated model classes, using 6a's primitives.
- **6c (later):** typed transactions (inputs + typed create/update/lookup).

The annotated **model class is the single source of truth** in 6b — the
generator reads each field's Dart type via the analyzer (no acanthis schema
duplication; the existing runtime `InstantSchema` is not the codegen source).

## Goal

A type-safe query builder whose output is byte-equivalent to the InstaQL maps
the engine already runs. Type errors (`t.priority.gte('x')`) are caught at
compile time. Zero engine changes — the DSL is a typed facade over existing
`db.query`/`db.queryOnce`.

## Non-goals (6a)

- Typed result objects (results stay `QueryResult` maps — that is 6b/6c).
- Code generation (6b).
- Typed transactions (6c).
- Nested/relational typed queries and multi-field ordering (later; 6a does
  single-namespace, single-order).

## Architecture

One new file `lib/src/typed/typed_query.dart` plus two thin `InstantDB`
methods. Everything compiles down to the map shape Phases 1 + 4 already handle
(`where_matcher.evaluateWhere`, `paginate`).

### `Col<T>` — typed field reference

Holds a field name; methods produce `Filter` leaves.

- All `T`: `Filter eq(T v)`, `Filter ne(T v)`, `Filter isNull(bool v)`,
  `Filter inList(List<T> vs)`.
- `extension ComparableCol<T extends Comparable<dynamic>> on Col<T>`:
  `gt(T)`, `gte(T)`, `lt(T)`, `lte(T)`.
- `extension StringCol on Col<String>`: `like(String)`, `ilike(String)`.
- `Order asc()`, `Order desc()`.
- **No `operator ==` override** (preserves `Object`/`hashCode` contract; use
  `.eq()`, the drift convention).

Value encoding is pass-through: the value the user supplies is placed directly
in the map (same as a hand-written query). 6a targets `String`/`int`/`num`/
`bool` field types; other types pass through unchanged (the caller owns
serialization, matching today's behavior).

### `Filter` — where expression

- Leaf: a single `{field: {op: value}}` (or `{field: value}` for `eq`).
- `Filter operator &(Filter other)` → `{'and': [a.toMap(), b.toMap()]}`.
- `Filter operator |(Filter other)` → `{'or': [a.toMap(), b.toMap()]}`.
- `Map<String, dynamic> toMap()` produces the InstaQL `where` fragment.

`and`/`or` nesting and the operators (`$ne`, `$gt`…, `$like`, `$ilike`,
`$isNull`, `$in`) map exactly onto what `where_matcher.evaluateWhere` (Phase 1)
already supports. `eq` emits direct equality `{field: value}`.

### `Order` — ordering

`Order` wraps `{field: 'asc' | 'desc'}`; produced by `Col.asc()/.desc()`.
Single field for 6a.

### `InstantTable` — entity handle

```dart
abstract class InstantTable {
  final String entityType;
  InstantTable(this.entityType);
  TypedQuery<E> query<E extends InstantTable>() => ...; // see note
}
```

Uses the self-referential generic (CRTP) so `query()` returns
`TypedQuery<Self>` with `t` correctly typed:

```dart
abstract class InstantTable<Self extends InstantTable<Self>> {
  final String entityType;
  InstantTable(this.entityType);
  TypedQuery<Self> query() => TypedQuery<Self>(this as Self);
}
```

Hand-written per entity in 6a:

```dart
class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final createdAt = Col<int>('createdAt');
}
```

`Todos().query()` therefore returns `TypedQuery<Todos>`, and the `where`/`order`
callbacks receive a `Todos` with typed `Col` fields. (`TypedQuery`'s bound
becomes `TypedQuery<E extends InstantTable<E>>` to match.)

### `TypedQuery<E extends InstantTable<E>>`

Immutable-ish fluent builder holding the table + accumulated options
(`where`/`order`/`select` callbacks take `E t`):

- `where(Filter Function(E t) build)`
- `order(Order Function(E t) build)`
- `first(int)`, `after(String)`, `last(int)`, `before(String)`,
  `afterInclusive(bool)`, `beforeInclusive(bool)`
- `limit(int)`, `offset(int)`
- `select(List<Col<dynamic>> Function(E t) fields)` → `fields`
- `Map<String, dynamic> toQuery()` →
  ```dart
  { entityType: { r'$': {
      if (where != null) 'where': where.toMap(),
      if (order != null) 'order': order.toMap(),
      if (first != null) 'first': first,
      if (after != null) 'after': after,
      // last/before/inclusive/limit/offset likewise
      if (fields != null) 'fields': [col.name, ...],
  }}}
  ```

This is exactly the InstaQL `$`-options shape Phase 4 consumes.

### `InstantDB` integration

Two thin wrappers (no new query logic):

```dart
Signal<QueryResult> queryTyped(TypedQuery q, {bool syncedOnly = false}) =>
    query(q.toQuery(), syncedOnly: syncedOnly);

Future<QueryResult> queryOnceTyped(TypedQuery q, {bool syncedOnly = false}) =>
    queryOnce(q.toQuery(), syncedOnly: syncedOnly);
```

`q.toQuery()` stays public for power users / debugging.

## Public API (barrel)

Export `lib/src/typed/typed_query.dart`: `Col`, `Filter`, `Order`,
`InstantTable`, `TypedQuery` (+ the `ComparableCol`/`StringCol` extensions).

## Data flow

`Todos().query().where(...).order(...).first(20)` → `TypedQuery.toQuery()` →
InstaQL map → `db.queryOnce(map)` → existing query engine (`where_matcher` +
`paginate`) → `QueryResult`.

## Error handling

- Type mismatches are compile-time (`t.priority.gte('x')` won't compile).
- `like`/`ilike` only exist on `Col<String>` (compile-time gated).
- `gt`/`lt`/etc only on `Col<Comparable>`.
- Runtime: `toQuery()` never throws; an empty builder yields `{entityType: {r'$': {}}}`,
  which the engine treats as "all".

## Testing

- **Pure unit tests** (`test/typed_query_test.dart`): exact map-equality on
  `Col` operators → `Filter.toMap()`, `&`/`|` nesting, `Order`, and full
  `TypedQuery.toQuery()` (where + order + pagination + fields). No DB.
- **Integration test** (`test/typed_query_integration_test.dart`): seed todos
  via `db` (syncEnabled:false), run a typed query through `db.queryOnceTyped`,
  and assert the result equals the equivalent hand-written-map query — proving
  the DSL output is what the engine expects.

## File structure

- Create: `lib/src/typed/typed_query.dart`
- Modify: `lib/src/core/instant_db.dart` (`queryTyped`/`queryOnceTyped`)
- Modify: `lib/flutter_instantdb.dart` (export)
- Create: `test/typed_query_test.dart`, `test/typed_query_integration_test.dart`
- Modify: `CHANGELOG.md`, `README.md`

## Backward compatibility

Purely additive. No existing symbol changes. The string-map API stays the
primary path; the typed DSL is an opt-in facade.

## Limitations (6a)

- Single namespace, single order field, no typed nested/relational queries.
- Typed results not included (maps only) — arrives with codegen (6b).
- Table classes are hand-written until the 6b generator lands.

## Next

6b (annotation codegen emitting `InstantTable` subclasses + typed results) and
6c (typed transactions) get their own brainstorm → spec → plan cycles.
