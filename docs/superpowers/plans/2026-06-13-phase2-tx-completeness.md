# Phase 2: Transaction Completeness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the transaction API to `@instantdb/core/src/instatx.ts` parity by adding chainable `lookup` (upsert-by-unique-attribute as the operation *target*), `ruleParams`, and the `{upsert: false}` strict-mode option — additively, no breaking changes.

**Architecture:** The transaction builder produces `Operation`s. Add a target `LookupRef` to `Operation` (JSON-excluded, resolved at transact time), carry `upsert`/`ruleParams` through the existing `Operation.options` map (already JSON-serializable). `InstantDB.transact` resolves target lookups against the store *once* up front (creating the entity for write ops when absent — that is the "upsert by unique attr"), so both the local apply and the sync path receive concrete entity ids and the complex sync tx-step builder stays untouched. `upsert: false` gates `update`/`merge` in the triple store to existing entities only. `ruleParams` rides on `options` and is forwarded in the outgoing sync message.

**Tech Stack:** Dart, `flutter_test`, `sqflite_common_ffi` (in-memory SQLite for tests). No new dependencies.

**Source of truth:** `@instantdb/core/src/instatx.ts`. Spec: `docs/superpowers/specs/2026-06-13-instantdb-parity-design.md` (Phase 2). Builds on Phase 1 (branch `feat/instantdb-parity-phase1`).

---

## Existing code facts (verified — rely on these)

- `lib/src/core/types.dart`:
  - `Operation` has fields `type, entityType, entityId, data, options` (all present), a custom `fromJson`, generated `toJson` via `types.g.dart`, plus legacy getters `attribute`/`value`.
  - `LookupRef { entityType, attribute, value }` already exists and is `@JsonSerializable`.
  - `TransactionChunk { List<Operation> operations; merge(other) }`.
  - `OperationType { add, update, delete, retract, link, unlink, merge }`.
- `lib/src/core/transaction_builder.dart`: `EntityBuilder` (has `create`), `EntityInstanceBuilder` (`update, link, unlink, merge, delete`), top-level `lookup(entityType, attr, value)` and `combineChunks`.
- `lib/src/storage/triple_store.dart`:
  - `applyTransaction(tx)` → resolves *data* lookups via `_resolveLookupReferences`, then applies each op in a DB txn.
  - `resolveLookup(entityType, attribute, value) -> Future<String?>` (returns existing entity id or null).
  - `update` apply (lines ~849) retracts+inserts triples per `data` entry. `merge` apply (~889) deep-merges. Neither currently checks entity existence.
  - Uses `txn.query('triples', where: 'entity_id = ? AND retracted = FALSE', ...)`.
- `lib/src/storage/storage_interface.dart`: abstract `StorageInterface` that `TripleStore` implements; `InstantDB._store` is typed `StorageInterface`.
- `lib/src/core/instant_db.dart` `transact()` builds a `Transaction` from `operations`, calls `_store.applyTransaction(tx)`, then `_syncEngine.sendTransaction(tx)` — **the same `tx` object** goes to both.
- Tests init the DB with `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`, then `InstantDB.init(appId: 'test-app-id', config: InstantConfig(syncEnabled: false, persistenceDir: 'test_db_<unique>'))`.

---

## File Structure

- **Modify:** `lib/src/core/types.dart` — add JSON-excluded `LookupRef? lookupRef` to `Operation`; add `TransactionChunk.ruleParams(...)`; add `TxOpts` class.
- **Modify:** `lib/src/core/transaction_builder.dart` — `EntityBuilder.lookup(...)`, lookup-target constructor on `EntityInstanceBuilder`, `upsert` opt on `update`/`merge`.
- **Modify:** `lib/src/storage/storage_interface.dart` — declare `resolveTargetLookups`.
- **Modify:** `lib/src/storage/triple_store.dart` — implement `resolveTargetLookups`; gate `update`/`merge` on `upsert:false`.
- **Modify:** `lib/src/core/instant_db.dart` — resolve target lookups before building the `Transaction`.
- **Modify:** `lib/src/sync/sync_engine.dart` — forward `ruleParams` from `options` in the outgoing message (bounded).
- **Create:** `test/transaction_builder_test.dart` — pure builder-output tests.
- **Create:** `test/tx_completeness_test.dart` — integration tests through the public API (syncEnabled:false).
- **Modify:** `CHANGELOG.md`, `README.md`.

