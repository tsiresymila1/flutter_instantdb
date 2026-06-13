# Phase 3: Connection-Status Enum + Named Local Id Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `ConnectionStatus` enum (`connecting/opened/authenticated/closed/errored`) matching `@instantdb/core/src/clientTypes.ts`, exposed reactively, and a persistent named `getLocalId(name)` matching `react-common` `useLocalId` — additively, no breaking changes.

**Architecture:** The sync engine already tracks a `bool` connection signal (`_connectionStatus`, true only after `init-ok`). Leave it untouched (existing send-guards depend on it). Add a *parallel* `Signal<ConnectionStatus> _status` updated at each socket lifecycle point. `InstantDB` exposes `connectionStatus` (the enum signal) and keeps `isOnline` (bool) working but `@Deprecated`. `getLocalId(name)` is store-backed via the existing unused `metadata(key,value)` SQLite table — same name returns the same id across restarts.

**Tech Stack:** Dart, `flutter_test`, `sqflite_common_ffi`. No new dependencies.

**Source of truth:** `@instantdb/core/src/clientTypes.ts` (enum), `@instantdb/react-common/src/InstantReactAbstractDatabase.tsx` (`useLocalId`). Spec: `docs/superpowers/specs/2026-06-13-instantdb-parity-design.md` (Phase 3). Builds on Phases 1–2 (branch `feat/instantdb-parity-phase1`).

---

## Existing code facts (verified — rely on these)

- `lib/src/sync/sync_engine.dart`:
  - `final Signal<bool> _connectionStatus = signal(false);` (line ~41); getter `ReadonlySignal<bool> get connectionStatus` (~70).
  - `_connectWebSocket()` starts at line ~232; `_webSocket = await WebSocketManager.connect(...)` at ~249 (success point); `try/catch` sets `_connectionStatus.value = false` at ~295 on connect failure.
  - `init-ok` handler sets `_connectionStatus.value = true` at ~369 (this is "authenticated").
  - `_handleWebSocketError(Object error)` at ~647 and `_handleWebSocketClose()` at ~655 both set the bool false then `_scheduleReconnect()`.
  - Auth-error paths set the bool false at ~435, ~642, ~650, ~658.
  - `import 'package:signals_flutter/signals_flutter.dart';` and `import '../core/types.dart';` are already present (the engine uses `Operation`, `Transaction`, etc.).
- `lib/src/core/instant_db.dart`:
  - `Signal<bool> _isOnline = signal(false)` (~31); `ReadonlySignal<bool> get isOnline` (~42); an `effect` (~125) mirrors `_syncEngine.connectionStatus.value` into `_isOnline`.
  - `String? _anonymousUserId;` (~33); `String getAnonymousUserId()` (~150) returns a lazily-created in-memory uuid (synchronous).
  - `_store` is typed `StorageInterface`; `_uuid` is a `const Uuid()` field.
- `lib/src/storage/storage_interface.dart`: abstract `StorageInterface`; methods include `applyTransaction`, `queryEntities`, `resolveTargetLookups`, `getEntityType`, `clearAll`, `close`.
- `lib/src/storage/triple_store.dart`: SQLite via sqflite; schema `version: 2`; a `metadata` table `(key TEXT PRIMARY KEY, value TEXT NOT NULL)` exists (created in `_createTables`, line ~89) and is currently only cleared in `clearAll` (~1400). `_db` is the open `Database`.
- `lib/src/reactive/instant_builder.dart`: `ConnectionStatusBuilder` (StatelessWidget) with `builder(BuildContext, bool isOnline)` reading `db.isOnline.value` inside a `Watch`. Imports flutter widgets, `InstantProvider`, signals.
- `lib/flutter_instantdb.dart`: barrel that exports `src/core/types.dart`, `src/reactive/instant_builder.dart`, etc. (so a new public enum in `types.dart` and a new widget in `instant_builder.dart` are auto-exported).
- Tests init with `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` then `InstantDB.init(appId: 'test-app-id', config: InstantConfig(syncEnabled: false, persistenceDir: 'test_db_<unique>'))`. With `syncEnabled: false` the sync engine never starts, so `connectionStatus` stays at its initial value.

---

## File Structure

- **Modify:** `lib/src/core/types.dart` — add `ConnectionStatus` enum.
- **Modify:** `lib/src/sync/sync_engine.dart` — add `_status` signal + `status` getter; set it at lifecycle points.
- **Modify:** `lib/src/storage/storage_interface.dart` — declare `getLocalId`.
- **Modify:** `lib/src/storage/triple_store.dart` — implement `getLocalId` via `metadata`.
- **Modify:** `lib/src/core/instant_db.dart` — `connectionStatus` enum getter; `getLocalId`; deprecate `isOnline`/`getAnonymousUserId`.
- **Modify:** `lib/src/reactive/instant_builder.dart` — add `ConnectionStateBuilder` (enum) widget; keep `ConnectionStatusBuilder` (bool) unchanged.
- **Create:** `test/connection_localid_test.dart` — integration tests (syncEnabled:false).
- **Modify:** `CHANGELOG.md`, `README.md`.

