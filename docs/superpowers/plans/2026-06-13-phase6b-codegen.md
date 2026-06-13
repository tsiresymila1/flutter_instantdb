# Phase 6b: Annotation Codegen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `source_gen` generator that turns an `@InstantModel`-annotated plain class into a typed `InstantModelTable` (typed `Col`s + `fromRow`) plus a per-model `TypedQuery` extension (`getAll`/`watchAll` → typed `List<Model>`), giving the full Prisma-style typed read on top of 6a.

**Architecture:** Runtime additions live in `flutter_instantdb` (`@InstantModel`/`@InstantField` annotations + `InstantModelTable<Self, Row>` extending 6a's `InstantTable<Self>`). A **separate, pure-Dart** package `flutter_instantdb_generator` holds the builder. The generator matches the annotation by `TypeChecker.fromUrl` and emits runtime types via import strings, so it does **not** depend on `flutter_instantdb` (avoids dragging the Flutter SDK into a pure-Dart generator — the `json_serializable`/`json_annotation` pattern). Generated code lands in a `part 'x.instant.dart'` file.

**Tech Stack:** Dart, `source_gen`, `build`, `analyzer`, `build_runner`, `source_gen_test` (generator); `flutter_test` + `sqflite_common_ffi` (runtime integration). Flutter binary may be at `/Users/tsiresymila/DevTools/flutter/bin` or `fvm flutter`; the generator package is pure Dart so use `dart`/`dart run` there.

**Source of truth:** Spec `docs/superpowers/specs/2026-06-13-phase6b-codegen-design.md`. Builds on merged 6a (`main`).

---

## Existing code facts (verified — rely on these)

- 6a `lib/src/typed/typed_query.dart`: `class Col<T> { final String name; const Col(this.name); ... }`; `abstract class InstantTable<Self extends InstantTable<Self>> { final String entityType; InstantTable(this.entityType); TypedQuery<Self> query(); }`; `class TypedQuery<E extends InstantTable<E>>` with `Map<String,dynamic> toQuery()`.
- `lib/src/core/instant_db.dart`: `Future<QueryResult> queryOnceTyped(TypedQuery q, {bool syncedOnly=false})` and `Signal<QueryResult> queryTyped(TypedQuery q, {bool syncedOnly=false})`. `QueryResult.documents` → `List<Map<String,dynamic>>`.
- `lib/flutter_instantdb.dart` barrel re-exports `Signal`, `computed`, `signal` from `signals_flutter` and exports `src/typed/typed_query.dart`.
- Package name `flutter_instantdb`, sdk `^3.8.0`, dev_deps already include `build_runner: ^2.4.13`.
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId:'test-app-id', config: InstantConfig(syncEnabled:false, persistenceDir:'test_db_<unique>'))`.
- **Commit messages must contain NO Co-Authored-By / Claude trailer** (owner preference). Use the exact messages in this plan.
- If `example/pubspec.lock` gets dirtied by a tool, leave/revert it — never commit it.

---

## File Structure

Root package `flutter_instantdb`:
- Create: `lib/src/typed/annotations.dart` — `@InstantModel`, `@InstantField`.
- Create: `lib/src/typed/model_table.dart` — `InstantModelTable<Self, Row>`.
- Modify: `lib/flutter_instantdb.dart` — export both.
- Create: `test/model_table_test.dart` — runtime base test (hand-written table).
- Create: `test/fixtures/sample.dart` + `test/fixtures/sample.instant.dart` (checked-in generated part) + `test/codegen_runtime_test.dart`.

New package `flutter_instantdb_generator/` (sibling dir):
- Create: `pubspec.yaml`, `build.yaml`, `lib/builder.dart`, `lib/src/instant_generator.dart`.
- Create: `test/instant_generator_test.dart`, `test/src/model_fixtures.dart`.

---

## Task 1: Runtime annotations + InstantModelTable

**Files:**
- Create: `lib/src/typed/annotations.dart`, `lib/src/typed/model_table.dart`
- Modify: `lib/flutter_instantdb.dart`
- Test: `test/model_table_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/model_table_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

// Hand-written model + table mimicking what the generator will emit, to test
// the runtime InstantModelTable base independently of code generation.
class Sample {
  final String id;
  final String title;
  final int n;
  Sample({required this.id, required this.title, required this.n});
}

