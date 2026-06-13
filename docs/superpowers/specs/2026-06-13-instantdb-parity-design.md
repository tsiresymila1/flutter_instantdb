# Design: flutter_instantdb parity with @instantdb/core, react, react-native

**Date:** 2026-06-13
**Status:** Approved (brainstorming) — pending spec review
**Scope decision:** All 5 phases in one spec. Additive, no breaking changes.

## Goal

Bring `flutter_instantdb` to feature parity with the current InstantDB JS clients
(`@instantdb/core`, `@instantdb/react`, `@instantdb/react-common`,
`@instantdb/react-native`) as found in the `instantdb/instant` GitHub repo.

Parity is measured against the canonical TypeScript source:
- Query operators / pagination: `core/src/instaql.ts`, `core/src/queryTypes.ts`
- Transactions: `core/src/instatx.ts`
- Storage / files: `core/src/StorageAPI.ts`
- Hooks / reactive surface: `react-common/src/InstantReactAbstractDatabase.tsx`,
  `react-common/src/InstantReactRoom.ts`
- Connection status: `core/src/clientTypes.ts`

## Constraint: additive, no breaks

The package has pre-existing non-standard API that diverges from upstream
(`$nin`, `$exists`, `$eq` query operators; `bool` connection status;
`getAnonymousUserId()`). These stay working. Where upstream has a different
canonical form, we add the upstream form and mark the divergent one
`@Deprecated('...')` with a pointer to the replacement. No symbol is removed in
this round.

## Current state (verified)

| Area | Current Flutter | Upstream canonical | Gap |
|---|---|---|---|
| Where ops | `$eq $ne $gt $gte $lt $lte $in $nin $exists $isNull` | `$gt $gte $lt $lte $ne $in $like $ilike $isNull $not` + `and`/`or` | add `$like $ilike $not`, `and`/`or` |
| Pagination | `limit` `offset` | `limit offset first after last before afterInclusive beforeInclusive` + `pageInfo` | add cursors + `pageInfo` |
| Fields | — | `$: { fields: [...] }` | add projection |
| Tx ops | `create update merge delete link unlink` + standalone `lookup()` | same + chainable `lookup`, `ruleParams`, `{upsert:false}` | add chainable lookup, ruleParams, upsert opt |
| Files | none | `$files` entity, `storage.uploadFile/delete/getDownloadUrl`, `tx.$files[id].delete()` | new subsystem |
| Connection status | `ReadonlySignal<bool>` | enum `connecting opened authenticated closed errored` | add enum |
| Local id | `getAnonymousUserId()` (single) | `useLocalId(name)` (named, persistent) | add named persistent id |
| Infinite query | — | `useInfiniteQuery` | add (phase 4) |

The reactive/presence layer (`InstantBuilder`, `getPresence/setPresence`,
`getCursors/updateCursor`, `setTyping/getTyping`, `publishTopic/subscribeTopic`,
`joinRoom/leaveRoom`) already maps cleanly to the React room hooks and is **not**
changed except where phase 3/4 add `pageInfo` and connection enum.

---

## Phase 1 — Query operators

**Files:** `lib/src/query/query_engine.dart` (`_evaluateWhereCondition`).

Add operators to the per-field operator `switch`:

- `$like` — case-sensitive SQL-style match. `%` = any run, `_` = single char.
  Translate the pattern to a Dart `RegExp` (escape regex metachars, then
  `%`→`.*`, `_`→`.`). Match against `fieldValue.toString()`. Null field → no match.
- `$ilike` — same as `$like` with `caseSensitive: false`.
- `$not` — inequality, alias of `$ne` semantics (`fieldValue == value` → false).
  Per upstream, `$not` is the deprecated spelling of `$ne`; both supported.

Add top-level logical combinators handled **before** the per-field loop in
`_evaluateWhereCondition`:

- `and: [ {..}, {..} ]` — every sub-where must pass (recurse).
- `or: [ {..}, {..} ]` — at least one sub-where must pass (recurse).

A `where` map may mix logical keys and field keys; all must hold (logical keys
AND with the rest).

Dot-notation nested field keys (`'todos.title'`) resolve by walking nested
maps/lists on the doc; if any segment is a list, match if **any** element
satisfies the remainder (mirrors upstream nested semantics). This is needed for
`and`/`or` over related entities.