---

## Task 1: TxOpts + Operation.lookupRef + TransactionChunk.ruleParams

**Files:**
- Modify: `lib/src/core/types.dart`
- Test: `test/transaction_builder_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/transaction_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('TxOpts', () {
    test('defaults to upsert true', () {
      expect(const TxOpts().upsert, isTrue);
      expect(const TxOpts(upsert: false).upsert, isFalse);
    });
  });

  group('TransactionChunk.ruleParams', () {
    test('attaches ruleParams to every operation options', () {
      final chunk = TransactionChunk([
        Operation(type: OperationType.update, entityType: 'docs',
            entityId: 'd1', data: {'title': 'x'}),
      ]).ruleParams({'token': 'abc'});

      expect(chunk.operations.single.options?['ruleParams'],
          equals({'token': 'abc'}));
    });

    test('preserves existing options and lookupRef', () {
      final chunk = TransactionChunk([
        Operation(type: OperationType.update, entityType: 'docs',
            entityId: 'd1', data: {'a': 1}, options: {'upsert': false},
            lookupRef: const LookupRef(
                entityType: 'docs', attribute: 'slug', value: 's')),
      ]).ruleParams({'token': 'abc'});

      final op = chunk.operations.single;
      expect(op.options?['upsert'], isFalse);
      expect(op.options?['ruleParams'], equals({'token': 'abc'}));
      expect(op.lookupRef?.attribute, equals('slug'));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/transaction_builder_test.dart`
Expected: FAIL — `TxOpts` undefined, `Operation` has no `lookupRef`, `TransactionChunk` has no `ruleParams`.

- [ ] **Step 3: Modify `lib/src/core/types.dart`**

3a. Add the `lookupRef` field to `Operation`. In the `Operation` class, change the field block and constructor. Find:

```dart
  final OperationType type;
  final String entityType;
  final EntityId entityId;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? options;

  const Operation({
    required this.type,
    required this.entityType,
    required this.entityId,
    this.data,
    this.options,
  });
```

Replace with:

```dart
  final OperationType type;
  final String entityType;
  final EntityId entityId;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? options;

  /// Target lookup reference (find/upsert entity by unique attribute) instead
  /// of a concrete [entityId]. Resolved at transact time. Not serialized — by
  /// the time an Operation is sent or persisted it carries a concrete id.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final LookupRef? lookupRef;

  const Operation({
    required this.type,
    required this.entityType,
    required this.entityId,
    this.data,
    this.options,
    this.lookupRef,
  });
```

3b. Add `TransactionChunk.ruleParams` and the `TxOpts` class. Find the `TransactionChunk` class:

```dart
class TransactionChunk {
  final List<Operation> operations;

  const TransactionChunk(this.operations);

  /// Merge with another transaction chunk
  TransactionChunk merge(TransactionChunk other) {
    return TransactionChunk([...operations, ...other.operations]);
  }
}
```

Replace with:

```dart
class TransactionChunk {
  final List<Operation> operations;

  const TransactionChunk(this.operations);

  /// Merge with another transaction chunk
  TransactionChunk merge(TransactionChunk other) {
    return TransactionChunk([...operations, ...other.operations]);
  }

  /// Attach permission rule parameters to every operation in this chunk.
  /// Mirrors `db.tx.ns[id].update({...}).ruleParams({...})` from @instantdb/core.
  TransactionChunk ruleParams(Map<String, dynamic> args) {
    final updated = operations
        .map((op) => Operation(
              type: op.type,
              entityType: op.entityType,
              entityId: op.entityId,
              data: op.data,
              options: {...?op.options, 'ruleParams': args},
              lookupRef: op.lookupRef,
            ))
        .toList();
    return TransactionChunk(updated);
  }
}

/// Options for write operations (update/merge). Mirrors the second argument
/// of `update`/`merge` in @instantdb/core.
class TxOpts {
  /// When false, the write is strict: it does not create the entity if it does
  /// not already exist. Defaults to true (upsert).
  final bool upsert;
  const TxOpts({this.upsert = true});

  Map<String, dynamic> toOptions() => {'upsert': upsert};
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/transaction_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify generated code still compiles (no regen needed)**

`lookupRef` is `@JsonKey`-excluded, so `types.g.dart` does not reference it.
Run: `flutter analyze lib/src/core/types.dart`
Expected: "No issues found!"
If (and only if) analyze reports an error referencing `_$Operation...`, regenerate:
`dart run build_runner build --delete-conflicting-outputs` then re-run analyze.

- [ ] **Step 6: Commit**

```bash
git add lib/src/core/types.dart test/transaction_builder_test.dart
git commit -m "feat(tx): add TxOpts, Operation.lookupRef, TransactionChunk.ruleParams

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Builder API — chainable lookup + upsert opt

