# refactor — split triple_store.dart & sync_engine.dart

Status: implemented. Two core files are very long single classes: `TripleStore`
(1450 L) and `SyncEngine` (1922 L). Goal: smaller, clearer files with **zero
behavior change**. Approach is dictated by coupling + test coverage.

## Hard rule

**No behavior change.** Two mechanisms only:
- **Extract** (real new module) ONLY pure, field-free clusters → free functions
  in a new file, with NEW unit tests.
- **`part of`** (same class, verbatim physical move) for everything that touches
  instance fields. A `part` move must be **line-for-line identical** logic — no
  reordering, no "while I'm here" edits.

**Gate after EVERY task**: `flutter analyze` clean AND full `flutter test` shows
ONLY the 5 pre-existing `database_closed` failures in
`test/query_engine_advanced_test.dart`. Anything else = regression → stop.

## Coverage reality (why the approach differs per file)

- **TripleStore**: the pure query/filter/aggregate cluster (~360 L) touches NO
  instance fields and is well-exercised by FFI integration tests
  (`query_engine_advanced_test`, `relational_include_test`, `tx_completeness_test`,
  `typed_*`). Safe to extract.
- **SyncEngine**: receive/transact/query clusters are densely coupled through
  `_attributeCache`, `_sentEventIds`, `_recentlyCreatedEntities`,
  `_lastProcessedData`, Signals, `_webSocket`, `_syncQueue` — they CANNOT become
  separate classes. The **datalog-conversion** sub-cluster is near-pure (only
  reads `_attributeCache` + logs) and has **ZERO test coverage** today, in the
  project's most regression-prone area (v0.2.x changelog). It is the one safe
  extraction AND the highest-value place to add tests.

## Existing code facts (verified — trust these)

### TripleStore (`lib/src/storage/triple_store.dart`)
- `class TripleStore implements StorageInterface`. Fields: `_db`, `appId`,
  `_schema`, `_changeController`. Only `TripleStore.init(...)` is called
  externally (`instant_db.dart:100`); all else via `StorageInterface`.
- **Pure (field-free) cluster** — extract targets: `_matchesWhere` (L320-374),
  `_matchesOperator` (L376-500), `_compareEntities` (L599-629),
  `_compareSingleField` (L631-653), `_processAggregations` (L655-689),
  `_calculateAggregates` (L691-759), `_parseValue` (L761-773),
  `_deepMerge` (L1245-1264), `_withEntityId` (L591-597), `_mapToTriple` (L775-785).
- **Field-coupled clusters** (`part of` only): init/_createTables/_upgradeTables
  (L27-109), CRUD (addTriple/retract/queryBy*/getEntityType/getLocalId,
  L112-228), `queryEntities` (L231-318), lookup resolution (L503-589, L848-902),
  apply (applyTransaction L787-845, `_ensureEntityType` L917-948,
  `_applyOperationWithChanges` L950-1242 — the op switch), tx mgmt
  (rollback/getPending/markSynced/getTransaction L1267-1380), maintenance
  (vacuum L1391-1429, clearAll L1431-1442, close L1445-1449).
- `where_matcher.dart`/`pagination.dart` are used by `QueryEngine`, NOT
  TripleStore — TripleStore has its own parallel logic. Do NOT try to merge them
  in this refactor (that would be a behavior change).

### SyncEngine (`lib/src/sync/sync_engine.dart`)
- `class SyncEngine` (no interface). Heavy shared state (see coverage section).
- **Near-pure datalog cluster** — extract targets: `_tryConvertDatalogToCollectionFormat`
  (L1503-1574), `_extractJoinRows` (L1577-1612), `_parseJoinRowsToEntities`
  (L1615-1673, reads `_attributeCache` → pass as param), `_groupEntitiesByType`
  (L1676-1695). Currently log via `_wsLogger` (pass a `Logger` param or keep logs
  minimal).
- **Field-coupled clusters** (`part of` only): connect/reconnect/auth
  (L237-306, L648-694), send (sendQuery/sendJoinRoom/sendLeaveRoom/sendPresence/
  _generateEventId, L122-235, 308-317), receive dispatch
  (`_handleRemoteMessage` switch L319-646 + handlers), transact
  (sendTransaction L1072-1159, `_processQueue` L1161-1423,
  _processPendingTransactions, _handleRemoteTransact L720-884, _applyRemoteTransaction,
  acks), query-response (L911-1045, _handleQueryResponse L1447-1500,
  _processCollectionData L1698-1829, cache L1880-1921), presence handlers
  (L1831-1878).
- Conditional import `web_socket_*.dart` (L16-18, provides `WebSocketManager`,
  used only in `_connectWebSocket`). **A `part` file has no imports** — the
  conditional import stays in the main library file; `part` files inherit it. ✓
- Public API to preserve: `connectionStatus`, `status`, `start`, `stop`,
  `sendQuery`, `sendJoinRoom`, `sendLeaveRoom`, `sendPresence`, `sendTransaction`,
  `getCachedQueryResult`, `clearCachedQueryResult`, `clearAllCachedResults`, ctor.