---

## Deliberate deviation from the spec (accepted)

The spec suggested reimplementing `getAnonymousUserId()` as `getLocalId('__anonymous__')`. `getLocalId` is **async** (store-backed) while `getAnonymousUserId()` is **synchronous** and public — changing its signature to `Future<String>` is a breaking change. To honor "additive, no breaks", `getAnonymousUserId()` keeps its synchronous in-memory behavior and is only marked `@Deprecated`, pointing users to `getLocalId` for persistence. New persistent ids use `getLocalId`.

---

## Task 1: ConnectionStatus enum

**Files:**
- Modify: `lib/src/core/types.dart`
- Test: `test/connection_localid_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/connection_localid_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('ConnectionStatus enum', () {
    test('has the five upstream states', () {
      expect(ConnectionStatus.values, hasLength(5));
      expect(ConnectionStatus.values, containsAll(const [
        ConnectionStatus.connecting,
        ConnectionStatus.opened,
        ConnectionStatus.authenticated,
        ConnectionStatus.closed,
        ConnectionStatus.errored,
      ]));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/connection_localid_test.dart`
Expected: FAIL — `ConnectionStatus` undefined.

- [ ] **Step 3: Add the enum**

In `lib/src/core/types.dart`, add near the other top-level enums (e.g. after the `StorageBackend` enum):

```dart
/// Connection lifecycle status, matching @instantdb/core ConnectionStatus.
enum ConnectionStatus {
  /// Socket is being established.
  connecting,

  /// Socket is open but not yet authenticated (pre `init-ok`).
  opened,

  /// Socket is open and authenticated (post `init-ok`) — fully online.
  authenticated,

  /// Socket is closed.
  closed,

  /// Socket errored.
  errored,
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/connection_localid_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/types.dart test/connection_localid_test.dart
git commit -m "feat(core): add ConnectionStatus enum

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: SyncEngine emits ConnectionStatus

**Files:**
- Modify: `lib/src/sync/sync_engine.dart`

- [ ] **Step 1: Add the status signal + getter**

Find:

```dart
  final Signal<bool> _connectionStatus = signal(false);
```

Add immediately after it:

```dart
  final Signal<ConnectionStatus> _status = signal(ConnectionStatus.closed);
```

Find the existing getter:

```dart
  ReadonlySignal<bool> get connectionStatus => _connectionStatus.readonly();
```

Add immediately after it:

```dart
  /// Reactive connection lifecycle status.
  ReadonlySignal<ConnectionStatus> get status => _status.readonly();
