# Design: Phase 6b — Annotation codegen (typed tables + typed results)

**Date:** 2026-06-13
**Status:** Approved (brainstorming) — pending spec review
**Part of:** Phase 6 (typed, Prisma-style API). Sub-phase **6b**, builds on **6a**
(typed query DSL, merged to `main`).

## Context

6a delivered a hand-written typed query DSL (`Col<T>`, `Filter`, `Order`,
`InstantTable<Self>`, `TypedQuery<E>`, `db.queryTyped`/`db.queryOnceTyped`)
compiling to InstaQL maps. 6b removes the hand-written boilerplate: a build_runner
generator emits the per-entity table class **and** typed result mapping from an
annotated model class, giving the full Prisma feel for reads.

## Decisions (from brainstorming)

1. **Separate generator package** (`flutter_instantdb_generator`), like
   `json_annotation`/`json_serializable` and `drift`/`drift_dev`. The runtime
   package keeps the annotations; the generator (analyzer/source_gen) is a
   consumer **dev_dependency**. Keeps `analyzer` out of app runtime.
2. **Part-file + plain class** declaration, matching the `json_serializable`
   pattern already used in this repo.
3. **Flat scope for 6b**: scalar fields + typed reads. Relation fields are
   detected and **deferred** (not emitted as columns yet); the foundation is
   shaped so nested slots in as a later sub-phase.

## Goal

```dart
@InstantModel('todos')
class Todo {
  final String id;
  final String title;
  final int priority;
  @InstantField('created_at') final int createdAt;
  Todo({required this.id, required this.title,
        required this.priority, required this.createdAt});
}
```
generates a typed table + result mapper so the consumer writes:
```dart
final todos = await TodoTable().query()
  .where((t) => t.priority.gte(8) & t.title.ilike('%urgent%'))
  .order((t) => t.priority.desc())
  .first(20)
  .getAll(db);   // List<Todo>, fully typed
```

## Non-goals (6b)

- Nested/relational queries and recursive result mapping (next sub-phase).
- Typed transactions / inputs (6c).
- Non-primitive field types beyond `String/int/double/num/bool` (enums,
  `DateTime`, custom converters → follow-ups).
- A `db.todos` accessor sugar (reads as `TodoTable().query()…getAll(db)` in 6b).

## Architecture

### Package layout (monorepo, two packages)

```
flutter_instantdb/                 # existing runtime package (root)
  lib/src/typed/
    typed_query.dart               # 6a (unchanged)
    annotations.dart               # NEW: @InstantModel, @InstantField
    model_table.dart               # NEW: InstantModelTable<Self, Row>
flutter_instantdb_generator/       # NEW package (sibling dir)
  pubspec.yaml                     # deps: build, source_gen, analyzer,
                                   #   path-dep flutter_instantdb; dev: source_gen_test
  build.yaml                       # PartBuilder('.instant.dart')
  lib/
    builder.dart                   # builder entrypoint (factory)
    src/instant_generator.dart     # GeneratorForAnnotation<InstantModel>
```

The root package is **not** restructured into `packages/` — the generator is a
sibling directory with its own `pubspec.yaml` and a `path: ../` dependency on
the runtime package. (If the repo later adopts a workspace/melos layout, the
generator moves under it; not required now.)

### Runtime additions (root package)

`lib/src/typed/annotations.dart`:
```dart
/// Marks a class as an InstantDB model; [entityType] is the namespace.
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

/// Overrides the stored attribute name for a field (default: the field name).
class InstantField {
  final String name;
  const InstantField(this.name);
}
```

`lib/src/typed/model_table.dart`:
```dart
import 'typed_query.dart';

/// A generated, typed table that also maps result rows to [Row] objects.
/// Extends the 6a InstantTable additively (hand-written tables still work).
abstract class InstantModelTable<Self extends InstantModelTable<Self, Row>, Row>
    extends InstantTable<Self> {
  InstantModelTable(super.entityType);

  /// Map one query-result document to a typed [Row].
  Row fromRow(Map<String, dynamic> map);
}
```

Both are exported from the barrel.

### Generated output (per model, into `<file>.instant.dart` part)

For `Todo` above the generator emits:

```dart
part of 'todo.dart';

class TodoTable extends InstantModelTable<TodoTable, Todo> {
  TodoTable() : super('todos');

  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final priority = const Col<int>('priority');
  final createdAt = const Col<int>('created_at');

  @override
  Todo fromRow(Map<String, dynamic> m) => Todo(
        id: m['id'] as String,
        title: m['title'] as String,
        priority: m['priority'] as int,
        createdAt: m['created_at'] as int,
      );
}

extension TodoQueryX on TypedQuery<TodoTable> {
  /// Run once and map to typed [Todo] objects.
  Future<List<Todo>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(TodoTable().fromRow)
          .toList();

  /// Reactive: a signal of typed [Todo] objects.
  Signal<List<Todo>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map(TodoTable().fromRow).toList());
  }
}
```

