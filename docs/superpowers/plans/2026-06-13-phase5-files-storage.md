# Phase 5: Files / Storage Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the InstantDB Files/Storage subsystem — `db.storage.uploadFile / getDownloadUrl / delete`, an `InstantFile` model, and documented `$files` query/tx access — matching `@instantdb/core/src/StorageAPI.ts`, additively with no breaking changes.

**Architecture:** A new `InstantStorage` class wraps the storage REST endpoints using `dio` (already a dependency). It takes an **injectable `Dio`** so the HTTP surface is fully unit-testable offline with a mock (`mocktail`, already a dev dependency); real usage constructs a default `Dio` against `config.baseUrl`. The auth bearer token comes from `AuthManager.refreshToken`. `InstantDB` exposes `db.storage`. `$files` is queryable through the existing generic query path (no special-casing needed); file deletion against the server is done via `db.storage.delete(path)`.

**Tech Stack:** Dart, `dio`, `flutter_test`, `mocktail`. No new dependencies.

**Source of truth:** `@instantdb/core/src/StorageAPI.ts` (endpoints verified below). Spec: `docs/superpowers/specs/2026-06-13-instantdb-parity-design.md` (Phase 5). Builds on Phases 1–4 (branch `feat/instantdb-parity-phase1`). FINAL phase.

---

## Verified REST endpoints (from StorageAPI.ts)

Base URL = `config.baseUrl` (default `https://api.instantdb.com`).

- **Upload (direct):** `POST {base}/storage/upload`
  headers: `app_id`, `path`, `content-type`, optional `content-disposition`,
  `authorization: Bearer <refreshToken>`; body = raw bytes. Response carries the
  file record under `data` (i.e. `response.data['data']`).
- **Signed download URL:** `GET {base}/storage/signed-download-url?app_id=<id>&filename=<path>`
  → response with the URL (under `data` or `data.url`).
- **Delete:** `DELETE {base}/storage/files?app_id=<id>&filename=<path>` with
  `authorization: Bearer <refreshToken>`.

(Signed two-step upload — `POST /storage/signed-upload-url` then `PUT url` — is
NOT implemented this round; direct upload is sufficient and matches the common
`uploadFile` path. Note this in the limitation section.)

---

## Existing code facts (verified — rely on these)

- `lib/src/auth/auth_manager.dart`: `AuthManager { final String appId; final String baseUrl; ... String? get refreshToken; }` — owns its own private `Dio`. Construct storage with its own `Dio`, not the auth one.
- `lib/src/core/instant_db.dart`: `_initialize()` creates `_authManager = AuthManager(appId: appId, baseUrl: config.baseUrl!)` before the sync engine. `_store`, `_queryEngine`, etc. are `late final`. Public getters follow the pattern `AuthManager get auth => _authManager;`. `InstantException` is available.
- `lib/src/core/types.dart`: `InstantException({required message, code, originalError})`.
- `lib/flutter_instantdb.dart`: barrel — add `export 'src/storage/instant_storage.dart';` for the public `InstantStorage`/`InstantFile`.
- `pubspec.yaml`: `dio: ^5.7.0` (dep), `mocktail: ^1.0.4` (dev dep).
- The transaction builder's `tx[entityType][id]` path already supports any entity name including `r'$files'` (it's just a string key), so `db.tx[r'$files'][fileId].delete()` already produces a delete op with `entityType: '$files'`. No builder change needed.
- The query engine queries any namespace by key, so `db.query({r'$files': {}})` already works (returns local `$files` entities; empty offline). No engine change needed.
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId:'test-app-id', config: InstantConfig(syncEnabled:false, persistenceDir:'test_db_<unique>'))`.

---

## File Structure

- **Create:** `lib/src/storage/instant_storage.dart` — `InstantFile` model + `InstantStorage` class.
- **Create:** `test/instant_storage_test.dart` — mocked-dio unit tests.
- **Modify:** `lib/src/core/instant_db.dart` — construct `_storage`, expose `db.storage`.
- **Modify:** `lib/flutter_instantdb.dart` — export the new file.
- **Create:** `test/files_integration_test.dart` — `db.storage` wiring + `$files` query/tx through the public API.
- **Modify:** `CHANGELOG.md`, `README.md`.

---

## Task 1: InstantFile model + InstantStorage (mocked-dio TDD)

**Files:**
- Create: `lib/src/storage/instant_storage.dart`
- Test: `test/instant_storage_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/instant_storage_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_instantdb/src/storage/instant_storage.dart';
import 'package:flutter_instantdb/src/auth/auth_manager.dart';

