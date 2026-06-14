# nested-2 — Typed relation accessors & typed `include`

Status: implemented. Builds directly on **nested-1** (engine `include` populates relation
lists) and **phase6a** (typed query DSL) / **phase6b** (code generator).

## Goal

Bring the relation support that nested-1 added to the *engine* up into the **typed**
layer, so a generated model can:

1. Declare relation fields with an `@InstantLink` annotation.
2. Compose includes type-safely: `q.include((g) => g.todos.where((t) => t.n.gte(2)).limit(5))`.
3. Get a recursively-typed `fromRow` that populates `List<Todo>` (to-many) or
   `Todo?` (to-one) on the parent model from the included relation maps.

No public engine change. The typed `.include` compiles to the **exact** InstaQL
`include` map nested-1 already consumes; the generator emits relation accessors +
nested `fromRow` mapping.

## Decisions (locked)

- **Include API shape**: relation accessor returns a `TypedQuery<R>`, so it chains
  directly — `g.todos.where(...).limit(5)`. (Matches nested-1 spec's literal example.)
- **v1 scope**: typed includes serialize nested `where`/`order`/`limit`/`offset`
  and recurse into nested includes. Cursor pagination (`first`/`after`/…) and
  `fields` projection **on relations** stay deferred (the engine ignores them on
  the nested set anyway — see nested-1 spec). Top-level cursor/fields unchanged.
- **`@InstantLink`**: cardinality inferred from the field type (`List<T>` ⇒ to-many,
  `T` ⇒ to-one); target table inferred from `T`'s `@InstantModel` (emitted as
  `${T}Table`); the relation **attribute** (triple attr / include key) defaults to
  the field name, overridable via `@InstantLink(attr: 'subtasks')`.

## Existing code facts (verified — trust these)

- **Engine include nesting** (`lib/src/query/query_engine.dart`):
  - `_processQuery` (lines 201-220): a namespace value is unwrapped from a `$`
    clause if present (`queryValue['$']`), else used directly → `entityQuery`.
  - `_queryEntities` reads `entityQuery['include'] as Map<String,dynamic>?`
    (line 279) and calls `_processIncludes` (line 313).
  - `_processIncludes` (lines 339-381): for each `includes.entry`, key =
    `relationName`, value = nested options map read **directly** (no `$`):
    `where`/`order`/`limit`/`offset` via `_applyQueryFilters`, and recursion via
    `relationQuery['include']` (lines 375-378). After resolution
    `entity[relationName]` is a `List<Map<String,dynamic>>` (full entity maps);
    **to-one links also surface as a single-element list** (nested-1 coerces).
  - ⇒ The typed `include` map must therefore be
    `{ '<attr>': { where?, order?, limit?, offset?, include? } }` placed inside the
    `$` options map. `toQuery()` already emits `{entityType: {r'$': options}}`
    (`typed_query.dart` line 187-204); add `'include'` into `options`.
- **`TypedQuery<E>`** (`lib/src/typed/typed_query.dart` line 78): immutable, all
  fields private and final, fluent methods clone via `_copyWith` → private `_`
  ctor (lines 106-158). Public main ctor `TypedQuery(this.table)` (line 93).
  `InstantTable<Self>` (line 65) has `entityType` + `query()`.
- **Generator** (`flutter_instantdb_generator/lib/src/instant_generator.dart`):
  - Matches `@InstantModel` by class **name** (`_annotationName`, line 26).
  - `_generateForClass` (line 68): `tableName = '${modelName}Table'`,
    `entityType` from annotation. Emits `Col` fields (line 104), `fromRow`
    ctor args (line 107), and the `${modelName}QueryX` extension (line 124).
  - `_modelFields` (line 136): iterates `element.fields`, skips static/synthetic;
    **today** non-scalar fields throw if non-nullable, else are skipped
    (lines 145-156). `_attrName` (line 175) reads `@InstantField('name')`.
  - `_isSupportedScalar` (line 168): String/int/double/num/bool.
  - `_FieldInfo` (line 186): fieldName/attr/dartType/nullable.