Key design points:
- The **per-model extension** binds `Row` concretely, so `getAll`/`watchAll`
  need no two-type-parameter generic inference — it always compiles.
- `Col` is used `const` (it only holds a name); the generator emits `const`.
- `fromRow` casts each field to its Dart type. Missing/typed-mismatch values
  surface as a runtime cast error (acceptable for 6b; nullable fields handled
  below).
- **Nullable fields**: a Dart field `final String? note;` → `note: m['note'] as String?`.
  The generator reads field nullability from the analyzer.
- **Relation fields** (a field whose type is another `@InstantModel` class, or
  `List<ThatModel>`): in 6b these are **skipped** — no `Col`, and `fromRow`
  does not populate them (must therefore be nullable or have a default in the
  model, or the generator errors with a clear message telling the user to make
  the relation field nullable until nested support lands). This is the reserved
  seam for the nested sub-phase.

### Generator (generator package)

`GeneratorForAnnotation<InstantModel>`:
- Validates the annotated element is a class with a generative constructor whose
  named parameters correspond to final fields (the json_serializable shape).
- For each field: resolve `DartType`; if it is a core scalar
  (`String/int/double/num/bool`, nullable or not), emit a `Col<T>` and a
  `fromRow` cast; if it is another `@InstantModel` type or `List<that>`, skip it
  (reserved for nested) and require it be nullable/defaulted, else throw
  `InvalidGenerationSourceError` with a clear message.
- Attribute name = `@InstantField('x')` value if present, else the field name.
- Emit the `Table` class + the `TypedQuery<XTable>` extension via
  `code_builder` or raw string emission (raw strings are fine and simplest).

`build.yaml`:
```yaml
builders:
  instant:
    import: 'package:flutter_instantdb_generator/builder.dart'
    builder_factories: ['instantBuilder']
    build_extensions: {'.dart': ['.instant.dart']}
    auto_apply: dependents
    build_to: source
    applies_builders: ['source_gen|combining_builder']
```
`builder.dart` exposes `Builder instantBuilder(BuilderOptions o) => PartBuilder([InstantGenerator()], '.instant.dart');`.

### Data flow

`@InstantModel` class → generator → `<file>.instant.dart` part (TodoTable +
extension) → consumer calls `TodoTable().query()…getAll(db)` → 6a `toQuery()` →
`db.queryOnceTyped` → query engine → docs → `TodoTable.fromRow` → `List<Todo>`.

## Error handling

- Annotated non-class, or class without a matching generative constructor →
  `InvalidGenerationSourceError` with a clear message.
- Non-nullable relation field (unsupported in 6b) → `InvalidGenerationSourceError`
  instructing the user to make it nullable until nested support lands.
- Unsupported scalar type → `InvalidGenerationSourceError` naming the field/type.
- Runtime: `fromRow` cast failure throws (documented); nullable fields tolerate
  missing values.

## Testing

- **Generator unit tests** (`flutter_instantdb_generator/test/`): use
  `source_gen_test`'s `testBuilder`/golden comparison to assert the generated
  source for a sample model — column emission, `@InstantField` name override,
  nullable field handling, `fromRow` body, and the `InvalidGenerationSourceError`
  cases (unsupported type, non-nullable relation).
- **Runtime integration test** (root package `test/`): check a generated
  `.instant.dart` into the test tree for a sample model, seed entities via `db`
  (syncEnabled:false), run `SampleTable().query().where(...).getAll(db)`, and
  assert a typed `List<Sample>` whose values match — and parity with the
  equivalent 6a hand-written query.
- **Example app**: add one annotated model + run the generator to prove
  end-to-end wiring (manual/CI `dart run build_runner build`).

## File structure

Root package:
- Create: `lib/src/typed/annotations.dart`, `lib/src/typed/model_table.dart`
- Modify: `lib/flutter_instantdb.dart` (export both)
- Create: runtime integration test + a checked-in generated sample part

Generator package (new dir `flutter_instantdb_generator/`):
- Create: `pubspec.yaml`, `build.yaml`, `lib/builder.dart`,
  `lib/src/instant_generator.dart`, `test/instant_generator_test.dart`,
  test fixtures.

## Backward compatibility

Purely additive. 6a's `InstantTable<Self>` and the string-map API are untouched;
`InstantModelTable` extends `InstantTable`. Hand-written tables keep working.

## Limitations (6b)

- Flat only — relation/nested deferred (next sub-phase); non-nullable relation
  fields are rejected with guidance.
- Primitive scalar field types only.
- Reads only (typed writes = 6c).
- No `db.todos` accessor sugar yet.

## Next

- **Nested sub-phase**: relation columns, `.include((g) => g.todos.where(...))`,
  recursive `fromRow`, cross-model resolution in the generator.
- **6c**: typed transactions (typed inputs, `create`/`update`/typed `lookup`).
