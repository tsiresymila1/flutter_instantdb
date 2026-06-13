# Phase 4: Cursor Pagination + Fields Selection + Infinite Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add InstaQL cursor pagination (`first`/`after`/`last`/`before` + `afterInclusive`/`beforeInclusive`), a `pageInfo` result block (`startCursor`/`endCursor`/`hasNextPage`/`hasPreviousPage`), `fields` projection, and an infinite-query helper — matching `@instantdb/core/src/queryTypes.ts` — additively, no breaking changes.

**Architecture:** A new **pure** function `paginate()` in `lib/src/query/pagination.dart` takes an already-ordered entity list plus pagination/projection options and returns the sliced window + `pageInfo`. Cursors are modeled offline as the entity `id`'s position in the ordered set (the server issues opaque cursors; offline we use id-position, which is stable). The query engine routes a query through `paginate()` only when cursor or `fields` keys are present (otherwise behavior is byte-identical), fetching the full ordered set from the store (bypassing the store's own `limit`/`offset`) so the window + flags are correct. `pageInfo` is threaded up onto `QueryResult.pageInfo`. `db.infiniteQuery()` builds on the cursor primitive to accumulate pages.

**Tech Stack:** Dart (records, SDK ^3.8), `flutter_test`, `sqflite_common_ffi`. No new dependencies.

**Source of truth:** `@instantdb/core/src/queryTypes.ts` (options + `PageInfoResponse`). Spec: `docs/superpowers/specs/2026-06-13-instantdb-parity-design.md` (Phase 4). Builds on Phases 1–3 (branch `feat/instantdb-parity-phase1`).

---

## Existing code facts (verified — rely on these)

- `lib/src/query/query_engine.dart`:
  - `_processQuery(query)` returns `Future<Map<String,dynamic>>` — `{entityType: List<entity>}`. Called by `_executeQuery`, which sets `resultSignal.value = QueryResult.success(result)`.
  - `_queryEntities(entityType, entityQuery, {syncedOnly})` returns the entity `List`. Two data paths: (a) sync-cache path → `_applyQueryFilters(cachedData, query)`; (b) storage path → builds `where`/`orderBy`/`limit`/`offset`/`include` and calls `_store.queryEntities(...)`, then `_processIncludes`. With `syncEnabled:false` there is no sync engine, so the **storage path** runs.
  - `_applyQueryFilters(data, query)` applies where → order → `limit` (`take`) → `offset` (`skip`). NOTE: it applies limit BEFORE offset (a latent bug when both are set); this phase's `paginate()` does offset-before-limit correctly, but do NOT change `_applyQueryFilters`'s existing limit/offset lines in this phase (avoid behavior churn on the cache path).
  - The `$` clause is unwrapped already: both paths read options like `where`/`order`/`limit`/`offset` from a flattened `entityQuery` map (React `$:{...}` is merged in before `_queryEntities`/`_applyQueryFilters`).
  - Every reconstructed entity map includes an `'id'` key (string).
- `lib/src/core/types.dart`: `QueryResult { bool isLoading; Map<String,dynamic>? data; String? error; }` with factories `loading()`, `success(data)`, `error(msg)`, JSON via `types.g.dart`, and a `documents` getter.
- `lib/src/core/instant_db.dart`: `query(map, {syncedOnly})` → `Signal<QueryResult>`; `queryOnce(map, {syncedOnly})` → `Future<QueryResult>`; `_queryEngine` is the `QueryEngine`.
- `lib/flutter_instantdb.dart` barrel exports `src/core/types.dart`, `src/query/query_engine.dart`, `src/reactive/instant_builder.dart`. A new `src/query/pagination.dart` must be added to the barrel if any public type from it is needed (the helper is internal — tests import it directly via `package:flutter_instantdb/src/query/pagination.dart`, same as `where_matcher.dart`).
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId:'test-app-id', config: InstantConfig(syncEnabled:false, persistenceDir:'test_db_<unique>'))`. Use `db.queryOnce({...})` to read results deterministically.

---

## File Structure

- **Create:** `lib/src/query/pagination.dart` — pure `paginate()` + `PageResult`.
- **Create:** `test/pagination_test.dart` — pure unit tests.
- **Modify:** `lib/src/core/types.dart` — add JSON-excluded `pageInfo` to `QueryResult`; `success` accepts optional `pageInfo`.
- **Modify:** `lib/src/query/query_engine.dart` — apply `paginate()` when cursor/fields present; thread `pageInfo` through `_processQuery`/`_executeQuery`.
- **Create:** `lib/src/query/infinite_query.dart` — `InstantInfiniteQuery` accumulator.
- **Modify:** `lib/src/core/instant_db.dart` — `infiniteQuery(...)` factory.
- **Modify:** `lib/src/reactive/instant_builder.dart` — `InstantInfiniteBuilder` widget.
- **Modify:** `lib/flutter_instantdb.dart` — export `infinite_query.dart`.
- **Modify:** `test/tx_completeness_test.dart`? No. **Create:** `test/pagination_integration_test.dart` — through public API.
- **Modify:** `CHANGELOG.md`, `README.md`.

---

## Task 1: Pure paginate() helper

**Files:**
- Create: `lib/src/query/pagination.dart`
- Test: `test/pagination_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/pagination_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/query/pagination.dart';