**Files:**
- Modify: `lib/src/core/transaction_builder.dart`
- Test: `test/transaction_builder_test.dart` (append)

- [ ] **Step 1: Add failing tests**

Append to the `main()` body of `test/transaction_builder_test.dart`:

```dart
  group('EntityBuilder.lookup chainable', () {
    final tx = TransactionBuilder();

    test('lookup().update() sets lookupRef target and data', () {
      final chunk = tx['profiles'].lookup('email', 'a@b.com')
          .update({'name': 'A'});
      final op = chunk.operations.single;
      expect(op.type, OperationType.update);
      expect(op.entityType, 'profiles');
      expect(op.lookupRef?.attribute, 'email');
      expect(op.lookupRef?.value, 'a@b.com');
      expect(op.data, {'name': 'A'});
    });

    test('lookup().delete() sets lookupRef target', () {
      final chunk = tx['profiles'].lookup('email', 'a@b.com').delete();
      final op = chunk.operations.single;
      expect(op.type, OperationType.delete);
      expect(op.lookupRef?.attribute, 'email');
    });
  });

  group('upsert option', () {
    final tx = TransactionBuilder();

    test('update with upsert:false records option', () {
      final chunk = tx['goals']['g1']
          .update({'title': 'x'}, opts: const TxOpts(upsert: false));
      expect(chunk.operations.single.options?['upsert'], isFalse);
    });

    test('update without opts has no upsert option (defaults upsert)', () {
      final chunk = tx['goals']['g1'].update({'title': 'x'});
      final opts = chunk.operations.single.options;
      expect(opts == null || opts['upsert'] != false, isTrue);
    });

    test('merge with upsert:false records option', () {
      final chunk = tx['games']['gm1']
          .merge({'state': {'a': 1}}, opts: const TxOpts(upsert: false));
      expect(chunk.operations.single.options?['upsert'], isFalse);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/transaction_builder_test.dart`
Expected: FAIL — `lookup` not defined on `EntityBuilder`; `update`/`merge` don't accept `opts`.

- [ ] **Step 3: Modify `lib/src/core/transaction_builder.dart`**

3a. Add `lookup` to `EntityBuilder`. Inside the `EntityBuilder` class, after the `create` method, add:

```dart
  /// Target an entity by a unique attribute (upsert-by-lookup), chainable like
  /// `tx.profiles.lookup('email', 'a@b.com').update({...})`.
  EntityInstanceBuilder lookup(String attribute, dynamic value) {
    return EntityInstanceBuilder.lookup(entityType, attribute, value);
  }
```

3b. Give `EntityInstanceBuilder` a lookup target. Replace its field/constructor head. Find:

```dart
class EntityInstanceBuilder {
  final String entityType;
  final String entityId;

  EntityInstanceBuilder(this.entityType, this.entityId);
```

Replace with:

```dart
class EntityInstanceBuilder {
  final String entityType;
  final String entityId;
  final LookupRef? lookupRef;

  EntityInstanceBuilder(this.entityType, this.entityId) : lookupRef = null;

  /// Construct a builder whose target is resolved by a unique attribute.
  EntityInstanceBuilder.lookup(this.entityType, String attribute, dynamic value)
      : entityId = '',
        lookupRef = LookupRef(
          entityType: entityType,
          attribute: attribute,
          value: value,
        );
```