class SampleTable extends InstantModelTable<SampleTable, Sample> {
  SampleTable() : super('samples');
  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final n = const Col<int>('n');

  @override
  Sample fromRow(Map<String, dynamic> m) => Sample(
        id: m['id'] as String,
        title: m['title'] as String,
        n: m['n'] as int,
      );
}

void main() {
  group('InstantModelTable', () {
    test('is usable as a 6a InstantTable (query compiles)', () {
      final q = SampleTable().query().where((t) => t.n.gte(1));
      expect(q.toQuery(), {
        'samples': {r'$': {'where': {'n': {r'$gte': 1}}}},
      });
    });

    test('fromRow maps a document to a typed object', () {
      final s = SampleTable().fromRow({'id': 'a', 'title': 'T', 'n': 3});
      expect(s.id, 'a');
      expect(s.title, 'T');
      expect(s.n, 3);
    });

    test('queryOnceTyped + fromRow yields typed objects', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_mt_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      for (var i = 0; i < 3; i++) {
        await db.transact(
          db.tx['samples']['s$i'].update({'title': 'T$i', 'n': i}),
        );
      }
      final table = SampleTable();
      final result =
          await db.queryOnceTyped(table.query().where((t) => t.n.gte(1)));
      final samples = result.documents.map(table.fromRow).toList();
      expect(samples.map((s) => s.n).toList()..sort(), [1, 2]);
      await db.dispose();
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/model_table_test.dart`
Expected: FAIL — `InstantModelTable` undefined.

- [ ] **Step 3: Create the annotations**

Create `lib/src/typed/annotations.dart`:

```dart
/// Marks a class as an InstantDB model. [entityType] is the namespace the
/// generated table queries (e.g. 'todos').
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

/// Overrides the stored attribute name for a field. Without it, the field name
/// is used as the attribute name.
class InstantField {
  final String name;
  const InstantField(this.name);
}
```

- [ ] **Step 4: Create the model table base**

Create `lib/src/typed/model_table.dart`:

```dart
import 'typed_query.dart';

/// A typed table (like a 6a [InstantTable]) that also maps query-result
/// documents to typed [Row] objects via [fromRow]. Generated subclasses provide
/// the columns and the mapper. Extends [InstantTable] additively — hand-written
/// 6a tables keep working unchanged.
abstract class InstantModelTable<Self extends InstantModelTable<Self, Row>, Row>
    extends InstantTable<Self> {
  InstantModelTable(super.entityType);

  /// Map a single query-result document to a typed [Row].
  Row fromRow(Map<String, dynamic> map);
}
```

- [ ] **Step 5: Export from the barrel**

In `lib/flutter_instantdb.dart`, next to the `export 'src/typed/typed_query.dart';`
line, add:

```dart
export 'src/typed/annotations.dart';
export 'src/typed/model_table.dart';
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/model_table_test.dart`
Expected: PASS (query-compiles, fromRow, and queryOnceTyped+fromRow).

- [ ] **Step 7: Verify analysis**

Run: `flutter analyze lib/src/typed/annotations.dart lib/src/typed/model_table.dart`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/src/typed/annotations.dart lib/src/typed/model_table.dart lib/flutter_instantdb.dart test/model_table_test.dart
git commit -m "feat(typed): add @InstantModel/@InstantField + InstantModelTable base"
```

---

## Task 2: Scaffold the generator package (emits table + extension)

**Files:**
- Create: `flutter_instantdb_generator/pubspec.yaml`, `build.yaml`, `lib/builder.dart`, `lib/src/instant_generator.dart`
- Create: `flutter_instantdb_generator/test/src/model_fixtures.dart`, `test/instant_generator_test.dart`

- [ ] **Step 1: Create the generator package pubspec**

Create `flutter_instantdb_generator/pubspec.yaml`:

```yaml
name: flutter_instantdb_generator
description: Code generator for flutter_instantdb typed models.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.8.0

dependencies:
  analyzer: '>=6.0.0 <8.0.0'
  build: ^2.4.0
  source_gen: ^1.5.0

dev_dependencies:
  build_runner: ^2.4.13
  source_gen_test: ^1.0.6
  test: ^1.24.0
  lints: ^4.0.0
```

Run: `cd flutter_instantdb_generator && dart pub get`
Expected: resolves. **If resolution fails** on `analyzer`/`source_gen`/`source_gen_test`
version conflicts, loosen the constraints to what `dart pub get` proposes (run
`dart pub get` and read the conflict message; pick the highest mutually
compatible versions). Record the final versions. Do NOT add a dependency on
`flutter_instantdb` — the generator matches the annotation by URL only.

- [ ] **Step 2: Write a failing generator test (golden)**

Create `flutter_instantdb_generator/test/src/model_fixtures.dart` — input
fixtures annotated for the generator. Use a local re-declaration of the
annotations so the fixture compiles without depending on `flutter_instantdb`
(the generator matches by the annotation's name/URL; for unit tests we point the
TypeChecker at this local annotation — see Step 4):

```dart
// Test-local stand-ins for the annotations (same shape as the runtime ones).
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

class InstantField {
  final String name;
  const InstantField(this.name);
}

@ShouldGenerate(r'''
class TodoTable extends InstantModelTable<TodoTable, Todo> {
  TodoTable() : super('todos');

  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final priority = const Col<int>('priority');

  @override
  Todo fromRow(Map<String, dynamic> m) => Todo(
        id: m['id'] as String,
        title: m['title'] as String,
        priority: m['priority'] as int,
      );
}

extension TodoQueryX on TypedQuery<TodoTable> {
  Future<List<Todo>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map(TodoTable().fromRow).toList();

  Signal<List<Todo>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map(TodoTable().fromRow).toList());
  }
}
''')
@InstantModel('todos')
class Todo {
  final String id;
  final String title;
  final int priority;
  const Todo({required this.id, required this.title, required this.priority});
}
```

Note: `import 'package:source_gen_test/source_gen_test.dart';` provides
`@ShouldGenerate`. Add the import at the top of the fixture file.

Create `flutter_instantdb_generator/test/instant_generator_test.dart`:

```dart
import 'package:build/build.dart';
import 'package:source_gen_test/source_gen_test.dart';
import 'package:flutter_instantdb_generator/src/instant_generator.dart';

Future<void> main() async {
  final reader = await initializeLibraryReaderForDirectory(
    'test/src',
    'model_fixtures.dart',
  );

  initializeBuildLogTracking();
  testAnnotatedElements<InstantModel>(
    reader,
    InstantGenerator(),
  );
}
```

Note: `InstantModel` in the test must refer to the SAME annotation the generator
checks. To keep the test self-contained, the generator's `TypeChecker` is
configured (Step 4) to match an annotation named `InstantModel` regardless of
library (using `TypeChecker.fromRuntime` is not possible cross-package; instead
match by name — see Step 4). Import the fixture's `InstantModel` here:
`import 'src/model_fixtures.dart' show InstantModel;`.

- [ ] **Step 3: Run to verify it fails**

Run: `cd flutter_instantdb_generator && dart test`
Expected: FAIL — `instant_generator.dart` / `InstantGenerator` does not exist.

- [ ] **Step 4: Implement the generator**

Create `flutter_instantdb_generator/lib/src/instant_generator.dart`:

```dart
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Generates a typed [InstantModelTable] + a `TypedQuery` extension for every
/// class annotated with `@InstantModel`.
class InstantGenerator extends Generator {
  // Match any annotation class named `InstantModel` (the runtime one and the
  // test-local stand-in share this name). The element is read structurally.
  static const _annotationName = 'InstantModel';

  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();
    for (final element in library.classes) {
      final annotation = _instantModelAnnotation(element);
      if (annotation == null) continue;
      buffer.writeln(_generateForClass(element, annotation));
    }
    final out = buffer.toString().trim();
    return out.isEmpty ? null : out;
  }

  DartObject? _instantModelAnnotation(ClassElement element) {
    for (final meta in element.metadata) {
      final value = meta.computeConstantValue();
      final typeName = value?.type?.element?.name;
      if (typeName == _annotationName) return value;
    }
    return null;
  }

  String _generateForClass(ClassElement element, DartObject annotation) {
    final modelName = element.name;
    final tableName = '${modelName}Table';
    final entityType = annotation.getField('entityType')!.toStringValue()!;

    final fields = _modelFields(element);

    final cols = StringBuffer();
    final ctorArgs = StringBuffer();
    for (final f in fields) {
      cols.writeln(
        "  final ${f.fieldName} = const Col<${f.dartType}>('${f.attr}');",
      );
      ctorArgs.writeln(
        "        ${f.fieldName}: m['${f.attr}'] as ${f.dartType}${f.nullable ? '?' : ''},",
      );
    }

    return '''
class $tableName extends InstantModelTable<$tableName, $modelName> {
  $tableName() : super('$entityType');

${cols.toString().trimRight()}

  @override
  $modelName fromRow(Map<String, dynamic> m) => $modelName(
${ctorArgs.toString().trimRight()}
      );
}

extension ${modelName}QueryX on TypedQuery<$tableName> {
  Future<List<$modelName>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map($tableName().fromRow).toList();

  Signal<List<$modelName>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map($tableName().fromRow).toList());
  }
}
''';
  }

  List<_FieldInfo> _modelFields(ClassElement element) {
    final result = <_FieldInfo>[];
    for (final field in element.fields) {
      if (field.isStatic || field.isSynthetic) continue;

      final type = field.type;
      final dartType = type.getDisplayString(withNullability: false);
      final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

      if (!_isSupportedScalar(type)) {
        // Relation / unsupported type: deferred to the nested sub-phase.
        if (!nullable) {
          throw InvalidGenerationSourceError(
            'Field "${field.name}" on ${element.name} has unsupported type '
            '"$dartType". Relations/non-primitive types are not yet generated; '
            'make the field nullable to skip it until nested support lands.',
            element: field,
          );
        }
        continue; // nullable unsupported field: skip emitting a column/mapping.
      }

      result.add(_FieldInfo(
        fieldName: field.name,
        attr: _attrName(field),
        dartType: dartType,
        nullable: nullable,
      ));
    }
    return result;
  }

  bool _isSupportedScalar(DartType type) =>
      type.isDartCoreString ||
      type.isDartCoreInt ||
      type.isDartCoreDouble ||
      type.isDartCoreNum ||
      type.isDartCoreBool;

  String _attrName(FieldElement field) {
    for (final meta in field.metadata) {
      final value = meta.computeConstantValue();
      if (value?.type?.element?.name == 'InstantField') {
        return value!.getField('name')!.toStringValue()!;
      }
    }
    return field.name;
  }
}

class _FieldInfo {
  final String fieldName;
  final String attr;
  final String dartType;
  final bool nullable;
  _FieldInfo({
    required this.fieldName,
    required this.attr,
    required this.dartType,
    required this.nullable,
  });
}
```

Add the analyzer import alias note: `DartObject` comes from
`package:analyzer/dart/constant/value.dart` — add
`import 'package:analyzer/dart/constant/value.dart';` to the imports if the
build reports `DartObject` undefined.

- [ ] **Step 5: Run to verify the golden passes**

Run: `cd flutter_instantdb_generator && dart test`
Expected: PASS — generated source matches the `@ShouldGenerate` golden for `Todo`.
**If the golden differs only in whitespace/trailing commas**, adjust the
`@ShouldGenerate` string in `model_fixtures.dart` to match the generator's exact
output (source_gen_test compares normalized output; align them). **If an
analyzer API (e.g. `element.metadata`, `getDisplayString`) is deprecated in the
resolved analyzer version**, use the non-deprecated equivalent the analyzer
suggests and keep behavior identical.

- [ ] **Step 6: Create the builder entrypoint + build.yaml**

Create `flutter_instantdb_generator/lib/builder.dart`:

```dart
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/instant_generator.dart';

Builder instantBuilder(BuilderOptions options) =>
    PartBuilder([InstantGenerator()], '.instant.dart');
```

Create `flutter_instantdb_generator/build.yaml`:

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

- [ ] **Step 7: Analyze the generator package**

Run: `cd flutter_instantdb_generator && dart analyze`
Expected: no errors (info/deprecation notes acceptable if the resolved analyzer
version deprecates an API you could not avoid; prefer the non-deprecated form).

- [ ] **Step 8: Commit**

```bash
git add flutter_instantdb_generator/
git commit -m "feat(generator): scaffold source_gen builder emitting typed tables"
```

---

## Task 3: Generator field handling — name override, nullable, errors

**Files:**
- Modify: `flutter_instantdb_generator/test/src/model_fixtures.dart`
- (Implementation from Task 2 already covers these — this task locks them with tests.)

- [ ] **Step 1: Add fixtures + goldens for the three cases**

Append to `flutter_instantdb_generator/test/src/model_fixtures.dart`:

```dart
@ShouldGenerate(r'''
class ProfileTable extends InstantModelTable<ProfileTable, Profile> {
  ProfileTable() : super('profiles');

  final id = const Col<String>('id');
  final createdAt = const Col<int>('created_at');
  final nickname = const Col<String>('nickname');

  @override
  Profile fromRow(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        createdAt: m['created_at'] as int,
        nickname: m['nickname'] as String?,
      );
}

extension ProfileQueryX on TypedQuery<ProfileTable> {
  Future<List<Profile>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map(ProfileTable().fromRow).toList();

  Signal<List<Profile>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map(ProfileTable().fromRow).toList());
  }
}
''')
@InstantModel('profiles')
class Profile {
  final String id;
  @InstantField('created_at')
  final int createdAt;
  final String? nickname;
  const Profile({required this.id, required this.createdAt, this.nickname});
}

@ShouldThrow(
  'Field "owner" on BadModel has unsupported type "Profile". '
  'Relations/non-primitive types are not yet generated; '
  'make the field nullable to skip it until nested support lands.',
)
@InstantModel('bad')
class BadModel {
  final String id;
  final Profile owner; // non-nullable relation -> error
  const BadModel({required this.id, required this.owner});
}
```

Note: `@ShouldThrow` is from `source_gen_test`. The exact message must match the
generator's `InvalidGenerationSourceError` text from Task 2 Step 4 verbatim — if
they differ, align one to the other (prefer making the test match the
generator's actual message).

- [ ] **Step 2: Run to verify**

Run: `cd flutter_instantdb_generator && dart test`
Expected: PASS for `Profile` (name override + nullable), and the `BadModel`
case throws the expected message. Align golden whitespace / message text if
needed (as in Task 2 Step 5).

- [ ] **Step 3: Commit**

```bash
git add flutter_instantdb_generator/test/src/model_fixtures.dart
git commit -m "test(generator): cover @InstantField, nullable, and relation-error cases"
```

---

## Task 4: End-to-end — generate + runtime typed read

**Files:**
- Create: `test/fixtures/sample.dart`, `test/fixtures/sample.instant.dart`
- Create: `test/codegen_runtime_test.dart`

This proves the generated code compiles against the real runtime and produces
typed results. Because wiring `build_runner` to run cross-package in CI is
fragile, we **check in** the generated part and test it directly (it is exactly
what the generator emits; Task 2/3 goldens guarantee the generator produces this
shape).

- [ ] **Step 1: Create the annotated model fixture**

Create `test/fixtures/sample.dart`:

```dart
import 'package:flutter_instantdb/flutter_instantdb.dart';

part 'sample.instant.dart';

@InstantModel('widgets')
class Widget2 {
  final String id;
  final String name;
  final int weight;
  const Widget2({required this.id, required this.name, required this.weight});
}
```

(The class is named `Widget2` to avoid clashing with Flutter's `Widget`.)

- [ ] **Step 2: Create the checked-in generated part**

Create `test/fixtures/sample.instant.dart` (exactly what the generator emits for
`Widget2`):

```dart
// GENERATED CODE - matches flutter_instantdb_generator output for Widget2.
part of 'sample.dart';

class Widget2Table extends InstantModelTable<Widget2Table, Widget2> {
  Widget2Table() : super('widgets');

  final id = const Col<String>('id');
  final name = const Col<String>('name');
  final weight = const Col<int>('weight');

  @override
  Widget2 fromRow(Map<String, dynamic> m) => Widget2(
        id: m['id'] as String,
        name: m['name'] as String,
        weight: m['weight'] as int,
      );
}

extension Widget2QueryX on TypedQuery<Widget2Table> {
  Future<List<Widget2>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map(Widget2Table().fromRow).toList();

  Signal<List<Widget2>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map(Widget2Table().fromRow).toList());
  }
}
```

- [ ] **Step 3: Write the failing runtime test**

Create `test/codegen_runtime_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

import 'fixtures/sample.dart';

void main() {
  group('Generated table end-to-end', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_cg_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      for (var i = 0; i < 4; i++) {
        await db.transact(
          db.tx['widgets']['w$i'].update({'name': 'w$i', 'weight': i}),
        );
      }
    });

    tearDown(() async => db.dispose());

    test('getAll returns typed List<Widget2> filtered + ordered', () async {
      final widgets = await Widget2Table()
          .query()
          .where((t) => t.weight.gte(2))
          .order((t) => t.weight.asc())
          .getAll(db);

      expect(widgets, isA<List<Widget2>>());
      expect(widgets.map((w) => w.weight), [2, 3]);
      expect(widgets.first.name, 'w2');
    });
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/codegen_runtime_test.dart`
Expected: PASS — the generated part compiles against the runtime and `getAll`
returns a typed `List<Widget2>`.

- [ ] **Step 5: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing `database_closed`
teardown ones in `test/query_engine_advanced_test.dart`.

- [ ] **Step 6: Commit**

```bash
git add test/fixtures/sample.dart test/fixtures/sample.instant.dart test/codegen_runtime_test.dart
git commit -m "test(typed): end-to-end generated table typed read"
```

---

## Task 5: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the Unreleased section in `CHANGELOG.md`:

```markdown
### Typed model codegen (Phase 6b)
- Added `@InstantModel`/`@InstantField` annotations and the `InstantModelTable<Self, Row>` base.
- Added a `flutter_instantdb_generator` package (build_runner) that emits a typed table + `getAll`/`watchAll` extension from an annotated model class, returning typed `List<Model>`.
- Flat models (primitive fields) for now; relation/nested fields are deferred (non-nullable relations are rejected with guidance).
```

- [ ] **Step 2: README section**

Add a "Typed models (codegen)" section after the "Typed queries" section:

````markdown
## Typed models (codegen)

Add the generator to your dev dependencies and annotate a model:

```dart
import 'package:flutter_instantdb/flutter_instantdb.dart';
part 'todo.instant.dart';

@InstantModel('todos')
class Todo {
  final String id;
  final String title;
  final int priority;
  const Todo({required this.id, required this.title, required this.priority});
}
```

Run `dart run build_runner build`, then:

```dart
final todos = await TodoTable()
    .query()
    .where((t) => t.priority.gte(8))
    .order((t) => t.priority.desc())
    .getAll(db); // List<Todo>
```
````

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only pre-existing `info`/`warning` issues outside the files this phase
touched (the generator package is analyzed separately via `dart analyze` in its
own dir).

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document typed model codegen (Phase 6b)"
```

---

## Done criteria

- `cd flutter_instantdb_generator && dart test` — generator goldens + error cases green.
- `flutter test test/model_table_test.dart test/codegen_runtime_test.dart` — green.
- `flutter test` — no NEW failures beyond the 5 known pre-existing ones.
- `flutter analyze` (root) and `dart analyze` (generator) — clean (only pre-existing root infos).
- An `@InstantModel` class generates a typed `InstantModelTable` + `getAll`/`watchAll` extension producing typed `List<Model>`; `@InstantField` renames the attribute; nullable unsupported fields are skipped; non-nullable relation fields error with guidance.
- No breaking changes: 6a + the string-map API are untouched; `InstantModelTable` extends `InstantTable` additively.
- No commit carries a Co-Authored-By / Claude trailer.

## Notes for the implementer

- Codegen versions are empirical: if `dart pub get` in the generator package can't
  resolve `analyzer`/`source_gen`/`source_gen_test`, adjust the constraints to the
  resolver's suggested compatible set and proceed — the generator code uses only
  stable analyzer/source_gen APIs.
- If a resolved analyzer version deprecates `element.metadata` /
  `getDisplayString(withNullability:)` / `type.element?.name`, switch to the
  non-deprecated equivalent the analyzer recommends, preserving behavior. Keep
  the generated OUTPUT identical so the goldens and the checked-in
  `sample.instant.dart` stay valid.
- The generator must NOT depend on `flutter_instantdb` (keeps the Flutter SDK out
  of a pure-Dart package). It matches the annotation by class name and emits
  runtime type names as plain text.

## Next

- Nested sub-phase: relation columns + `.include((g) => g.todos.where(...))` + recursive `fromRow`.
- 6c: typed transactions (typed inputs, create/update/typed lookup).
