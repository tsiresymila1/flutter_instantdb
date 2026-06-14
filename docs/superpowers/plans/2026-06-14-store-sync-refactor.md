# Plan — split triple_store.dart & sync_engine.dart (no behavior change)

Spec: `docs/superpowers/specs/2026-06-14-store-sync-refactor-design.md`. Branch off
`main`. **No Co-Authored-By / Claude trailer in any commit.**

Flutter: `/Users/tsiresymila/DevTools/flutter/bin` (prepend to PATH).

## THE GATE (run after EVERY task — non-negotiable)
```
flutter analyze lib/ test/        # must be clean (no new errors)
flutter test                      # must show ONLY the 5 pre-existing
                                  # database_closed failures in
                                  # test/query_engine_advanced_test.dart
```
If any other test fails or analyze errors → STOP, revert the last change, report.
The whole point is ZERO behavior change.

**DISK ~10 GiB free / 98% used.** ENOSPC → STOP + report BLOCKED. Do NOT run
build_runner. Do NOT touch sync_engine/triple_store LOGIC — only move it.

## Discipline
- **Extract** (new module) = pure functions only; rename `_x`→`x`; bodies VERBATIM.
- **`part of`** = same class, methods moved **line-for-line identical**. No
  reordering, no renames, no "small cleanups". If you're tempted to improve
  something, DON'T — note it for a later change.
- Re-derive exact line ranges yourself (file is main, unchanged from the spec's
  numbers, but confirm before cutting).

---

## Task 1 — TripleStore: extract pure eval module + tests

**Files**: new `lib/src/storage/triple_query_eval.dart`, new
`test/triple_query_eval_test.dart`, edit `lib/src/storage/triple_store.dart`.

1. Create `triple_query_eval.dart` with free functions moved VERBATIM from
   TripleStore (rename `_`→public): `matchesWhere`, `matchesOperator`,
   `compareEntities`, `compareSingleField`, `processAggregations`,
   `calculateAggregates`, `parseValue`, `deepMerge`, `withEntityId`, `mapToTriple`.
   Imports: only what those bodies use (likely `dart:convert` for `_parseValue`,
   and `package:.../types.dart` if `mapToTriple`/`withEntityId` reference `Triple`).
   If `mapToTriple` needs DB row types, keep it in the class instead — only move
   genuinely pure bodies.
2. In `triple_store.dart`: delete the moved private methods; `import` the new
   module; update call sites (`_matchesWhere(` → `matchesWhere(` etc.). Watch the
   `queryEntities` filter/order/aggregate path and `_applyOperationWithChanges`
   (`_deepMerge`).
3. Write `triple_query_eval_test.dart` (spec §Tests) — real assertions on
   where-ops/order/aggregates/deepMerge/parseValue.

GATE. Then `flutter test test/triple_query_eval_test.dart` green.

**Commit**: `refactor(store): extract pure query/aggregate helpers to triple_query_eval`

---

## Task 2 — TripleStore: part-split the class (verbatim)

**Files**: `lib/src/storage/triple_store.dart` + new `triple_store_query.dart`,
`triple_store_apply.dart`.

1. Add to `triple_store.dart` after imports:
   `part 'triple_store_query.dart';` and `part 'triple_store_apply.dart';`.
2. Each part file begins with `part of 'triple_store.dart';` and contains an
   `extension`-free continuation — i.e. the moved methods must live inside the
   class. With `part of`, you re-open the class by moving the method bodies into
   the part **inside the same `class TripleStore { ... }`**? NO — `part` files do
   not re-declare the class. Instead: the class body stays in the library file,
   and `part` files can only add **top-level** members OR the WHOLE class lives in
   one file. Dart `part` shares the library's private scope but a class body
   cannot be split across files.

   ⇒ CORRECT Dart mechanism: move whole METHODS is NOT possible across `part`
   for a single class — a class body is one lexical block. So for "split a class"
   the options are: (a) keep the class in one file (cannot physically split a
   class body across parts), or (b) convert moved methods into **extensions** in
   part files: `part of`, then `extension _TripleStoreApply on TripleStore { ...
   moved methods ... }`. Extensions in a `part of` file share library privacy and
   CAN access private fields (`_db`, `_changeController`). **Use private
   extensions in part files** to physically move method clusters out of the main
   file while keeping one class + private access + zero API change.

   So: `triple_store_apply.dart` =
   ```dart
   part of 'triple_store.dart';
   extension TripleStoreApply on TripleStore {
     Future<...> applyTransaction(...) async { ...verbatim... }
     // _ensureEntityType, _applyOperationWithChanges, rollbackTransaction,
     // getTransaction, getPendingTransactions, _markTransactionsAsFailed,
     // markTransactionSynced
   }
   ```
   NOTE: `@override` methods (interface impls like `applyTransaction`,
   `rollbackTransaction`, `getPendingTransactions`, `markTransactionSynced`)
   CANNOT be defined in an extension (extensions can't override interface members
   / aren't part of the class's interface). ⇒ Those `@override` methods MUST stay
   in the main class body. Only NON-override helpers can move to extensions.

   ⇒ Revised, safe split:
   - Keep ALL `@override`/interface methods + fields + init in `triple_store.dart`.
   - Move only PRIVATE helpers that are large into private extensions in parts:
     `triple_store_apply.dart` → `extension _Apply on TripleStore { Future
     _applyOperationWithChanges(...); Future _ensureEntityType(...); Future
     _markTransactionsAsFailed(...); }`. `triple_store_query.dart` → private
     query/lookup helpers (`_resolveLookupReferences`, `_entityExists`, etc.).
   This still meaningfully shrinks the main file (the op-switch ~290 L moves out)
   with zero API/behavior change.