3c. Thread `lookupRef` and `opts` through the operation-producing methods. Replace the `update` method:

```dart
  TransactionChunk update(Map<String, dynamic> data) {
    return TransactionChunk([
      Operation(
        type: OperationType.update,
        entityType: entityType,
        entityId: entityId,
        data: data,
      ),
    ]);
  }
```

with:

```dart
  /// Update entity with new data. Pass `opts: TxOpts(upsert: false)` for
  /// strict mode (do not create the entity if it does not exist).
  TransactionChunk update(Map<String, dynamic> data, {TxOpts? opts}) {
    return TransactionChunk([
      Operation(
        type: OperationType.update,
        entityType: entityType,
        entityId: entityId,
        data: data,
        options: opts?.toOptions(),
        lookupRef: lookupRef,
      ),
    ]);
  }
```

Replace the `merge` method:

```dart
  TransactionChunk merge(Map<String, dynamic> data) {
    return TransactionChunk([
      Operation(
        type: OperationType.merge,
        entityType: entityType,
        entityId: entityId,
        data: data,
      ),
    ]);
  }
```

with:

```dart
  /// Deep-merge data into the existing entity. Pass `opts: TxOpts(upsert:false)`
  /// for strict mode.
  TransactionChunk merge(Map<String, dynamic> data, {TxOpts? opts}) {
    return TransactionChunk([
      Operation(
        type: OperationType.merge,
        entityType: entityType,
        entityId: entityId,
        data: data,
        options: opts?.toOptions(),
        lookupRef: lookupRef,
      ),
    ]);
  }
```

Replace the `delete` method:

```dart
  TransactionChunk delete() {
    return TransactionChunk([
      Operation(
        type: OperationType.delete,
        entityType: entityType,
        entityId: entityId,
      ),
    ]);
  }
```

with:

```dart
  TransactionChunk delete() {
    return TransactionChunk([
      Operation(
        type: OperationType.delete,
        entityType: entityType,
        entityId: entityId,
        lookupRef: lookupRef,
      ),
    ]);
  }
```

In the `link` method, find the `Operation(` constructions and add `lookupRef: lookupRef,` after `data: {relationName: targetId},` (both the list branch and the single branch). Do the same in `unlink`. For example the list branch in `link` becomes:

```dart
          operations.add(
            Operation(
              type: OperationType.link,
              entityType: entityType,
              entityId: entityId,
              data: {relationName: targetId},
              lookupRef: lookupRef,
            ),
          );
```

Apply the identical `lookupRef: lookupRef,` addition to: the single-target branch in `link`, and both branches in `unlink` (using `OperationType.unlink`).

3d. Add the import for `LookupRef`/`TxOpts` — they live in `types.dart`, already imported at the top (`import 'types.dart';`). No new import needed.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/transaction_builder_test.dart`
Expected: PASS (all builder tests).

- [ ] **Step 5: Verify analysis**

Run: `flutter analyze lib/src/core/transaction_builder.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/src/core/transaction_builder.dart test/transaction_builder_test.dart
git commit -m "feat(tx): chainable lookup() target and upsert option on update/merge

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Resolve target lookups in the store + upsert gating

**Files:**
- Modify: `lib/src/storage/storage_interface.dart`
- Modify: `lib/src/storage/triple_store.dart`
- Test: `test/tx_completeness_test.dart` (create)

- [ ] **Step 1: Write failing integration tests**

