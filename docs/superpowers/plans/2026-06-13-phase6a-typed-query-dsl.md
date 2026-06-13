# Phase 6a: Typed Query DSL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a type-safe query builder (`Col<T>`, `Filter`, `Order`, `InstantTable<Self>`, `TypedQuery<E>`) that compiles to the existing InstaQL string-maps, plus `db.queryTyped`/`db.queryOnceTyped` — additively, no engine changes.

**Architecture:** One pure-Dart file `lib/src/typed/typed_query.dart` holds the DSL. It compiles to the exact `{entityType: {r'$': {where, order, first/after/..., fields}}}` shape that the Phase 1 where-matcher and Phase 4 paginate already consume. `InstantDB` gets two thin wrappers that call existing `query`/`queryOnce` with `TypedQuery.toQuery()`.

**Tech Stack:** Dart (generics, operator overloading, extension methods, CRTP), `flutter_test`, `sqflite_common_ffi`. No new dependencies.

**Source of truth:** Spec `docs/superpowers/specs/2026-06-13-phase6a-typed-query-dsl-design.md`. Builds on the merged Phases 1–5 (branch off `main`).

---

## Existing code facts (verified — rely on these)

- `lib/src/core/instant_db.dart`: `Signal<QueryResult> query(Map<String,dynamic> query, {bool syncedOnly = false})` (line ~188) and `Future<QueryResult> queryOnce(Map<String,dynamic> query, {bool syncedOnly = false})` (line ~203). `InstantInfiniteQuery infiniteQuery(...)` is at ~226 (a good neighbor to add the typed methods next to).
- The query engine reads namespace options from a `r'$'` clause (or a flat map): keys `where`, `order`, `limit`, `offset`, `first`, `last`, `after`, `before`, `afterInclusive`, `beforeInclusive`, `fields`. The where-matcher (Phase 1) supports operators `$eq $ne $not $gt $gte $lt $lte $in $nin $isNull $like $ilike` and `and`/`or`. `eq` can be expressed as direct equality `{field: value}`.
- `lib/flutter_instantdb.dart` barrel exports `src/core/instant_db.dart`, `src/core/types.dart`, `src/query/query_engine.dart`, `src/query/infinite_query.dart`, etc. Add a typed export there.
- `QueryResult` has a `documents` getter returning `List<Map<String,dynamic>>`.
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId:'test-app-id', config: InstantConfig(syncEnabled:false, persistenceDir:'test_db_<unique>'))`. Use `db.queryOnce`/`db.queryOnceTyped` for deterministic reads. flutter binary may be at `/Users/tsiresymila/DevTools/flutter/bin` or via `fvm flutter`.

---

## File Structure

- **Create:** `lib/src/typed/typed_query.dart` — `Col<T>`, the `ComparableCol`/`StringCol` extensions, `Filter`, `Order`, `InstantTable<Self>`, `TypedQuery<E>`. One responsibility: build a typed query and compile it to an InstaQL map.
- **Modify:** `lib/src/core/instant_db.dart` — add `queryTyped` / `queryOnceTyped`.
- **Modify:** `lib/flutter_instantdb.dart` — export the typed file.
- **Create:** `test/typed_query_test.dart` — pure unit tests (map equality).
- **Create:** `test/typed_query_integration_test.dart` — through the public DB API.
- **Modify:** `CHANGELOG.md`, `README.md`.

---

## Task 1: Col + Filter + Order (pure, with map output)

**Files:**
- Create: `lib/src/typed/typed_query.dart`
- Test: `test/typed_query_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/typed_query_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/typed/typed_query.dart';