- **Generated shape** pinned by golden tests in
  `flutter_instantdb_generator/test/src/model_fixtures.dart` via
  `@ShouldGenerate`/`@ShouldThrow`; harness `instant_generator_test.dart` uses
  `source_gen_test` (no build_runner). `BadModel` asserts a **non-nullable
  relation without `@InstantLink`** still throws — keep that.
- **Runtime fixtures**: `test/fixtures/sample.dart` (input) + committed
  `test/fixtures/sample.instant.dart` (generated). `test/codegen_runtime_test.dart`
  exercises the committed generated file directly (does NOT regenerate).
- **Annotations** live in `lib/src/typed/annotations.dart` (runtime) and are
  **duplicated as stand-ins** in `model_fixtures.dart` (the generator matches by
  name, no cross-package dep).
- **`InstantModelTable<Self, Row>`** (`lib/src/typed/model_table.dart`): extends
  `InstantTable<Self>`, abstract `Row fromRow(Map)`.
- Codegen build: `flutter packages pub run build_runner build --delete-conflicting-outputs`
  (justfile `generate`). Generated `.instant.dart` is committed.

## Design

### 1. `@InstantLink` annotation (`lib/src/typed/annotations.dart`)

```dart
/// Marks a relation field on an `@InstantModel`. Cardinality is inferred from the
/// field type: `List<T>` is to-many, a bare model type `T` is to-one. The target
/// table is `${T}Table` (T must itself be an `@InstantModel`). [attr] overrides
/// the stored relation attribute (the include key); it defaults to the field name.
class InstantLink {
  final String? attr;
  const InstantLink({this.attr});
}
```

Duplicate the same class (by name) into `model_fixtures.dart` for the golden tests.

### 2. Typed `.include` (`lib/src/typed/typed_query.dart`)

- Add two private fields, threaded through the `_` ctor and `_copyWith`:
  - `final String? _relationAttr;` — set on a query that *is* a relation
    resolution, so `.include` knows the include key.
  - `final Map<String, dynamic>? _includes;` — accumulated include map
    (`{attr: nestedOptions}`).
- Extend the **public** main ctor to accept the tag (so generated `part of` code,
  which cannot touch private members, can build a tagged query):
  `TypedQuery(this.table, {String? relationAttr}) : _relationAttr = relationAttr, … ;`
- Add the method:
  ```dart
  TypedQuery<E> include<R extends InstantTable<R>>(
    TypedQuery<R> Function(E t) build,
  ) {
    final sub = build(table);
    final attr = sub._relationAttr ?? sub.table.entityType;
    final merged = <String, dynamic>{...?_includes, attr: sub._includeOptions()};
    return _copyWith(includes: merged);
  }
  ```
- Add `_includeOptions()` (nested options — no `$`, no entityType wrapper; v1 scope):
  ```dart
  Map<String, dynamic> _includeOptions() => {
        if (_where != null) 'where': _where.toMap(),
        if (_order != null) 'order': _order.toMap(),
        if (_limit != null) 'limit': _limit,
        if (_offset != null) 'offset': _offset,
        if (_includes != null) 'include': _includes,
      };
  ```
- In `toQuery()` add to `options`: `if (_includes != null) 'include': _includes,`.
- `_copyWith` gains `Map<String,dynamic>? includes` and `String? relationAttr`
  params (preserve existing when null), the `_` ctor gains both required fields,
  and the main ctor initializes `_includes = null`.

### 3. Generator: relation accessors + nested `fromRow`

- New `_LinkInfo { fieldName, attr, relatedTypeName, relatedTableName, toMany, nullable }`.
- In `_modelFields` (rename/extend to also collect links): for each field, detect
  `@InstantLink` by metadata class name `'InstantLink'`. If present:
  - Determine the element type: if `field.type` is `List<T>` (`isDartCoreList`),
    `toMany = true`, related = the single type arg; else `toMany = false`,
    related = `field.type`.
  - `relatedTypeName = related.element.name`; `relatedTableName = '${relatedTypeName}Table'`.
  - Validate the related element carries `@InstantModel` (metadata name match);
    else `InvalidGenerationSourceError('relation target … must be @InstantModel')`.
  - `attr = annotation.attr ?? field.name`; `nullable` from the field type.
  - Collect into a links list (separate from scalar `_FieldInfo`).
  - A non-nullable non-scalar field **without** `@InstantLink` must keep throwing
    (BadModel golden unchanged).