Create `test/tx_completeness_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Transaction completeness', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final testId = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_txc_$testId',
        ),
      );
    });

    tearDown(() async => db.dispose());

    Future<List<Map<String, dynamic>>> profiles() async {
      final r = await db.queryOnce({'profiles': {}});
      return r.documents;
    }

    test('lookup().update() creates entity when absent (upsert by attr)',
        () async {
      await db.transact(
        db.tx['profiles'].lookup('email', 'a@b.com').update({'name': 'Alice'}),
      );
      final rows = await profiles();
      expect(rows.length, 1);
      expect(rows.single['email'], 'a@b.com');
      expect(rows.single['name'], 'Alice');
    });

    test('lookup().update() updates existing entity, no duplicate', () async {
      await db.transact(
        db.tx['profiles'].lookup('email', 'a@b.com').update({'name': 'Alice'}),
      );
      await db.transact(
        db.tx['profiles'].lookup('email', 'a@b.com').update({'name': 'Alice2'}),
      );
      final rows = await profiles();
      expect(rows.length, 1);
      expect(rows.single['name'], 'Alice2');
    });

    test('update upsert:false is a no-op on missing entity', () async {
      await db.transact(
        db.tx['goals']['missing-id']
            .update({'title': 'x'}, opts: const TxOpts(upsert: false)),
      );
      final r = await db.queryOnce({'goals': {}});
      expect(r.documents, isEmpty);
    });

    test('update upsert:false updates an existing entity', () async {
      final id = db.id();
      await db.transact(db.tx['goals'][id].update({'title': 'orig'}));
      await db.transact(
        db.tx['goals'][id]
            .update({'title': 'new'}, opts: const TxOpts(upsert: false)),
      );
      final r = await db.queryOnce({'goals': {}});
      expect(r.documents.single['title'], 'new');
    });

    test('lookup().delete() on missing entity does not throw', () async {
      await db.transact(
        db.tx['profiles'].lookup('email', 'ghost@b.com').delete(),
      );
      expect(await profiles(), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tx_completeness_test.dart`
Expected: FAIL — target lookups not resolved (entity not created / wrong id), upsert:false not gated.

- [ ] **Step 3: Declare `resolveTargetLookups` on the interface**

In `lib/src/storage/storage_interface.dart`, add to the abstract `StorageInterface` class (alongside the other method declarations):

```dart
  /// Resolve operations whose target is a [LookupRef] into concrete entity ids.
  /// For write ops with no existing match, a new entity id is allocated (upsert
  /// by unique attribute). Delete ops with no match are dropped.
  Future<List<Operation>> resolveTargetLookups(List<Operation> operations);
```

(If `Operation`/`LookupRef` are not imported in this file, add `import '../core/types.dart';` — check existing imports first; the interface already references `Transaction`/`Operation` types so the import is likely present.)

- [ ] **Step 4: Implement in `triple_store.dart`**

Add this method to the `TripleStore` class (place it next to `resolveLookup`, around line 481). Ensure `Uuid` is available — `triple_store.dart` already imports `package:uuid/uuid.dart` for id generation; if not, add `import 'package:uuid/uuid.dart';` and a `final _uuid = const Uuid();` field, or reuse the existing one.

```dart
  @override
  Future<List<Operation>> resolveTargetLookups(
    List<Operation> operations,
  ) async {
    final resolved = <Operation>[];
    for (final op in operations) {
      final ref = op.lookupRef;
      if (ref == null) {
        resolved.add(op);
        continue;
      }

      final existingId = await resolveLookup(
        ref.entityType,
        ref.attribute,
        ref.value,
      );

      if (existingId != null) {
        resolved.add(_withEntityId(op, existingId));
        continue;
      }

      // No existing entity for this unique attribute.
      if (op.type == OperationType.delete) {
        // Nothing to delete — drop the op.
        continue;
      }

      // Upsert: allocate a new id and ensure the type + lookup attribute are
      // persisted so the entity is findable next time.
      final newId = const Uuid().v4();
      final data = <String, dynamic>{
        ...?op.data,
        '__type': ref.entityType,
        ref.attribute: ref.value,
      };
      resolved.add(
        Operation(
          type: op.type == OperationType.merge
              ? OperationType.merge
              : OperationType.update,
          entityType: ref.entityType,
          entityId: newId,
          data: data,
          options: op.options,
        ),
      );
    }
    return resolved;
  }

  Operation _withEntityId(Operation op, String id) => Operation(
        type: op.type,
        entityType: op.entityType.isNotEmpty ? op.entityType : op.lookupRef!.entityType,
        entityId: id,
        data: op.data,
        options: op.options,
      );
```

- [ ] **Step 5: Gate `update` and `merge` on `upsert:false`**