void main() {
  group('Col operators -> Filter.toMap', () {
    final title = Col<String>('title');
    final priority = Col<int>('priority');

    test('eq emits direct equality', () {
      expect(title.eq('Run').toMap(), {'title': 'Run'});
    });

    test('ne / isNull / inList', () {
      expect(title.ne('Run').toMap(), {'title': {r'$ne': 'Run'}});
      expect(title.isNull(true).toMap(), {'title': {r'$isNull': true}});
      expect(priority.inList([1, 2]).toMap(), {'priority': {r'$in': [1, 2]}});
    });

    test('comparable operators', () {
      expect(priority.gt(5).toMap(), {'priority': {r'$gt': 5}});
      expect(priority.gte(5).toMap(), {'priority': {r'$gte': 5}});
      expect(priority.lt(5).toMap(), {'priority': {r'$lt': 5}});
      expect(priority.lte(5).toMap(), {'priority': {r'$lte': 5}});
    });

    test('string like / ilike', () {
      expect(title.like('%x%').toMap(), {'title': {r'$like': '%x%'}});
      expect(title.ilike('%x%').toMap(), {'title': {r'$ilike': '%x%'}});
    });
  });

  group('Filter combinators', () {
    final title = Col<String>('title');
    final priority = Col<int>('priority');

    test('and via &', () {
      final f = priority.gte(8) & title.ilike('%x%');
      expect(f.toMap(), {
        'and': [
          {'priority': {r'$gte': 8}},
          {'title': {r'$ilike': '%x%'}},
        ],
      });
    });

    test('or via |', () {
      final f = title.eq('A') | title.eq('B');
      expect(f.toMap(), {
        'or': [
          {'title': 'A'},
          {'title': 'B'},
        ],
      });
    });
  });

  group('Order', () {
    test('asc / desc', () {
      expect(Col<int>('createdAt').asc().toMap(), {'createdAt': 'asc'});
      expect(Col<int>('createdAt').desc().toMap(), {'createdAt': 'desc'});
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/typed_query_test.dart`
Expected: FAIL — `typed_query.dart` / `Col` undefined.

- [ ] **Step 3: Implement Col + Filter + Order in `lib/src/typed/typed_query.dart`**

```dart
/// Typed query DSL for InstantDB. Compiles to the InstaQL string-maps that the
/// query engine already consumes. Pure Dart — no DB dependency.

/// A where-clause expression. Combine leaves with `&` (and) / `|` (or).
class Filter {
  final Map<String, dynamic> _map;
  const Filter._(this._map);

  /// Leaf filter for a single field condition.
  factory Filter.field(String field, dynamic condition) =>
      Filter._({field: condition});

  Map<String, dynamic> toMap() => _map;

  Filter operator &(Filter other) =>
      Filter._({'and': [toMap(), other.toMap()]});

  Filter operator |(Filter other) =>
      Filter._({'or': [toMap(), other.toMap()]});
}

/// Ordering spec: `{field: 'asc' | 'desc'}`.
class Order {
  final String field;
  final String direction;
  const Order(this.field, this.direction);

  Map<String, dynamic> toMap() => {field: direction};
}

/// A typed reference to an entity field named [name].
class Col<T> {
  final String name;
  const Col(this.name);

  /// Direct equality (`{name: value}`).
  Filter eq(T value) => Filter.field(name, value);

  Filter ne(T value) => Filter.field(name, {r'$ne': value});

  Filter isNull(bool value) => Filter.field(name, {r'$isNull': value});

  Filter inList(List<T> values) => Filter.field(name, {r'$in': values});

  Order asc() => Order(name, 'asc');
  Order desc() => Order(name, 'desc');
}

/// Comparison operators, available only on `Col` of a `Comparable` type.
extension ComparableCol<T extends Comparable<dynamic>> on Col<T> {
  Filter gt(T value) => Filter.field(name, {r'$gt': value});
  Filter gte(T value) => Filter.field(name, {r'$gte': value});
  Filter lt(T value) => Filter.field(name, {r'$lt': value});
  Filter lte(T value) => Filter.field(name, {r'$lte': value});
}

/// String match operators, available only on `Col<String>`.
extension StringCol on Col<String> {
  Filter like(String pattern) => Filter.field(name, {r'$like': pattern});
  Filter ilike(String pattern) => Filter.field(name, {r'$ilike': pattern});
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/typed_query_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/typed/typed_query.dart test/typed_query_test.dart
git commit -m "feat(typed): add Col/Filter/Order DSL primitives"
```

---

## Task 2: InstantTable + TypedQuery.toQuery()

**Files:**
- Modify: `lib/src/typed/typed_query.dart`
- Test: `test/typed_query_test.dart` (append)

- [ ] **Step 1: Add the failing tests**

Append to the `main()` body of `test/typed_query_test.dart`:

```dart
  group('TypedQuery.toQuery', () {
    test('empty query yields just the namespace with empty options', () {
      expect(Todos().query().toQuery(), {
        'todos': {r'$': <String, dynamic>{}},
      });
    });

    test('where + order + first + fields compile to the $ clause', () {
      final q = Todos()
          .query()
          .where((t) => t.priority.gte(8) & t.title.ilike('%x%'))
          .order((t) => t.createdAt.desc())
          .first(20)
          .select((t) => [t.title, t.priority]);

      expect(q.toQuery(), {
        'todos': {
          r'$': {
            'where': {
              'and': [
                {'priority': {r'$gte': 8}},
                {'title': {r'$ilike': '%x%'}},
              ],
            },
            'order': {'createdAt': 'desc'},
            'first': 20,
            'fields': ['title', 'priority'],
          },
        },
      });
    });

    test('pagination + limit/offset options', () {
      final q = Todos()
          .query()
          .after('cursor1')
          .last(5)
          .before('cursor9')
          .afterInclusive(true)
          .beforeInclusive(true)
          .limit(3)
          .offset(2);
      expect(q.toQuery()['todos'][r'$'], {
        'after': 'cursor1',
        'last': 5,
        'before': 'cursor9',
        'afterInclusive': true,
        'beforeInclusive': true,
        'limit': 3,
        'offset': 2,
      });
    });
  });
}

/// Test table used by the TypedQuery tests above.
class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final createdAt = Col<int>('createdAt');
}
```

Note: the closing `}` of `main()` is already present in the file from Task 1 —
place the new `group(...)` BEFORE that closing brace, and put the `class Todos`
declaration AFTER the closing brace of `main()` (top-level). Adjust the existing
file so there is exactly one `main()` close and the class is top-level.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/typed_query_test.dart`
Expected: FAIL — `InstantTable` / `TypedQuery` / `.query()` undefined.

- [ ] **Step 3: Add `InstantTable` and `TypedQuery` to `typed_query.dart`**

Append to `lib/src/typed/typed_query.dart`:

```dart
/// Base class for a typed entity handle. Uses the self-referential generic so
/// `query()` returns a `TypedQuery<Self>` with correctly-typed columns.
abstract class InstantTable<Self extends InstantTable<Self>> {
  final String entityType;
  InstantTable(this.entityType);

  TypedQuery<Self> query() => TypedQuery<Self>(this as Self);
}

/// A fluent, type-safe query over a single namespace. Compiles to the InstaQL
/// `{entityType: {r'$': {...}}}` map the engine consumes.
class TypedQuery<E extends InstantTable<E>> {
  final E table;

  Filter? _where;
  Order? _order;
  int? _first;
  int? _last;
  int? _offset;
  int? _limit;
  String? _after;
  String? _before;
  bool? _afterInclusive;
  bool? _beforeInclusive;
  List<Col<dynamic>>? _fields;

  TypedQuery(this.table);

  TypedQuery<E> where(Filter Function(E t) build) {
    _where = build(table);
    return this;
  }

  TypedQuery<E> order(Order Function(E t) build) {
    _order = build(table);
    return this;
  }

  TypedQuery<E> select(List<Col<dynamic>> Function(E t) build) {
    _fields = build(table);
    return this;
  }

  TypedQuery<E> first(int n) {
    _first = n;
    return this;
  }

  TypedQuery<E> last(int n) {
    _last = n;
    return this;
  }

  TypedQuery<E> offset(int n) {
    _offset = n;
    return this;
  }

  TypedQuery<E> limit(int n) {
    _limit = n;
    return this;
  }

  TypedQuery<E> after(String cursor) {
    _after = cursor;
    return this;
  }

  TypedQuery<E> before(String cursor) {
    _before = cursor;
    return this;
  }

  TypedQuery<E> afterInclusive(bool value) {
    _afterInclusive = value;
    return this;
  }

  TypedQuery<E> beforeInclusive(bool value) {
    _beforeInclusive = value;
    return this;
  }

  /// Compile to the InstaQL map.
  Map<String, dynamic> toQuery() {
    final options = <String, dynamic>{
      if (_where != null) 'where': _where!.toMap(),
      if (_order != null) 'order': _order!.toMap(),
      if (_first != null) 'first': _first,
      if (_last != null) 'last': _last,
      if (_after != null) 'after': _after,
      if (_before != null) 'before': _before,
      if (_afterInclusive != null) 'afterInclusive': _afterInclusive,
      if (_beforeInclusive != null) 'beforeInclusive': _beforeInclusive,
      if (_limit != null) 'limit': _limit,
      if (_offset != null) 'offset': _offset,
      if (_fields != null) 'fields': _fields!.map((c) => c.name).toList(),
    };
    return {
      table.entityType: {r'$': options},
    };
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/typed_query_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Verify analysis**

Run: `flutter analyze lib/src/typed/typed_query.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/src/typed/typed_query.dart test/typed_query_test.dart
git commit -m "feat(typed): add InstantTable + TypedQuery compiling to InstaQL"
```

---

## Task 3: db.queryTyped / db.queryOnceTyped + barrel export

**Files:**
- Modify: `lib/src/core/instant_db.dart`
- Modify: `lib/flutter_instantdb.dart`
- Test: `test/typed_query_integration_test.dart` (create)

- [ ] **Step 1: Write the failing integration test**

Create `test/typed_query_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final n = Col<int>('n');
}

void main() {
  group('Typed query through db', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: 'test_typed_$id'),
      );
      for (var i = 0; i < 5; i++) {
        await db.transact(
          db.tx['todos']['t$i'].update({'title': 'todo$i', 'n': i}),
        );
      }
    });

    tearDown(() async => db.dispose());

    test('queryOnceTyped filters + paginates like the hand-written map', () async {
      final typed = await db.queryOnceTyped(
        Todos()
            .query()
            .where((t) => t.n.gte(1))
            .order((t) => t.n.asc())
            .first(2),
      );
      expect(typed.documents.map((e) => e['n']), [1, 2]);

      // Parity with the equivalent hand-written map.
      final manual = await db.queryOnce({
        'todos': {
          r'$': {
            'where': {'n': {r'$gte': 1}},
            'order': {'n': 'asc'},
            'first': 2,
          },
        },
      });
      expect(
        typed.documents.map((e) => e['n']).toList(),
        manual.documents.map((e) => e['n']).toList(),
      );
    });

    test('queryTyped returns a reactive signal', () async {
      final sig = db.queryTyped(Todos().query().where((t) => t.title.eq('todo3')));
      // Allow the async query to settle.
      await Future.delayed(const Duration(milliseconds: 150));
      expect(sig.value.documents.single['title'], 'todo3');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/typed_query_integration_test.dart`
Expected: FAIL — `db.queryOnceTyped` / `db.queryTyped` undefined; `InstantTable` not exported.

- [ ] **Step 3: Export the typed file from the barrel**

In `lib/flutter_instantdb.dart`, after the query exports, add:

```dart
export 'src/typed/typed_query.dart';
```

- [ ] **Step 4: Add the two wrappers to `instant_db.dart`**

Add the import at the top of `lib/src/core/instant_db.dart`:

```dart
import '../typed/typed_query.dart';
```

Add the methods near `infiniteQuery` (or `queryOnce`):

```dart
  /// Reactive typed query (see TypedQuery). Compiles to the InstaQL map and
  /// delegates to [query].
  Signal<QueryResult> queryTyped(
    TypedQuery query, {
    bool syncedOnly = false,
  }) {
    return this.query(query.toQuery(), syncedOnly: syncedOnly);
  }

  /// One-shot typed query. Compiles to the InstaQL map and delegates to
  /// [queryOnce].
  Future<QueryResult> queryOnceTyped(
    TypedQuery query, {
    bool syncedOnly = false,
  }) {
    return queryOnce(query.toQuery(), syncedOnly: syncedOnly);
  }
```

Note: the parameter is named `query` to read naturally; inside `queryTyped` the
existing method is reached via `this.query(...)` (as shown) to avoid the name
clash. `TypedQuery` here is the raw type (`TypedQuery<dynamic>`-compatible) —
that is fine because only `.toQuery()` is called.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/typed_query_integration_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing `database_closed`
teardown ones in `test/query_engine_advanced_test.dart`.

- [ ] **Step 7: Verify analysis**

Run: `flutter analyze lib/src/core/instant_db.dart lib/flutter_instantdb.dart lib/src/typed/typed_query.dart`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/src/core/instant_db.dart lib/flutter_instantdb.dart test/typed_query_integration_test.dart
git commit -m "feat(core): add db.queryTyped / db.queryOnceTyped"
```

---

## Task 4: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the Unreleased section in `CHANGELOG.md`:

```markdown
### Typed query DSL (Phase 6a)
- Added a type-safe query builder: `Col<T>`, `Filter` (combine with `&`/`|`), `Order`, `InstantTable<Self>`, `TypedQuery<E>`.
- Added `db.queryTyped(...)` (reactive) and `db.queryOnceTyped(...)` (one-shot), compiling to the existing InstaQL maps.
- Compile-time safety: `$like`/`$ilike` only on `Col<String>`, comparisons only on `Col<Comparable>`, value types checked against the column type.
```

- [ ] **Step 2: README section**

Run: `grep -n "queryOnce\|db.query\|InstantBuilder" README.md | head`
Add a "Typed queries" section after the query section:

````markdown
## Typed queries

```dart
class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final createdAt = Col<int>('createdAt');
}

final result = await db.queryOnceTyped(
  Todos()
    .query()
    .where((t) => t.title.ilike('%urgent%') & t.priority.gte(8))
    .order((t) => t.createdAt.desc())
    .first(20),
);
```
````

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only pre-existing `info`/`warning` issues outside the files this phase
touched.

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document the typed query DSL"
```

---

## Done criteria

- `flutter test test/typed_query_test.dart test/typed_query_integration_test.dart` — all green.
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones.
- `flutter analyze` — no issues in any file this phase modified.
- `Todos().query().where((t) => ...).order(...).first(n)` compiles to the correct InstaQL map; `db.queryOnceTyped` returns the same results as the equivalent hand-written map; compile-time type errors fire for mismatched column/value types and `like`/`ilike` on non-strings.
- No breaking changes: the string-map API is untouched; the DSL is purely additive.

## Notes for the implementer

- Do NOT add `operator ==` to `Col` — it must keep the `Object` equality/`hashCode` contract. Equality filtering is `.eq()`.
- Commit messages here intentionally omit any Co-Authored-By trailer (project preference for this work).

## Next

Phase 6b (annotation codegen emitting `InstantTable` subclasses + typed results) and 6c (typed transactions) get their own brainstorm → spec → plan cycles.