List<Map<String, dynamic>> rows(int n) =>
    List.generate(n, (i) => {'id': 'e$i', 'n': i});

void main() {
  group('paginate - first/after', () {
    test('first n takes the leading window', () {
      final r = paginate(rows(5), first: 2);
      expect(r.items.map((e) => e['id']), ['e0', 'e1']);
      expect(r.pageInfo['startCursor'], 'e0');
      expect(r.pageInfo['endCursor'], 'e1');
      expect(r.pageInfo['hasNextPage'], isTrue);
      expect(r.pageInfo['hasPreviousPage'], isFalse);
    });

    test('after cursor is exclusive by default', () {
      final r = paginate(rows(5), after: 'e1', first: 2);
      expect(r.items.map((e) => e['id']), ['e2', 'e3']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isTrue);
    });

    test('afterInclusive includes the cursor row', () {
      final r = paginate(rows(5), after: 'e1', afterInclusive: true, first: 2);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
    });

    test('reaching the end sets hasNextPage false', () {
      final r = paginate(rows(3), after: 'e0', first: 5);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
      expect(r.pageInfo['hasNextPage'], isFalse);
    });
  });

  group('paginate - last/before', () {
    test('last n takes the trailing window', () {
      final r = paginate(rows(5), last: 2);
      expect(r.items.map((e) => e['id']), ['e3', 'e4']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isFalse);
    });

    test('before cursor is exclusive by default', () {
      final r = paginate(rows(5), before: 'e3', last: 2);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
    });

    test('beforeInclusive includes the cursor row', () {
      final r = paginate(rows(5), before: 'e3', beforeInclusive: true, last: 2);
      expect(r.items.map((e) => e['id']), ['e2', 'e3']);
    });
  });

  group('paginate - offset/limit (no cursor keys)', () {
    test('offset then limit, in the correct order', () {
      final r = paginate(rows(10), offset: 2, limit: 3);
      expect(r.items.map((e) => e['id']), ['e2', 'e3', 'e4']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isTrue);
    });
  });

  group('paginate - fields projection', () {
    test('keeps id plus requested fields only', () {
      final r = paginate([
        {'id': 'a', 'title': 'T', 'status': 'open', 'secret': 1},
      ], fields: ['title', 'status']);
      expect(r.items.single.keys.toSet(), {'id', 'title', 'status'});
    });
  });

  group('paginate - empty', () {
    test('empty input yields null cursors and no pages', () {
      final r = paginate(<Map<String, dynamic>>[], first: 5);
      expect(r.items, isEmpty);
      expect(r.pageInfo['startCursor'], isNull);
      expect(r.pageInfo['endCursor'], isNull);
      expect(r.pageInfo['hasNextPage'], isFalse);
      expect(r.pageInfo['hasPreviousPage'], isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pagination_test.dart`
Expected: FAIL — `pagination.dart` / `paginate` undefined.

- [ ] **Step 3: Implement `lib/src/query/pagination.dart`**

```dart
/// Pure cursor-pagination + field-projection over an already-ordered list.
///
/// Cursors are modeled offline as an entity `id`'s position in the ordered set
/// (the server issues opaque cursors; offline we use id-position, which is
/// stable for a given order). Returns the sliced window plus a `pageInfo` map
/// matching @instantdb/core `PageInfoResponse`.
class PageResult {
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> pageInfo;
  const PageResult(this.items, this.pageInfo);
}

int _indexOfId(List<Map<String, dynamic>> rows, String id) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i]['id'] == id) return i;
  }
  return -1;
}

Map<String, dynamic> _project(Map<String, dynamic> row, List<String> fields) {
  final out = <String, dynamic>{'id': row['id']};
  for (final f in fields) {
    if (row.containsKey(f)) out[f] = row[f];
  }
  return out;
}

PageResult paginate(
  List<Map<String, dynamic>> ordered, {
  int? first,
  int? last,
  String? after,
  String? before,
  bool afterInclusive = false,
  bool beforeInclusive = false,
  int? offset,
  int? limit,
  List<String>? fields,
}) {
  final total = ordered.length;
  final hasCursorKeys =
      first != null || last != null || after != null || before != null;

  var startIdx = 0;
  var endIdx = total; // exclusive

  if (after != null) {
    final i = _indexOfId(ordered, after);
    if (i >= 0) startIdx = afterInclusive ? i : i + 1;
  }
  if (before != null) {
    final i = _indexOfId(ordered, before);
    if (i >= 0) endIdx = beforeInclusive ? i + 1 : i;
  }
  if (startIdx > endIdx) startIdx = endIdx;

  // first/last narrow the [startIdx, endIdx) window.
  if (first != null && first >= 0 && (endIdx - startIdx) > first) {
    endIdx = startIdx + first;
  }
  if (last != null && last >= 0 && (endIdx - startIdx) > last) {
    startIdx = endIdx - last;
  }

  // offset/limit only when no cursor keys are used.
  if (!hasCursorKeys) {
    if (offset != null && offset > 0) {
      startIdx = (startIdx + offset).clamp(0, endIdx);
    }
    if (limit != null && limit > 0 && (endIdx - startIdx) > limit) {
      endIdx = startIdx + limit;
    }
  }

  final window = ordered.sublist(startIdx, endIdx);
  final items = fields == null
      ? window
      : window.map((r) => _project(r, fields)).toList();

  final pageInfo = <String, dynamic>{
    'startCursor': window.isNotEmpty ? window.first['id'] : null,
    'endCursor': window.isNotEmpty ? window.last['id'] : null,
    'hasNextPage': endIdx < total,
    'hasPreviousPage': startIdx > 0,
  };

  return PageResult(items, pageInfo);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/pagination_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/src/query/pagination.dart test/pagination_test.dart
git commit -m "feat(query): pure paginate() with cursors, offset/limit, fields

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: QueryResult.pageInfo

**Files:**
- Modify: `lib/src/core/types.dart`
- Test: `test/pagination_test.dart` (append)

- [ ] **Step 1: Add a failing test**

Append to the `main()` body of `test/pagination_test.dart`:

```dart
  group('QueryResult.pageInfo', () {
    test('success carries optional pageInfo', () {
      final r = QueryResult.success({'todos': []},
          pageInfo: {'todos': {'hasNextPage': true}});
      expect(r.pageInfo?['todos']['hasNextPage'], isTrue);
    });

    test('success without pageInfo is null', () {
      expect(QueryResult.success({'todos': []}).pageInfo, isNull);
    });
  });
```

Add the import at the top of the file (next to the existing imports):

```dart
import 'package:flutter_instantdb/flutter_instantdb.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pagination_test.dart`
Expected: FAIL — `success` does not accept `pageInfo`; `QueryResult.pageInfo` undefined.

- [ ] **Step 3: Modify `QueryResult` in `lib/src/core/types.dart`**

Find:

```dart
class QueryResult {
  final bool isLoading;
  final Map<String, dynamic>? data;
  final String? error;

  const QueryResult({required this.isLoading, this.data, this.error});

  factory QueryResult.loading() => const QueryResult(isLoading: true);

  factory QueryResult.success(Map<String, dynamic> data) =>
      QueryResult(isLoading: false, data: data);
```

Replace with:

```dart
class QueryResult {
  final bool isLoading;
  final Map<String, dynamic>? data;
  final String? error;

  /// Per-namespace pagination info: `{ namespace: { startCursor, endCursor,
  /// hasNextPage, hasPreviousPage } }`. Null when the query did not paginate.
  /// Runtime-only — not serialized.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Map<String, dynamic>? pageInfo;

  const QueryResult({
    required this.isLoading,
    this.data,
    this.error,
    this.pageInfo,
  });

  factory QueryResult.loading() => const QueryResult(isLoading: true);

  factory QueryResult.success(
    Map<String, dynamic> data, {
    Map<String, dynamic>? pageInfo,
  }) =>
      QueryResult(isLoading: false, data: data, pageInfo: pageInfo);
```

(Leave the `error` factory, `fromJson`/`toJson`, and `documents` getter
unchanged. `pageInfo` is `@JsonKey`-excluded so `types.g.dart` needs no regen.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/pagination_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify no regen needed**

Run: `flutter analyze lib/src/core/types.dart`
Expected: "No issues found!" (only run `dart run build_runner build --delete-conflicting-outputs` if it errors on `_$QueryResult...`).

- [ ] **Step 6: Commit**

```bash
git add lib/src/core/types.dart test/pagination_test.dart
git commit -m "feat(core): add QueryResult.pageInfo (runtime-only)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire pagination + fields into the query engine

**Files:**
- Modify: `lib/src/query/query_engine.dart`
- Test: `test/pagination_integration_test.dart` (create)

- [ ] **Step 1: Write failing integration tests**

Create `test/pagination_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Pagination + fields integration', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: 'test_pg_$id'),
      );
      // Seed 5 todos with a sortable index.
      for (var i = 0; i < 5; i++) {
        await db.transact(db.tx['todos']['t$i'].update({'n': i}));
      }
    });

    tearDown(() async => db.dispose());

    test('first + order returns a leading page with pageInfo', () async {
      final r = await db.queryOnce({
        'todos': {
          '\$': {
            'order': {'n': 'asc'},
            'first': 2,
          },
        },
      });
      final items = r.documents;
      expect(items.length, 2);
      expect(items.map((e) => e['n']), [0, 1]);
      expect(r.pageInfo?['todos']?['hasNextPage'], isTrue);
      expect(r.pageInfo?['todos']?['hasPreviousPage'], isFalse);
    });

    test('after cursor pages forward', () async {
      final first = await db.queryOnce({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2},
        },
      });
      final cursor = first.pageInfo?['todos']?['endCursor'] as String;

      final next = await db.queryOnce({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2, 'after': cursor},
        },
      });
      expect(next.documents.map((e) => e['n']), [2, 3]);
    });

    test('fields projection limits returned keys', () async {
      final r = await db.queryOnce({
        'todos': {
          '\$': {'fields': ['n']},
        },
      });
      for (final doc in r.documents) {
        expect(doc.keys.toSet().difference({'id', 'n'}), isEmpty);
      }
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pagination_integration_test.dart`
Expected: FAIL — cursor/fields not applied; `pageInfo` null.

- [ ] **Step 3: Add the import**

At the top of `lib/src/query/query_engine.dart`, next to `import 'where_matcher.dart';`, add:

```dart
import 'pagination.dart';
```

- [ ] **Step 4: Change `_queryEntities` to apply pagination/fields and record pageInfo**

`_queryEntities` currently returns `Future<List<Map<String,dynamic>>>`. Add an
instance field to stash the most recent pageInfo per entity type, then apply
`paginate()` when cursor/fields keys are present.

4a. Add a private field to the `QueryEngine` class (near the other fields, e.g.
after `_subscribedQueries`):

```dart
  // pageInfo from the most recent _queryEntities call, keyed by entity type.
  final Map<String, Map<String, dynamic>> _lastPageInfo = {};
```

4b. In `_queryEntities`, detect pagination/fields keys. Find where the storage
path reads options:

```dart
    final limit = query['limit'] as int?;
    final offset = query['offset'] as int?;
    final include = query['include'] as Map<String, dynamic>?;
```

Replace that with:

```dart
    final include = query['include'] as Map<String, dynamic>?;
    final fields = (query['fields'] as List?)?.cast<String>();
    final first = query['first'] as int?;
    final last = query['last'] as int?;
    final after = query['after'] as String?;
    final before = query['before'] as String?;
    final afterInclusive = query['afterInclusive'] == true;
    final beforeInclusive = query['beforeInclusive'] == true;
    final usePaginate = fields != null ||
        first != null ||
        last != null ||
        after != null ||
        before != null;

    // When cursor/fields are present, fetch the full ordered set (no store-side
    // limit/offset) so the window + pageInfo are computed correctly.
    final limit = usePaginate ? null : query['limit'] as int?;
    final offset = usePaginate ? null : query['offset'] as int?;
```

4c. After the `_processIncludes` block, before `return entities;`, insert:

```dart
    if (usePaginate) {
      final page = paginate(
        entities,
        first: first,
        last: last,
        after: after,
        before: before,
        afterInclusive: afterInclusive,
        beforeInclusive: beforeInclusive,
        offset: query['offset'] as int?,
        limit: query['limit'] as int?,
        fields: fields,
      );
      _lastPageInfo[entityType] = page.pageInfo;
      return page.items;
    } else {
      _lastPageInfo.remove(entityType);
    }
```

(`entityType` is the method parameter; `query` is the flattened options map.)

- [ ] **Step 5: Thread pageInfo from `_processQuery` into the result**

5a. Change `_processQuery` to also return pageInfo. Find:

```dart
  Future<Map<String, dynamic>> _processQuery(
    Map<String, dynamic> query, {
    bool syncedOnly = false,
  }) async {
    final results = <String, dynamic>{};

    for (final entry in query.entries) {
      final entityType = entry.key;
```

Replace the signature and add a pageInfo accumulator:

```dart
  Future<({Map<String, dynamic> data, Map<String, dynamic> pageInfo})>
      _processQuery(
    Map<String, dynamic> query, {
    bool syncedOnly = false,
  }) async {
    final results = <String, dynamic>{};
    final pageInfo = <String, dynamic>{};

    for (final entry in query.entries) {
      final entityType = entry.key;
```

5b. At the end of `_processQuery`, find:

```dart
      results[entityType] = entities;
    }

    return results;
  }
```

Replace with:

```dart
      results[entityType] = entities;
      final pi = _lastPageInfo[entityType];
      if (pi != null) pageInfo[entityType] = pi;
    }

    return (data: results, pageInfo: pageInfo);
  }
```

5c. Update `_executeQuery` to consume the record. Find:

```dart
      final result = await _processQuery(query, syncedOnly: syncedOnly);
      batch(() {
        resultSignal.value = QueryResult.success(result);
      });
```

Replace with:

```dart
      final result = await _processQuery(query, syncedOnly: syncedOnly);
      batch(() {
        resultSignal.value = QueryResult.success(
          result.data,
          pageInfo: result.pageInfo.isEmpty ? null : result.pageInfo,
        );
      });
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/pagination_integration_test.dart`
Expected: PASS (first-page + pageInfo, after-cursor forward paging, fields projection).

- [ ] **Step 7: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing `database_closed`
teardown ones. (Plain `limit`/`offset` queries are unaffected — `usePaginate`
is false for them, so the store path is byte-identical.)

- [ ] **Step 8: Commit**

```bash
git add lib/src/query/query_engine.dart test/pagination_integration_test.dart
git commit -m "feat(query): apply cursor pagination + fields, expose pageInfo

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Infinite query helper

**Files:**
- Create: `lib/src/query/infinite_query.dart`
- Modify: `lib/src/core/instant_db.dart`
- Modify: `lib/flutter_instantdb.dart`
- Modify: `lib/src/reactive/instant_builder.dart`
- Test: `test/pagination_integration_test.dart` (append)

- [ ] **Step 1: Add a failing test**

Append to the `main()` body of `test/pagination_integration_test.dart`
(inside the same group, which already seeds 5 todos):

```dart
    test('infiniteQuery accumulates pages via loadMore', () async {
      final inf = db.infiniteQuery({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2},
        },
      }, pageSize: 2, entityType: 'todos');

      // initial page
      await Future.delayed(const Duration(milliseconds: 50));
      expect(inf.items.value.length, 2);

      await inf.loadMore();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(inf.items.value.length, 4);

      await inf.loadMore();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(inf.items.value.length, 5);
      expect(inf.hasMore.value, isFalse);

      inf.dispose();
    });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pagination_integration_test.dart`
Expected: FAIL — `db.infiniteQuery` undefined.

- [ ] **Step 3: Implement `lib/src/query/infinite_query.dart`**

```dart
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';

/// Accumulating infinite-query helper built on cursor pagination. Holds the
/// concatenated items across pages and advances via [loadMore], mirroring
/// @instantdb/react-common `useInfiniteQuery`.
class InstantInfiniteQuery {
  final Future<QueryResult> Function(Map<String, dynamic> query) _runOnce;
  final Map<String, dynamic> _baseQuery;
  final String _entityType;
  final int _pageSize;

  final Signal<List<Map<String, dynamic>>> items = signal([]);
  final Signal<bool> isLoading = signal(false);
  final Signal<bool> hasMore = signal(true);

  String? _endCursor;

  InstantInfiniteQuery({
    required Future<QueryResult> Function(Map<String, dynamic>) runOnce,
    required Map<String, dynamic> baseQuery,
    required String entityType,
    required int pageSize,
  })  : _runOnce = runOnce,
        _baseQuery = baseQuery,
        _entityType = entityType,
        _pageSize = pageSize {
    _loadFirst();
  }

  Map<String, dynamic> _queryWith({String? after}) {
    // Deep-ish copy of the base query, injecting first/after into the entity's
    // `$` options.
    final query = <String, dynamic>{};
    for (final entry in _baseQuery.entries) {
      query[entry.key] = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : entry.value;
    }
    final entity = Map<String, dynamic>.from(
      (query[_entityType] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final opts = Map<String, dynamic>.from(
      (entity[r'$'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    opts['first'] = _pageSize;
    if (after != null) opts['after'] = after;
    entity[r'$'] = opts;
    query[_entityType] = entity;
    return query;
  }

  Future<void> _loadFirst() async {
    isLoading.value = true;
    final result = await _runOnce(_queryWith());
    final docs = _docsOf(result);
    items.value = docs;
    _updateCursor(result);
    isLoading.value = false;
  }

  /// Load the next page and append it. No-op when [hasMore] is false or a load
  /// is already in flight.
  Future<void> loadMore() async {
    if (!hasMore.value || isLoading.value || _endCursor == null) return;
    isLoading.value = true;
    final result = await _runOnce(_queryWith(after: _endCursor));
    final docs = _docsOf(result);
    items.value = [...items.value, ...docs];
    _updateCursor(result);
    isLoading.value = false;
  }

  void _updateCursor(QueryResult result) {
    final pi = result.pageInfo?[_entityType] as Map?;
    _endCursor = pi?['endCursor'] as String?;
    hasMore.value = (pi?['hasNextPage'] as bool?) ?? false;
  }

  List<Map<String, dynamic>> _docsOf(QueryResult result) {
    final list = result.data?[_entityType];
    if (list is List) {
      return List<Map<String, dynamic>>.from(
        list.whereType<Map<String, dynamic>>(),
      );
    }
    return [];
  }

  void dispose() {
    items.dispose();
    isLoading.dispose();
    hasMore.dispose();
  }
}
```

- [ ] **Step 4: Add `infiniteQuery` to `InstantDB`**

In `lib/src/core/instant_db.dart`, add (near `queryOnce`):

```dart
  /// Create an accumulating infinite query over a single namespace. [pageSize]
  /// becomes the `first` count; [entityType] is the namespace to paginate.
  InstantInfiniteQuery infiniteQuery(
    Map<String, dynamic> query, {
    required String entityType,
    int pageSize = 20,
  }) {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }
    return InstantInfiniteQuery(
      runOnce: (q) => queryOnce(q),
      baseQuery: query,
      entityType: entityType,
      pageSize: pageSize,
    );
  }
```

Add the import at the top of `instant_db.dart`:

```dart
import '../query/infinite_query.dart';
```

- [ ] **Step 5: Export from the barrel**

In `lib/flutter_instantdb.dart`, in the query exports section, add:

```dart
export 'src/query/infinite_query.dart';
```

- [ ] **Step 6: Add the `InstantInfiniteBuilder` widget**

In `lib/src/reactive/instant_builder.dart`, add after `ConnectionStateBuilder`:

```dart
/// Widget that rebuilds as an [InstantInfiniteQuery] accumulates pages.
class InstantInfiniteBuilder extends StatelessWidget {
  final InstantInfiniteQuery query;
  final Widget Function(
    BuildContext context,
    List<Map<String, dynamic>> items,
    bool hasMore,
  ) builder;

  const InstantInfiniteBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return builder(context, query.items.value, query.hasMore.value);
    });
  }
}
```

If `InstantInfiniteQuery` is unresolved here, add
`import '../query/infinite_query.dart';` at the top of `instant_builder.dart`.

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/pagination_integration_test.dart`
Expected: PASS (including the infiniteQuery accumulation test).

- [ ] **Step 8: Verify analysis**

Run: `flutter analyze lib/src/query/infinite_query.dart lib/src/core/instant_db.dart lib/src/reactive/instant_builder.dart lib/flutter_instantdb.dart`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
git add lib/src/query/infinite_query.dart lib/src/core/instant_db.dart lib/flutter_instantdb.dart lib/src/reactive/instant_builder.dart test/pagination_integration_test.dart
git commit -m "feat(query): add infiniteQuery accumulator + InstantInfiniteBuilder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the existing Unreleased section in `CHANGELOG.md`:

```markdown
### Query pagination & fields
- Added cursor pagination: `first`/`after`/`last`/`before` (+ `afterInclusive`/`beforeInclusive`) under a namespace's `$` options.
- Added `pageInfo` on `QueryResult` (`startCursor`/`endCursor`/`hasNextPage`/`hasPreviousPage` per namespace).
- Added `fields` projection: `$: { fields: ['title', 'status'] }` (id always included).
- Added `db.infiniteQuery(...)` accumulator + `InstantInfiniteBuilder` widget.
```

- [ ] **Step 2: README example (only if a query section exists)**

Run: `grep -n "queryOnce\|db.query\|\\\$:\|InstantBuilder" README.md | head`
If a query section exists, add near it:

````markdown
```dart
// Cursor pagination
final page = await db.queryOnce({
  'todos': { r'$': { 'order': {'n': 'asc'}, 'first': 20 } },
});
final next = page.pageInfo?['todos']?['endCursor'];

// Infinite scroll
final feed = db.infiniteQuery(
  {'todos': {r'$': {'order': {'n': 'asc'}}}},
  entityType: 'todos', pageSize: 20,
);
await feed.loadMore();
```
````

If no such section exists, skip this step.

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only the pre-existing `info`/`warning` issues outside the files this
phase touched (the example app may emit additional deprecation infos from
Phase 3 — that is expected and not from this phase).

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document cursor pagination, fields, and infiniteQuery

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter test test/pagination_test.dart test/pagination_integration_test.dart` — all green.
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones; plain `limit`/`offset` queries unchanged.
- `flutter analyze` — no issues in any file this phase modified.
- `first/after/last/before` (+inclusive) page correctly with `pageInfo`; `fields` projects to `id`+listed; `db.infiniteQuery(...).loadMore()` accumulates and stops at `hasMore == false`.
- No breaking changes: `QueryResult.success(data)` still callable with one arg; existing queries without cursor/fields keys behave identically.

## Limitations (acceptable this round)

- Cursors are offline id-position tokens, not server-issued opaque cursors. Against the live server, the server's own `pageInfo`/cursors are authoritative; full server-cursor passthrough (adopting the server's encoded cursors and forwarding cursor opts in the subscription) is deferred — it needs a live server to verify and is out of this phase's offline scope.
- `infiniteQuery` paginates a single named namespace (`entityType`), matching the common infinite-scroll use case.

## Next phase

Phase 5 (files/storage `$files` subsystem) gets its own just-in-time plan — the final phase.