Existing `$nin`, `$exists`, `$eq` retained unchanged (non-standard extensions,
left as-is — no deprecation, they are harmless supersets).

**Tests (TDD):** unit tests on `_evaluateWhereCondition` (extract to a testable
pure function if not already) covering each operator, `and`/`or` nesting,
dot-notation, null handling, `%`/`_` wildcards, case sensitivity.

## Phase 2 — Transaction completeness

**Files:** `lib/src/core/transaction_builder.dart`, `lib/src/core/types.dart`
(Operation `opts`/lookup support), `lib/src/storage/triple_store.dart`
(apply lookup + upsert semantics).

1. **Chainable `lookup`.** Add `lookup(String attribute, dynamic value)` to
   `EntityBuilder`, returning an `EntityInstanceBuilder` whose target is a
   `LookupRef` instead of a concrete id:
   ```dart
   db.tx.profiles.lookup('email', 'a@b.com').update({'name': 'A'});
   db.tx.$files.lookup('path', 'photos/x.png').delete();
   ```
   `EntityInstanceBuilder` gains an optional `LookupRef? lookupRef` alongside
   `entityId`. `Operation` carries the `LookupRef` so the triple store resolves
   the entity (find by attribute==value; create if absent on write ops).
   The standalone `lookup(entityType, attr, value)` top-level helper stays for
   back-compat.

2. **`ruleParams`.** Add `ruleParams(Map<String, dynamic> args)` to
   `EntityInstanceBuilder` and `TransactionChunk`, chainable like upstream:
   ```dart
   db.tx.docs[id].update({...}).ruleParams({'token': t});
   ```
   Stored on the `Operation`/chunk and forwarded to the sync engine in the
   transaction payload (server uses it for permission rules). Offline/local
   apply ignores it.

3. **`upsert` option.** `update` and `merge` accept an optional
   `TxOpts? opts` with `bool upsert` (default `true`):
   ```dart
   db.tx.goals[id].update({...}, opts: TxOpts(upsert: false));
   ```
   `upsert:false` → strict mode: triple store throws / no-ops if the entity does
   not already exist, instead of creating it. Default preserves current behavior.

**Tests:** triple-store tests for lookup-resolve-or-create, upsert:false on
missing entity, ruleParams round-trips into the sync payload (mock sync).

## Phase 3 — Connection status enum + named local id

**Files:** `lib/src/sync/sync_engine.dart`, `lib/src/core/instant_db.dart`,
`lib/src/core/types.dart`, `lib/src/storage/triple_store.dart` (local-id store).

1. **`ConnectionStatus` enum** matching upstream:
   `connecting, opened, authenticated, closed, errored`.
   - `SyncEngine` exposes `ReadonlySignal<ConnectionStatus> status`.
   - Map socket lifecycle: opening→`connecting`, open(pre-auth)→`opened`,
     auth-ok→`authenticated`, clean close→`closed`, error→`errored`.
   - `InstantDB.connectionStatus` → the new enum signal.
   - Existing `bool isOnline` / `connectionStatus` bool getter kept, marked
     `@Deprecated('Use connectionStatus enum (authenticated == online)')`,
     derived as `status == authenticated`.
   - New `ConnectionStatusBuilder` already exists; extend it to expose the enum
     while keeping the bool callback overload working.

2. **`localId(String name)`** — named, persistent device id:
   ```dart
   final deviceId = await db.getLocalId('device');
   ```
   Persisted in the triple store under a reserved `__localIds` key-value table
   (one row per name). Generated with `uuid.v4()` on first request, stable
   across restarts. `getAnonymousUserId()` kept, reimplemented as
   `getLocalId('__anonymous__')` for continuity, marked `@Deprecated`.

**Tests:** enum transitions driven by a mock socket; `getLocalId` stability
across store reopen; same name → same id, different name → different id.

## Phase 4 — Cursor pagination + fields selection

**Files:** `lib/src/query/query_engine.dart`, `lib/src/sync/sync_engine.dart`
(server cursor passthrough), `lib/src/core/types.dart` (`QueryResult.pageInfo`).