```

- [ ] **Step 2: Set the status at each lifecycle point**

Make these additions (each is a single added line next to existing code — do NOT remove or change the existing `_connectionStatus.value = ...` lines):

2a. In `_connectWebSocket()`, at the very start of the `try {` block (before constructing the URL), add:

```dart
      _status.value = ConnectionStatus.connecting;
```

2b. Immediately AFTER the successful `_webSocket = await WebSocketManager.connect(wsUri.toString());` line, add:

```dart
      _status.value = ConnectionStatus.opened;
```

2c. In the `catch (e)` of `_connectWebSocket()`, next to `_connectionStatus.value = false;`, add:

```dart
      _status.value = ConnectionStatus.errored;
```

2d. In the `init-ok` handler, next to where `_connectionStatus.value = true;` is set, add:

```dart
            _status.value = ConnectionStatus.authenticated;
```

2e. In `_handleWebSocketClose()`, inside the `batch(() { ... })`, next to `_connectionStatus.value = false;`, add:

```dart
      _status.value = ConnectionStatus.closed;
```

2f. In `_handleWebSocketError(Object error)`, inside the `batch(() { ... })`, next to `_connectionStatus.value = false;`, add:

```dart
      _status.value = ConnectionStatus.errored;
```

2g. In `stop()` (the method that tears the engine down — find it near the top, it sets `_connectionStatus.value = false;` around line 112), next to that line add:

```dart
      _status.value = ConnectionStatus.closed;
```

(Leave the auth-error paths at ~435/~642/~650/~658 as-is; the close/error handlers they funnel through already update `_status`. Do not add status lines there to avoid double-setting.)

- [ ] **Step 3: Verify analysis**

Run: `flutter analyze lib/src/sync/sync_engine.dart`
Expected: "No issues found!" (no unused field — `_status` is read by the new getter).

- [ ] **Step 4: Run full suite for no regressions**

Run: `flutter test`
Expected: same baseline `+N/-5` (the only failures remain the 5 pre-existing `database_closed` teardown tests in `test/query_engine_advanced_test.dart`). No new failures.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/sync_engine.dart
git commit -m "feat(sync): emit ConnectionStatus at socket lifecycle points

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Store-backed getLocalId

**Files:**
- Modify: `lib/src/storage/storage_interface.dart`
- Modify: `lib/src/storage/triple_store.dart`
- Test: `test/connection_localid_test.dart` (append)

- [ ] **Step 1: Add failing tests**

Append to the `main()` body of `test/connection_localid_test.dart`:

```dart
  group('getLocalId', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('same name returns a stable id; different names differ', () async {
      final dir = 'test_localid_${DateTime.now().microsecondsSinceEpoch}';
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );

      final a1 = await db.getLocalId('device');
      final a2 = await db.getLocalId('device');
      final b = await db.getLocalId('session');

      expect(a1, isNotEmpty);
      expect(a1, equals(a2));
      expect(a1, isNot(equals(b)));

      await db.dispose();
    });

    test('id persists across re-init with same persistenceDir', () async {
      final dir = 'test_localid_persist_${DateTime.now().microsecondsSinceEpoch}';

      final db1 = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );
      final first = await db1.getLocalId('device');
      await db1.dispose();

      final db2 = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );
      final second = await db2.getLocalId('device');
      await db2.dispose();

      expect(second, equals(first));
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/connection_localid_test.dart`
Expected: FAIL — `getLocalId` not defined on `InstantDB`.

- [ ] **Step 3: Declare on the interface**

In `lib/src/storage/storage_interface.dart`, add to `StorageInterface`:

```dart
  /// Get (creating on first use) a stable, persisted local id for [name].
  /// Same name returns the same id across restarts; different names differ.
  Future<String> getLocalId(String name);
```

- [ ] **Step 4: Implement in `triple_store.dart`**

Add to the `TripleStore` class (place near `getEntityType`). `_db` is the open
`Database`; `Uuid` is imported (added in Phase 2) — reuse `const Uuid()`:

```dart
  @override
  Future<String> getLocalId(String name) async {
    final key = 'localId:$name';
    final existing = await _db.query(
      'metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['value'] as String;
    }
    final id = const Uuid().v4();
    await _db.insert(
      'metadata',
      {'key': key, 'value': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }
```

(`ConflictAlgorithm` is from `package:sqflite_common_ffi`/`sqflite` — already
imported in `triple_store.dart`, which uses `ConflictAlgorithm.replace` in
`addTriple`. No new import.)

- [ ] **Step 5: Add the `InstantDB.getLocalId` passthrough**

In `lib/src/core/instant_db.dart`, add a method (near `getAnonymousUserId`):

```dart
  /// Get (creating on first use) a stable, persisted local id for [name],
  /// matching @instantdb useLocalId. Survives restarts.
  Future<String> getLocalId(String name) {
    if (!_isReady.value) {
      throw InstantException(
        message: 'InstantDB not ready. Call init() first.',
      );
    }
    return _store.getLocalId(name);
  }
```

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/connection_localid_test.dart`
Expected: PASS (enum + both getLocalId tests).

- [ ] **Step 7: Commit**

```bash
git add lib/src/storage/storage_interface.dart lib/src/storage/triple_store.dart lib/src/core/instant_db.dart
git commit -m "feat(core): add persistent getLocalId(name)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: InstantDB.connectionStatus enum + deprecations + enum builder

**Files:**
- Modify: `lib/src/core/instant_db.dart`
- Modify: `lib/src/reactive/instant_builder.dart`
- Test: `test/connection_localid_test.dart` (append)

- [ ] **Step 1: Add failing test**

Append to the `main()` body of `test/connection_localid_test.dart`:

```dart
  group('InstantDB.connectionStatus', () {
    test('exposes the enum signal; closed when sync disabled', () async {
      final dir = 'test_connstatus_${DateTime.now().microsecondsSinceEpoch}';
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );

      expect(db.connectionStatus.value, ConnectionStatus.closed);
      // Deprecated bool getter still works.
      expect(db.isOnline.value, isFalse);

      await db.dispose();
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/connection_localid_test.dart`
Expected: FAIL — `connectionStatus` not defined on `InstantDB`.

- [ ] **Step 3: Add the enum getter + deprecate the bool**

In `lib/src/core/instant_db.dart`:

3a. Add a getter (near the `isOnline` getter):

```dart
  /// Reactive connection lifecycle status (connecting/opened/authenticated/
  /// closed/errored). Online == ConnectionStatus.authenticated.
  ReadonlySignal<ConnectionStatus> get connectionStatus => _syncEngine.status;
```

3b. Mark `isOnline` deprecated. Change:

```dart
  /// Whether the database is online and syncing
  ReadonlySignal<bool> get isOnline => _isOnline.readonly();
```

to:

```dart
  /// Whether the database is online and syncing.
  @Deprecated(
    'Use connectionStatus; online == ConnectionStatus.authenticated',
  )
  ReadonlySignal<bool> get isOnline => _isOnline.readonly();
```

3c. Mark `getAnonymousUserId` deprecated. Change its doc/signature line:

```dart
  /// Get the consistent anonymous user ID for this database instance
  String getAnonymousUserId() {
```

to:

```dart
  /// Get the consistent anonymous user ID for this database instance.
  @Deprecated('Use getLocalId(name) for a persistent local id')
  String getAnonymousUserId() {
```

- [ ] **Step 4: Add the enum builder widget**

In `lib/src/reactive/instant_builder.dart`, add after the existing
`ConnectionStatusBuilder` class (do NOT modify that class):

```dart
/// Widget that rebuilds with the full connection lifecycle status.
class ConnectionStateBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ConnectionStatus status) builder;

  const ConnectionStateBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);
    return Watch((context) {
      return builder(context, db.connectionStatus.value);
    });
  }
}
```

If `ConnectionStatus` is not resolved in this file, confirm the file imports the
public API or `../core/instant_db.dart`/`../core/types.dart`. It already uses
`InstantProvider.of(context)` returning an `InstantDB`, so the core import is
present; `ConnectionStatus` lives in `types.dart`. Add `import '../core/types.dart';`
only if analyze reports `ConnectionStatus` undefined.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/connection_localid_test.dart`
Expected: PASS (all groups).

- [ ] **Step 6: Verify analysis (deprecation self-references)**

Run: `flutter analyze lib/src/core/instant_db.dart lib/src/reactive/instant_builder.dart`
Expected: "No issues found!"
Note: the internal `effect` that mirrors `_syncEngine.connectionStatus` into
`_isOnline` reads the **bool** `connectionStatus` getter on the sync engine (not
the deprecated `InstantDB.isOnline`), so no self-deprecation warning is expected.
If analyze flags a `deprecated_member_use` inside this package, suppress that
single line with `// ignore: deprecated_member_use` and note it in the report.

- [ ] **Step 7: Commit**

```bash
git add lib/src/core/instant_db.dart lib/src/reactive/instant_builder.dart
git commit -m "feat(core): expose connectionStatus enum; deprecate isOnline/getAnonymousUserId

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the existing Unreleased section in `CHANGELOG.md`:

```markdown
### Connection status & local id
- Added `ConnectionStatus` enum (`connecting`/`opened`/`authenticated`/`closed`/`errored`) exposed via `db.connectionStatus` and the new `ConnectionStateBuilder` widget.
- Added persistent `db.getLocalId(name)` — a stable id per name that survives restarts (matches `useLocalId`).
- Deprecated `db.isOnline` (use `connectionStatus`; online == `authenticated`) and `db.getAnonymousUserId()` (use `getLocalId`). Both still work.
```

- [ ] **Step 2: README example (only if a connection/status section exists)**

Run: `grep -n "isOnline\|ConnectionStatus\|connection" README.md | head`
If a relevant section exists, add near it:

````markdown
```dart
// Reactive connection lifecycle
ConnectionStateBuilder(
  builder: (context, status) => Text(status.name),
);

// Stable per-name local id (survives restarts)
final deviceId = await db.getLocalId('device');
```
````

If no such section exists, skip this step.

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only the pre-existing `info`/`warning` issues in `bin/`, `example/`,
`lib/src/sync/web_socket_web.dart` (unchanged count); none in files this phase
modified.

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document ConnectionStatus enum and getLocalId

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter test test/connection_localid_test.dart` — all green (enum, getLocalId stability + persistence, connectionStatus default).
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones.
- `flutter analyze` — no issues in any file this phase modified.
- `db.connectionStatus` is a `ReadonlySignal<ConnectionStatus>`; `db.getLocalId(name)` is stable + persistent; `ConnectionStateBuilder` exists; `isOnline`/`getAnonymousUserId` deprecated but functional.
- No breaking changes: `ConnectionStatusBuilder` (bool) unchanged; `getAnonymousUserId()` still synchronous.

## Limitation (acceptable this round)

The socket lifecycle transitions (`connecting`→`opened`→`authenticated`→`closed`/`errored`) are wired but verified only by reading; full transition verification needs a live server or a mocked WebSocket transport (same constraint as Phases 4–5). Offline tests cover the enum, the `closed` default, and `getLocalId`.

## Next phase

Phase 4 (cursor pagination + fields selection + infinite query) gets its own just-in-time plan.