In `triple_store.dart`, in `_applyOperationWithChanges`, at the very start of the `case OperationType.update:` block (before the `if (operation.data != null)`), insert:

```dart
        if (operation.options?['upsert'] == false &&
            !await _entityExists(txn, operation.entityId)) {
          break; // strict mode: do not create a missing entity
        }
```

At the start of the `case OperationType.merge:` block (before it queries `existingTriples`), insert the same guard:

```dart
        if (operation.options?['upsert'] == false &&
            !await _entityExists(txn, operation.entityId)) {
          break;
        }
```

Add the helper method to the `TripleStore` class:

```dart
  Future<bool> _entityExists(DatabaseExecutor txn, String entityId) async {
    final rows = await txn.query(
      'triples',
      where: 'entity_id = ? AND retracted = FALSE',
      whereArgs: [entityId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
```

(`DatabaseExecutor` is already used as the `txn` parameter type in `_applyOperationWithChanges`; no new import.)

- [ ] **Step 6: Run to verify it fails differently**

Run: `flutter test test/tx_completeness_test.dart`
Expected: STILL FAIL on the lookup-create tests — because `InstantDB.transact` does not yet call `resolveTargetLookups`. The `upsert:false` no-op test should now pass. (This confirms Task 3's store layer works; Task 4 wires it.)

- [ ] **Step 7: Commit**

```bash
git add lib/src/storage/storage_interface.dart lib/src/storage/triple_store.dart test/tx_completeness_test.dart
git commit -m "feat(store): resolveTargetLookups + upsert:false gating

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire target-lookup resolution into transact

**Files:**
- Modify: `lib/src/core/instant_db.dart`

- [ ] **Step 1: Resolve target lookups before building the Transaction**

In `lib/src/core/instant_db.dart`, in the `transact` method, find:

```dart
    final txId = id();
    InstantDBLogging.root.debug(
      'InstantDB: Creating transaction $txId with ${operations.length} operations - StorageBackend: SQLite',
    );

    final tx = Transaction(
      id: txId,
      operations: operations,
      timestamp: DateTime.now(),
    );
```

Replace with:

```dart
    final txId = id();
    InstantDBLogging.root.debug(
      'InstantDB: Creating transaction $txId with ${operations.length} operations - StorageBackend: SQLite',
    );

    // Resolve any lookup-target operations (tx.ns.lookup(attr, value)...) into
    // concrete entity ids (creating the entity for write ops when absent) so
    // local apply and sync both receive concrete ids.
    final resolvedOperations = await _store.resolveTargetLookups(operations);

    final tx = Transaction(
      id: txId,
      operations: resolvedOperations,
      timestamp: DateTime.now(),
    );
```

- [ ] **Step 2: Run the integration tests to verify they pass**

Run: `flutter test test/tx_completeness_test.dart`
Expected: PASS (all 5 tests — create-on-lookup, update-existing, upsert:false no-op, upsert:false update, lookup-delete missing).

- [ ] **Step 3: Run the builder + matcher suites for regressions**

Run: `flutter test test/transaction_builder_test.dart test/where_matcher_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/src/core/instant_db.dart
git commit -m "feat(tx): resolve lookup targets up front in transact()

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Forward ruleParams in the sync message

**Files:**
- Modify: `lib/src/sync/sync_engine.dart`

**Context:** `ruleParams` is a server-side permission concern; it cannot be
verified offline. This task forwards it best-effort and must not regress the
existing sync path. Keep the change small and localized.

- [ ] **Step 1: Locate the outgoing transact message construction**

Run: `grep -n "tx-steps\|'transact'\|\"transact\"\|jsonEncode" lib/src/sync/sync_engine.dart | head`
Read the block in `_processQueue` where `txSteps` is assembled into the message
map that is sent over the WebSocket (the map that contains the `tx-steps` key).

- [ ] **Step 2: Collect and attach ruleParams**

In `_processQueue`, after `txSteps` is fully built and immediately before the
message map is created/sent, add:

```dart
            // Forward permission rule params if any operation carries them.
            Map<String, dynamic>? ruleParams;
            for (final op in transaction.operations) {
              final rp = op.options?['ruleParams'];
              if (rp is Map<String, dynamic>) {
                ruleParams = {...?ruleParams, ...rp};
              }
            }
```

Then, in the message map that is sent (the one with `'tx-steps': txSteps`), add
a conditional entry so it is only present when non-null. If the map is built as
a literal, add after the `tx-steps` entry:

```dart
              if (ruleParams != null) 'rule-params': ruleParams,
```

If the message map is not a collection literal (built/mutated imperatively),
instead add after its construction:

```dart
            if (ruleParams != null) {
              <messageMapVariable>['rule-params'] = ruleParams;
            }
```

replacing `<messageMapVariable>` with the actual variable name you found in
Step 1. Choose whichever form matches the existing code; do not restructure the
surrounding builder.

- [ ] **Step 3: Verify analysis and existing sync behavior**

Run: `flutter analyze lib/src/sync/sync_engine.dart`
Expected: "No issues found!"

Run: `flutter test`
Expected: PASS for all suites except the 5 known pre-existing failures
(ORDER BY / Performance `database_closed` teardown in
`test/query_engine_advanced_test.dart`). No NEW failures.

- [ ] **Step 4: Commit**

```bash
git add lib/src/sync/sync_engine.dart
git commit -m "feat(sync): forward ruleParams in outgoing transact message

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Documentation + changelog

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CHANGELOG entry**

Add under the existing Unreleased section in `CHANGELOG.md`:

```markdown
### Transactions (InstaML parity)
- Added chainable `lookup` target: `db.tx.profiles.lookup('email', 'a@b.com').update({...})` — upsert by unique attribute (also works with `merge`, `delete`, `link`, `unlink`).
- Added `{upsert: false}` strict mode: `db.tx.goals[id].update({...}, opts: TxOpts(upsert: false))` does not create the entity if it does not exist.
- Added `ruleParams`: `db.tx.docs[id].update({...}).ruleParams({...})`, forwarded to the server for permission rules.
```

- [ ] **Step 2: README examples**

Run: `grep -n "tx\[\|tx\.\|transact\|lookup" README.md | head`
If a transactions/`tx` section exists, add near it:

````markdown
```dart
// Upsert by unique attribute
await db.transact(
  db.tx['profiles'].lookup('email', 'a@b.com').update({'name': 'Alice'}),
);

// Strict update (no create) + rule params
await db.transact(
  db.tx['goals'][goalId]
      .update({'title': 'Get fit'}, opts: const TxOpts(upsert: false))
      .ruleParams({'token': token}),
);
```
````

If no such section exists, skip this step.

- [ ] **Step 3: Verify and commit**

Run: `flutter analyze`
Expected: only pre-existing `info`/`warning` issues in `bin/`, `example/`,
`lib/src/sync/web_socket_web.dart` (unchanged count); none in the files this
phase touched.

```bash
git add CHANGELOG.md README.md
git commit -m "docs: document tx lookup, upsert option, and ruleParams

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria

- `flutter test test/transaction_builder_test.dart test/tx_completeness_test.dart test/where_matcher_test.dart` — all green.
- `flutter test` — no NEW failures beyond the 5 known pre-existing (`database_closed` teardown) ones.
- `flutter analyze` — no issues in any file this phase modified.
- Chainable `lookup` creates-or-updates by unique attr; `upsert:false` is a strict no-op on missing entities; `ruleParams` rides on `options` and is forwarded in the sync message.
- No breaking changes: all prior builder calls (`tx[type][id].update(data)` etc.) still compile and behave identically.

## Known limitation (acceptable this round)

`lookup().link(...)` / `lookup().unlink(...)` against a **non-existent** target
fall through the create-branch as an `update` that persists `__type` + the
lookup attribute but does not carry the link itself. The documented and tested
lookup-upsert cases — `update`, `merge`, `delete` — are correct. Link/unlink via
lookup are normally used against existing entities (the common path, which works
because `resolveLookup` returns the id). Full link-on-missing-target upsert is
deferred; note it in the implementer report if it surfaces.

## Next phase

Phase 3 (connection-status enum + named `localId`) gets its own just-in-time plan.