- No `part`/`part of` precedent in hand-written code (only `types.g.dart` codegen).

## Design

### TripleStore
- **New `lib/src/storage/triple_query_eval.dart`** (pure, no imports beyond
  dart:core/convert): free functions `matchesWhere`, `matchesOperator`,
  `compareEntities`, `compareSingleField`, `processAggregations`,
  `calculateAggregates`, `parseValue`, `deepMerge`, `withEntityId`, `mapToTriple`.
  Move bodies verbatim; rename `_x` → `x`. Update call sites in `triple_store.dart`.
- **`part` split** the remaining class:
  - `triple_store.dart` (library): imports, `class TripleStore` header + fields +
    init/_createTables/_upgradeTables/close/`changes` + CRUD + getLocalId +
    getEntityType + lookup resolution + vacuum/clearAll, and the `part`
    directives.
  - `part 'triple_store_query.dart'`: `queryEntities` (now calling
    `matchesWhere`/`compareEntities`/`processAggregations` from the eval module).
  - `part 'triple_store_apply.dart'`: applyTransaction, `_ensureEntityType`,
    `_applyOperationWithChanges`, rollbackTransaction, getTransaction,
    getPendingTransactions, `_markTransactionsAsFailed`, markTransactionSynced.

### SyncEngine
- **New `lib/src/sync/datalog_convert.dart`** (pure-ish): free functions
  `tryConvertDatalogToCollectionFormat(data, {Logger? log})`,
  `extractJoinRows(...)`, `parseJoinRowsToEntities(joinRows, attributeCache,
  {Logger? log})`, `groupEntitiesByType(...)`. Move bodies verbatim; replace
  `_wsLogger` with the optional `log` param; replace `_attributeCache` reads with
  the passed `attributeCache`. SyncEngine delegates to these.
- **`part` split** the remaining class (verbatim):
  - `sync_engine.dart` (library): imports (incl. conditional websocket), `class
    SyncEngine` header + fields + ctor + start/stop + status getters + cache
    methods + the datalog delegation calls + `part` directives.
  - `part 'sync_connect.dart'`: `_connectWebSocket`, `_scheduleReconnect`,
    `_handleWebSocketError/Close`, `_handleAuthChange/Error`.
  - `part 'sync_send.dart'`: sendQuery/sendJoinRoom/sendLeaveRoom/sendPresence/
    `_generateEventId`.
  - `part 'sync_receive.dart'`: `_handleRemoteMessage` + per-op handlers
    (invalidation/refresh/refreshOk/presence/error) + `_processCollectionData` +
    `_handleQueryResponse` + `_cleanupRecentlyCreatedEntities`.
  - `part 'sync_transact.dart'`: sendTransaction, `_processQueue`,
    `_processPendingTransactions`, `_handleRemoteTransact`,
    `_applyRemoteTransaction`, `_handleTransactionAck/Error`.
  - (Exact cluster→part assignment may be adjusted; rule: each method moves
    verbatim and the file compiles + tests pass.)

## Tests (new — fill the gaps the extraction exposes)

- **`test/triple_query_eval_test.dart`**: unit-test the extracted pure functions
  directly — `matchesWhere` with `$gt/$lt/$in/$like/$ilike/and/or`,
  `compareEntities` ordering (asc/desc, multi-field), `calculateAggregates`
  (count/sum/avg/min/max + groupBy), `deepMerge`, `parseValue`. (These had no
  direct unit test before — net coverage gain.)
- **`test/datalog_convert_test.dart`**: characterization tests for the extracted
  datalog functions using representative InstantDB join-row payloads + a sample
  attribute cache — assert `extractJoinRows` count, `parseJoinRowsToEntities`
  reconstructs entity maps keyed correctly, `groupEntitiesByType` buckets by
  type, and `tryConvertDatalogToCollectionFormat` end-to-end on a sample. Locks
  the previously-untested datalog format handling.
- Existing FFI integration tests remain the net for the `part`-split store/apply
  paths. The SyncEngine `part` splits rely on `flutter analyze` + the
  verbatim-move review (no behavior tests exist for the message path).

## Risks

- **SyncEngine `part` splits have no behavior test net.** Mitigation: moves are
  strictly verbatim; `flutter analyze` catches compile breaks; a review pass
  diffs each moved method against the original to confirm zero logic change.
- **`_applyOperationWithChanges` (op switch) + `_processQueue` (tx encoding)** are
  the most order-sensitive bodies — move verbatim, never reorder.
- **Datalog extraction** swaps `_attributeCache`/`_wsLogger` for params — verify
  the param is threaded at every original use site.
- `part of` requires the part files declare `part of '<library>.dart';` (or the
  library name) and the library file declare each `part`. Get the directive
  spelling right or it won't compile (caught by analyze).

## Next

Optional later: unify TripleStore's `_matchesWhere` with `QueryEngine`'s
`where_matcher.dart` (a real behavior-affecting consolidation — separate, tested
change, NOT part of this no-behavior-change refactor).