GATE.

**Commit**: `refactor(store): move large private helpers into part-of extensions`

---

## Task 3 — SyncEngine: extract datalog module + tests

**Files**: new `lib/src/sync/datalog_convert.dart`, new
`test/datalog_convert_test.dart`, edit `lib/src/sync/sync_engine.dart`.

1. Create `datalog_convert.dart` (free functions, VERBATIM bodies):
   `tryConvertDatalogToCollectionFormat(Map data, {Logger? log})`,
   `extractJoinRows(...)`, `parseJoinRowsToEntities(joinRows, Map attributeCache,
   {Logger? log})`, `groupEntitiesByType(...)`. Replace `_wsLogger.x(...)` with
   `log?.x(...)`; replace `_attributeCache` with the `attributeCache` param.
2. In `sync_engine.dart`: delete the moved private methods; call the module
   functions (passing `_attributeCache` + `_wsLogger`).
3. Write `test/datalog_convert_test.dart` — characterization tests with
   representative join-row payloads + a sample attribute cache (spec §Tests).

GATE. Then `flutter test test/datalog_convert_test.dart` green.

**Commit**: `refactor(sync): extract datalog conversion to a tested module`

---

## Task 4 — SyncEngine: part-split the class (verbatim, private extensions)

**Files**: `lib/src/sync/sync_engine.dart` + new part files.

Same Dart constraint as Task 2: a class body can't be split across `part` files,
and extensions can't hold the class's interface — BUT SyncEngine implements no
interface, so its PUBLIC methods are still real members; only `@override` would
block extensions, and there are none. Still, to be safe and idiomatic:
- Keep fields + ctor + lifecycle (start/stop) + status getters + the small
  public send/cache methods in the main class body.
- Move large PRIVATE clusters into private `part of` extensions:
  - `sync_connect.dart` → `extension _Connect on SyncEngine { _connectWebSocket,
    _scheduleReconnect, _handleWebSocketError/Close, _handleAuthChange/Error }`.
  - `sync_receive.dart` → `extension _Receive on SyncEngine { _handleRemoteMessage
    + all _handle* dispatch handlers + _processCollectionData + _handleQueryResponse
    + _cleanupRecentlyCreatedEntities }`.
  - `sync_transact.dart` → `extension _Transact on SyncEngine { sendTransaction(?),
    _processQueue, _processPendingTransactions, _handleRemoteTransact,
    _applyRemoteTransaction, _handleTransactionAck/Error }`.
  Note: `sendTransaction` is PUBLIC — public methods CAN live in an extension
  (callers resolve it the same way), so it may move; but if anything calls it via
  `this.` internally that's fine too. If unsure, keep public methods in the main
  class and move only the private `_process*`/`_handle*` helpers.
- Conditional `web_socket_*` import + `WebSocketManager` usage stays accessible:
  the import is in the main library file; `part` files share it. ✓

Move methods VERBATIM. Re-run the GATE after EACH part file is moved (not just at
the end) so a break is localized.

**Commit**: `refactor(sync): move connect/receive/transact clusters into part-of extensions`

---

## Task 5 — Docs

- `CHANGELOG.md`: short "Internal: split triple_store/sync_engine into focused
  files (no behavior change); extracted + tested triple_query_eval and
  datalog_convert."
- Flip the refactor spec `Status: design` → `Status: implemented`.

GATE (final): full `flutter test` only the 5 pre-existing failures; `flutter
analyze` clean.

**Commit**: `docs: note store/sync refactor`

---

## Definition of done
- `triple_store.dart` + `sync_engine.dart` are meaningfully shorter; large pure
  clusters live in tested `triple_query_eval.dart` + `datalog_convert.dart`; large
  private clusters live in `part of` extensions.
- Public API unchanged (StorageInterface + SyncEngine public methods intact).
- New unit tests for the two extracted modules pass.
- Full `flutter test`: ONLY the 5 pre-existing failures, at every task boundary.
- No Claude trailer. `example/pubspec.lock` not committed.