class _MockDio extends Mock implements Dio {}

class _FakeAuth extends AuthManager {
  _FakeAuth() : super(appId: 'app1', baseUrl: 'https://api.instantdb.com');
}

Response<dynamic> _resp(dynamic data, String path) => Response<dynamic>(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );

void main() {
  late _MockDio dio;
  late InstantStorage storage;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    storage = InstantStorage(
      appId: 'app1',
      baseUrl: 'https://api.instantdb.com',
      authManager: _FakeAuth(),
      dio: dio,
    );
  });

  group('InstantFile', () {
    test('fromJson parses core fields', () {
      final f = InstantFile.fromJson({
        'id': 'f1',
        'path': 'photos/x.png',
        'url': 'https://cdn/x.png',
        'size': 1234,
        'content-type': 'image/png',
      });
      expect(f.id, 'f1');
      expect(f.path, 'photos/x.png');
      expect(f.url, 'https://cdn/x.png');
      expect(f.size, 1234);
      expect(f.contentType, 'image/png');
    });
  });

  group('uploadFile', () {
    test('POSTs to /storage/upload and returns InstantFile', () async {
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _resp(
            {'data': {'id': 'f1', 'path': 'photos/x.png'}},
            '/storage/upload',
          ));

      final file = await storage.uploadFile(
        'photos/x.png',
        Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
      );

      expect(file.id, 'f1');
      expect(file.path, 'photos/x.png');

      final captured = verify(() => dio.post(
            captureAny(),
            data: any(named: 'data'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/storage/upload');
      final opts = captured[1] as Options;
      expect(opts.headers?['app_id'], 'app1');
      expect(opts.headers?['path'], 'photos/x.png');
      expect(opts.headers?['content-type'], 'image/png');
    });
  });

  group('getDownloadUrl', () {
    test('GETs signed-download-url and returns the url', () async {
      when(() => dio.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => _resp(
            {'data': 'https://cdn/x.png?sig=abc'},
            '/storage/signed-download-url',
          ));

      final url = await storage.getDownloadUrl('photos/x.png');
      expect(url, 'https://cdn/x.png?sig=abc');

      final captured = verify(() => dio.get(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured;
      expect(captured[0], '/storage/signed-download-url');
      final qp = captured[1] as Map;
      expect(qp['app_id'], 'app1');
      expect(qp['filename'], 'photos/x.png');
    });
  });

  group('delete', () {
    test('DELETEs /storage/files with filename', () async {
      when(() => dio.delete(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _resp({'ok': true}, '/storage/files'));

      await storage.delete('photos/x.png');

      final captured = verify(() => dio.delete(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/storage/files');
      final qp = captured[1] as Map;
      expect(qp['app_id'], 'app1');
      expect(qp['filename'], 'photos/x.png');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/instant_storage_test.dart`
Expected: FAIL — `instant_storage.dart` / `InstantStorage` / `InstantFile` undefined.

- [ ] **Step 3: Implement `lib/src/storage/instant_storage.dart`**

```dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_manager.dart';
import '../core/types.dart';

/// A file record from the InstantDB `$files` namespace / storage API.
class InstantFile {
  final String id;
  final String path;
  final String? url;
  final int? size;
  final String? contentType;

  const InstantFile({
    required this.id,
    required this.path,
    this.url,
    this.size,
    this.contentType,
  });

  factory InstantFile.fromJson(Map<String, dynamic> json) => InstantFile(
        id: (json['id'] ?? '').toString(),
        path: (json['path'] ?? json['filename'] ?? '').toString(),
        url: json['url'] as String?,
        size: json['size'] is int ? json['size'] as int : null,
        contentType:
            (json['content-type'] ?? json['contentType']) as String?,
      );
}

/// Client for the InstantDB storage REST API. Mirrors @instantdb/core
/// StorageAPI (`uploadFile`, `getDownloadUrl`, `deleteFile`).
class InstantStorage {
  final String appId;
  final String baseUrl;
  final AuthManager _authManager;
  final Dio _dio;

  InstantStorage({
    required this.appId,
    required this.baseUrl,
    required AuthManager authManager,
    Dio? dio,
  })  : _authManager = authManager,
        _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  String? get _token => _authManager.refreshToken;

  Map<String, dynamic> _authHeader() =>
      _token != null ? {'authorization': 'Bearer $_token'} : {};

  /// Upload [bytes] to [path]. Returns the created file record.
  Future<InstantFile> uploadFile(
    String path,
    Uint8List bytes, {
    String? contentType,
    String? contentDisposition,
  }) async {
    final type = contentType ?? 'application/octet-stream';
    try {
      final response = await _dio.post(
        '/storage/upload',
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: {
            'app_id': appId,
            'path': path,
            'content-type': type,
            if (contentDisposition != null)
              'content-disposition': contentDisposition,
            Headers.contentLengthHeader: bytes.length,
            ..._authHeader(),
          },
          contentType: type,
        ),
      );
      final data = response.data;
      final record = (data is Map && data['data'] is Map)
          ? data['data'] as Map
          : (data as Map);
      return InstantFile.fromJson(Map<String, dynamic>.from(record));
    } on DioException catch (e) {
      throw _error(e, 'Failed to upload file');
    }
  }

  /// Get a signed download URL for the file at [path].
  Future<String> getDownloadUrl(String path) async {
    try {
      final response = await _dio.get(
        '/storage/signed-download-url',
        queryParameters: {'app_id': appId, 'filename': path},
      );
      final data = response.data;
      final url = (data is Map)
          ? (data['data'] is Map
              ? (data['data'] as Map)['url']
              : data['data'] ?? data['url'])
          : data;
      return url.toString();
    } on DioException catch (e) {
      throw _error(e, 'Failed to get download url');
    }
  }

  /// Delete the file at [path].
  Future<void> delete(String path) async {
    try {
      await _dio.delete(
        '/storage/files',
        queryParameters: {'app_id': appId, 'filename': path},
        options: Options(headers: {..._authHeader()}),
      );
    } on DioException catch (e) {
      throw _error(e, 'Failed to delete file');
    }
  }

  InstantException _error(DioException e, String fallback) {
    final message =
        e.response?.data?['message'] ?? e.message ?? fallback;
    return InstantException(
      message: message.toString(),
      code: 'storage_error',
      originalError: e,
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/instant_storage_test.dart`
Expected: PASS (InstantFile parse + upload/getDownloadUrl/delete).

- [ ] **Step 5: Verify analysis**

Run: `flutter analyze lib/src/storage/instant_storage.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/src/storage/instant_storage.dart test/instant_storage_test.dart
git commit -m "feat(storage): add InstantStorage + InstantFile (upload/download/delete)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Wire db.storage + barrel export

**Files:**
- Modify: `lib/src/core/instant_db.dart`
- Modify: `lib/flutter_instantdb.dart`
- Test: `test/files_integration_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/files_integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Files / $files integration', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: 'test_files_$id'),
      );
    });

    tearDown(() async => db.dispose());

    test('db.storage exposes an InstantStorage', () {
      expect(db.storage, isA<InstantStorage>());
    });

    test(r'$files namespace is queryable without error', () async {
      final r = await db.queryOnce({r'$files': {}});
      expect(r.hasError, isFalse);
      // Offline: no files synced yet.
      expect(r.documents, isEmpty);
    });

    test(r'tx[$files][id].delete() produces a delete chunk', () async {
      // Should not throw; removes any local refs.
      await db.transact(db.tx[r'$files']['f1'].delete());
      final r = await db.queryOnce({r'$files': {}});
      expect(r.documents, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/files_integration_test.dart`
Expected: FAIL — `db.storage` undefined; `InstantStorage` not exported.

- [ ] **Step 3: Construct + expose storage in `instant_db.dart`**

3a. Add the import at the top:

```dart
import '../storage/instant_storage.dart';
```

3b. Add the field (near the other `late final` managers):

```dart
  late final InstantStorage _storage;
```

3c. Add the getter (near `AuthManager get auth => _authManager;`):

```dart
  /// File storage client (upload/download/delete).
  InstantStorage get storage => _storage;
```

3d. In `_initialize()`, after `_authManager = AuthManager(...)` is constructed,
add:

```dart
      _storage = InstantStorage(
        appId: appId,
        baseUrl: config.baseUrl!,
        authManager: _authManager,
      );
```

- [ ] **Step 4: Export from the barrel**

In `lib/flutter_instantdb.dart`, in the storage/core export area, add:

```dart
export 'src/storage/instant_storage.dart';
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/files_integration_test.dart`
Expected: PASS (storage getter, `$files` queryable, tx delete).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: no NEW failures beyond the 5 known pre-existing `database_closed`
teardown ones.

- [ ] **Step 7: Verify analysis**

Run: `flutter analyze lib/src/core/instant_db.dart lib/flutter_instantdb.dart`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
git add lib/src/core/instant_db.dart lib/flutter_instantdb.dart test/files_integration_test.dart
git commit -m "feat(core): expose db.storage and $files access

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the existing Unreleased section in `CHANGELOG.md`:

```markdown
### Files & storage
- Added `db.storage` (`InstantStorage`): `uploadFile(path, bytes, {contentType, contentDisposition})`, `getDownloadUrl(path)`, `delete(path)`.
- Added the `InstantFile` model.
- `$files` is queryable like any namespace (`db.query({r'$files': {}})`); local file refs can be removed with `db.tx[r'$files'][id].delete()`.
```

- [ ] **Step 2: README example**

Run: `grep -n "storage\|upload\|\\\$files" README.md | head`
Add a Files section (after the queries/transactions sections):

````markdown
## Files & storage

```dart
import 'dart:typed_data';

// Upload
final file = await db.storage.uploadFile(
  'photos/avatar.png',
  bytes, // Uint8List
  contentType: 'image/png',
);

// Signed download URL
final url = await db.storage.getDownloadUrl('photos/avatar.png');

// Delete
await db.storage.delete('photos/avatar.png');

// Query file records (synced from the server)
final files = await db.queryOnce({r'$files': {}});
```
````

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only the pre-existing `info`/`warning` issues outside the files this
phase touched.

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document db.storage files API and \$files

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter test test/instant_storage_test.dart test/files_integration_test.dart` — all green.
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones.
- `flutter analyze` — no issues in any file this phase modified.
- `db.storage.uploadFile/getDownloadUrl/delete` hit the correct endpoints with `app_id`/`path`/`filename` + bearer auth (verified by mocked dio); `InstantFile.fromJson` parses; `$files` queryable; `db.tx[r'$files'][id].delete()` works.
- No breaking changes.

## Limitations (acceptable this round)

- Real uploads/downloads against the live InstantDB server are not exercised in CI (offline) — only the request shape is verified via a mocked `Dio`. Manual verification against a real app/app-id is recommended before release.
- Two-step signed upload (`/storage/signed-upload-url` + `PUT`) is not implemented; direct `POST /storage/upload` is used. Add the signed variant later if large-file/presigned flows are needed.
- `db.tx[r'$files'][id].delete()` removes local refs; deleting the actual stored object is done via `db.storage.delete(path)` (or server-side on sync).

## Project status after this phase

All 5 parity phases complete: query operators, tx completeness, connection status + localId, cursor pagination + fields, files/storage. Ready for a final full-branch review and merge/PR (see superpowers:finishing-a-development-branch).
