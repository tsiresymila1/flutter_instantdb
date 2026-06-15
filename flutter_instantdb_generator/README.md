# flutter_instantdb_generator

Build-time code generator for [`flutter_instantdb`](https://pub.dev/packages/flutter_instantdb).
It turns plain annotated model classes into type-safe query tables, typed
transactions, and relation accessors over the same InstantDB engine.

- 📚 Docs: https://flutter-instantdb.vercel.app/typed/codegen
- 📦 Runtime package: [`flutter_instantdb`](https://pub.dev/packages/flutter_instantdb)

## Install

Add the runtime package as a dependency and the generator + `build_runner` as
dev dependencies:

```yaml
dependencies:
  flutter_instantdb: ^1.1.2

dev_dependencies:
  build_runner: ^2.4.13
  flutter_instantdb_generator: ^0.2.0
```

## Usage

Annotate a model with `@InstantModel` and declare it as a `part`:

```dart
import 'package:flutter_instantdb/flutter_instantdb.dart';

part 'todo.instant.dart';

@InstantModel('todos')
class Todo {
  final String id;
  final String title;
  @InstantField('done_at')
  final int? doneAt;
  const Todo({required this.id, required this.title, this.doneAt});
}
```

Run the generator:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This emits `todo.instant.dart` with a `TodoTable` and typed extensions:

```dart
// Typed query
final todos = await TodoTable()
    .query()
    .where((t) => t.title.like('%urgent%'))
    .order((t) => t.title.asc())
    .getAll(db);

// Typed write
await db.transact(
  TodoTable().tx(db).createModel(Todo(id: db.id(), title: 'Ship it')),
);
```

### Annotations

- `@InstantModel('namespace')` — marks a class as an InstantDB model.
- `@InstantField('attr')` — overrides the stored attribute name for a field.
- `@InstantLink()` — marks a relation field. Cardinality is inferred from the
  field type (`List<T>` → to-many, `T` → to-one); the target must itself be an
  `@InstantModel`. Emits a typed `.include(...)` accessor, a recursively-typed
  `fromRow`, and a `RelationRef` for typed `linkRel`/`unlinkRel`.

See the [typed-layer docs](https://flutter-instantdb.vercel.app/typed/codegen)
for the full reference.

## License

MIT — see [LICENSE](LICENSE).