- Emit, on the `$tableName` class, one accessor per link:
  ```dart
  TypedQuery<$relatedTableName> get $fieldName =>
      TypedQuery<$relatedTableName>($relatedTableName(), relationAttr: '$attr');
  ```
- Emit, in `fromRow`, one ctor arg per link (dart:core-only, safe when the
  relation was NOT included → the raw value is an id-list of strings, which
  `whereType<Map>` filters to empty / null):
  - to-many, non-nullable field `List<T>`:
    ```dart
    $fieldName: (m['$attr'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map($relatedTableName().fromRow)
            .toList() ??
        const <$relatedTypeName>[],
    ```
  - to-many, nullable field `List<T>?`: same without the `?? const […]` fallback.
  - to-one (always treat as nullable `T?`; engine yields a single-element list):
    ```dart
    $fieldName: (() {
      final l = (m['$attr'] as List<dynamic>?)?.whereType<Map<String, dynamic>>();
      return (l == null || l.isEmpty) ? null : $relatedTableName().fromRow(l.first);
    })(),
    ```
- Scalar emission, the `QueryX` extension, and ctor-param validation are unchanged.
  Relation field names must still match a named ctor param (existing check).

## Tests

- **Typed unit** (`test/typed_query_test.dart`): build a query whose `.include`
  arg is a manually-constructed `TypedQuery<R>(table, relationAttr: 'todos')` with
  nested `where`/`order`/`limit`; assert `toQuery()` yields
  `{ns: {r'$': {'include': {'todos': {'where':…, 'order':…, 'limit':…}}}}}`, and a
  nested two-level include nests under `include`. Assert immutability (original
  query has no include).
- **Typed integration** (`test/typed_query_integration_test.dart` or new
  `test/typed_relations_test.dart`): hand-written `InstantTable`/`InstantModelTable`
  subclasses (mirror `model_table_test.dart`), seed via `db.tx[...].link(...)`,
  run `db.queryOnceTyped(q.include(...))`, and assert the relation maps populate
  (to-many list, to-one single, nested filter narrows the set).
- **Generator golden** (`model_fixtures.dart`): add `@ShouldGenerate` fixtures for
  a to-many model (`Goal` with `@InstantLink() List<Todo> todos`) and a to-one
  model (`Post` with `@InstantLink() Author? author`), pinning the emitted
  accessor + nested `fromRow`. Add a `@ShouldThrow` for `@InstantLink` whose
  target is not an `@InstantModel`. Keep `BadModel` (non-nullable relation, **no**
  `@InstantLink`) throwing unchanged.
- **Codegen runtime** (`test/codegen_runtime_test.dart` + `test/fixtures/sample.*`):
  add a relation to `sample.dart`, regenerate `sample.instant.dart` (build_runner;
  if blocked, hand-write to match the golden), and add a test that seeds + links,
  runs `.include`, and asserts a typed nested `List<T>` populates on the parent.
- Full suite stays at the **5 known pre-existing** `database_closed` failures in
  `test/query_engine_advanced_test.dart`.

## Risks

- **Un-included relation access**: calling a generated `fromRow` on a parent whose
  relation was not `.include`d gives an id-list of strings, not maps. The
  `whereType<Map<String,dynamic>>()` guard makes this safe (empty list / null) —
  documented behavior, not a crash.
- **build_runner on a near-full disk** (~10 GiB free): if regeneration ENOSPCs,
  fall back to hand-writing `sample.instant.dart` to match the golden output (the
  golden test is the source-of-truth for the emit shape). Do **not** free space.

## Next

**nested-3** (future): typed cursor pagination + `fields` projection on relations
(lift the deferred nested-set limitations once the engine supports them on the
nested window).