1. **`fields` projection.** `$: { fields: ['title','status'] }` (and the existing
   top-level `query['fields']`) restrict returned attributes; `id` always
   included. Applied in the query engine after where/order, before returning.

2. **Cursor pagination.** Support `first`, `after`, `last`, `before`,
   `afterInclusive`, `beforeInclusive` in query options.
   - A `Cursor` is the opaque server-issued token; locally we model it as the
     ordered position key `(serverCreatedAt, id)` so offline paging still works.
   - `QueryResult` gains `PageInfo? pageInfo` per namespace:
     `{ startCursor, endCursor, hasNextPage, hasPreviousPage }`.
   - When syncing, forward cursor opts to the server query and adopt the
     server `pageInfo`; offline, compute from the locally ordered/sliced set.
   - `limit`/`offset` retained and unchanged.

3. **`useInfiniteQuery` equivalent.** Add `InstantInfiniteQuery` /
   `db.infiniteQuery(...)` returning a signal plus `loadMore()` that advances
   `after`/`endCursor`, mirroring `react-common/useInfiniteQuery`. A
   `InstantInfiniteBuilder` widget wraps it.

**Tests:** offline paging slices and `pageInfo` flags (hasNext/hasPrev at
boundaries); `fields` projection keeps `id`; `loadMore` accumulates.

## Phase 5 — Files / Storage subsystem

**New file:** `lib/src/storage/instant_storage.dart` (`InstantStorage` class).
**Touches:** `instant_db.dart` (expose `db.storage`), `transaction_builder.dart`
(`$files` namespace delete/link), `flutter_instantdb.dart` (export).

REST base = `config.baseUrl` (`https://api.instantdb.com`). Endpoints verified
from `StorageAPI.ts`:

- **Upload (direct):** `POST {base}/storage/upload`
  headers: `app_id`, `path`, `content-type`, `authorization: Bearer <token>`,
  optional `content-disposition`; body = bytes. Returns file record.
- **Signed upload (2-step):** `POST {base}/storage/signed-upload-url`
  body `{app_id, filename}` → `{url}`; then `PUT url` with body = bytes.
- **Download url:** `GET {base}/storage/signed-download-url?app_id=&filename=`
  → signed URL.
- **Delete:** `DELETE {base}/storage/files?app_id=&filename=` (also reachable via
  `db.tx.$files[id].delete()` / `db.tx.$files.lookup('path', p).delete()`).

Dart API:
```dart
class InstantFile { final String id, path; final String? url; final int? size;
  final String? contentType; /* from $files entity */ }

class InstantStorage {
  Future<InstantFile> uploadFile(String path, Uint8List bytes,
      {String? contentType, String? contentDisposition});
  Future<String> getDownloadUrl(String path);
  Future<void> delete(String path);
}
```
- `db.storage` getter exposes it. Uses `dio` (already a dep) + auth token from
  `AuthManager`.
- `$files` is queryable like any namespace: `db.query({r'$files': {}})`.
- `db.tx.$files[id].delete()` works via the chainable builder (phase 2 lookup
  also applies: delete by `path`).

**Tests:** mock dio for each endpoint (upload direct + signed, download, delete);
`$files` query returns file records; `tx.$files[id].delete()` emits correct op.

---

## Cross-cutting

- **Docs:** update `README.md`, `CLAUDE.md` "Implementation Status" + version
  history, and the docs site source for each shipped phase.
- **Version:** bump `pubspec.yaml` (minor per phase or one minor for the set —
  decided at PR time). `CHANGELOG.md` entry per phase.
- **Lints/format:** `flutter analyze` clean, `dart format lib/ test/`.
- **No new runtime deps:** uses existing `dio`, `uuid`, `signals_flutter`,
  `sqflite`.

## Out of scope (this round)

- Schema codegen changes / Acanthis schema parity beyond what phases need.
- SSR / Next-specific helpers (`next-ssr`) — not applicable to Flutter.
- Devtool, OAuth provider-specific flows beyond existing idToken/code exchange.

## Phase ordering & checkpoints

1 → 2 → 3 → 4 → 5. Each phase: red/green TDD, `flutter analyze` clean, commit,
checkpoint review before the next. Phases 1–3 are pure-Dart/offline-testable;
4–5 need a live app or mocked transport for full verification.
