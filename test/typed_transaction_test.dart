import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

/// Hand-written table for typed-transaction tests (mirrors model_table_test).
class _Todos extends InstantTable<_Todos> {
  _Todos() : super('todos');
  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final priority = const Col<int>('priority');
  final email = const Col<String>('email');
}

class _Goals extends InstantTable<_Goals> {
  _Goals() : super('goals');
}

void main() {
  final t = _Todos();

  group('TypedTx (unit, no DB)', () {
    test('typed create builds an add op with typed fields', () {
      final w = TypedTx(t).create(id: 't1')
        ..set(t.title, 'Run')
        ..set(t.priority, 1);
      final ops = w.toTransactionChunk().operations;
      expect(ops.single.type, OperationType.add);
      expect(ops.single.entityId, 't1');
      expect(ops.single.data, containsPair('title', 'Run'));
      expect(ops.single.data, containsPair('priority', 1));
      expect(ops.single.data, containsPair('__type', 'todos'));
    });

    test('typed create without id generates one', () {
      final w = TypedTx(t).create()..set(t.title, 'X');
      final op = w.toTransactionChunk().operations.single;
      expect(op.type, OperationType.add);
      expect(op.entityId, isNotEmpty);
      expect(op.data, containsPair('title', 'X'));
    });

    test('typed update builds an update op', () {
      final w = TypedTx(t).update('t1')..set(t.priority, 2);
      final op = w.toTransactionChunk().operations.single;
      expect(op.type, OperationType.update);
      expect(op.entityId, 't1');
      expect(op.data, {'priority': 2});
    });

    test('typed merge builds a merge op', () {
      final w = TypedTx(t).merge('t1')..set(t.priority, 5);
      final op = w.toTransactionChunk().operations.single;
      expect(op.type, OperationType.merge);
      expect(op.entityId, 't1');
      expect(op.data, {'priority': 5});
    });

    test('typed delete builds a delete op', () {
      final chunk = TypedTx(t).delete('t1');
      final op = chunk.toTransactionChunk().operations.single;
      expect(op.type, OperationType.delete);
      expect(op.entityId, 't1');
    });

    test('typed link / unlink map to the right op types', () {
      final linkOp =
          TypedTx(t).link('t1', 'tags', 'g1').toTransactionChunk().operations.single;
      expect(linkOp.type, OperationType.link);
      expect(linkOp.entityId, 't1');
      expect(linkOp.data, {'tags': 'g1'});

      final unlinkOp = TypedTx(t)
          .unlink('t1', 'tags', 'g1')
          .toTransactionChunk()
          .operations
          .single;
      expect(unlinkOp.type, OperationType.unlink);
      expect(unlinkOp.entityId, 't1');
      expect(unlinkOp.data, {'tags': 'g1'});
    });

    test('typed lookup carries a lookupRef', () {
      final w = TypedTx(t).lookup(t.email, 'a@b.com')..set(t.title, 'X');
      final op = w.toTransactionChunk().operations.single;
      expect(op.type, OperationType.update);
      expect(op.lookupRef?.attribute, 'email');
      expect(op.lookupRef?.value, 'a@b.com');
      expect(op.data, {'title': 'X'});
    });

    test('typed lookup(merge: true) builds a merge op with a lookupRef', () {
      final w = TypedTx(t).lookup(t.email, 'a@b.com', merge: true)
        ..set(t.title, 'X');
      final op = w.toTransactionChunk().operations.single;
      expect(op.type, OperationType.merge);
      expect(op.lookupRef?.attribute, 'email');
    });

    test('set() after toTransactionChunk does not mutate the built op', () {
      final w = TypedTx(t).update('t1')..set(t.priority, 1);
      final op = w.toTransactionChunk().operations.single;
      w.set(t.priority, 2); // must not leak into the already-built op
      expect(op.data, {'priority': 1});
    });

    test('opts carries upsert:false through to update', () {
      final w = TypedTx(t).update('t1')
        ..set(t.priority, 9)
        ..opts(const TxOpts(upsert: false));
      final op = w.toTransactionChunk().operations.single;
      expect(op.options?['upsert'], isFalse);
    });

    // Compile-time safety is inherent: `set(t.priority, 'x')` would not compile
    // because `set<T>(Col<T>, T)` binds the value type to the column's T.

    test('createFromMap builds an add op with the whole map', () {
      final chunk =
          TypedTx(t).createFromMap({'id': 't1', 'title': 'Run', 'priority': 1});
      final op = chunk.operations.single;
      expect(op.type, OperationType.add);
      expect(op.entityId, 't1');
      expect(op.data, containsPair('title', 'Run'));
      expect(op.data, containsPair('__type', 'todos'));
    });

    test('updateFromMap builds an update op and copies the map', () {
      final src = {'priority': 1};
      final chunk = TypedTx(t).updateFromMap('t1', src);
      src['priority'] = 99; // must not leak into the built op
      expect(chunk.operations.single.data, {'priority': 1});
    });

    test('mergeFromMap builds a merge op and copies the map', () {
      final src = {'priority': 1};
      final chunk = TypedTx(t).mergeFromMap('t1', src);
      src['priority'] = 99; // must not leak
      final op = chunk.operations.single;
      expect(op.type, OperationType.merge);
      expect(op.entityId, 't1');
      expect(op.data, {'priority': 1});
    });

    test('linkRel / unlinkRel build link/unlink ops via the RelationRef attr',
        () {
      const rel = RelationRef<_Todos>('todos');
      final linkOps = TypedTx(_Goals()).linkRel('g1', rel, ['t1', 't2']).operations;
      expect(linkOps.length, 2);
      expect(linkOps.every((o) => o.type == OperationType.link), isTrue);
      final unlinkOps = TypedTx(_Goals()).unlinkRel('g1', rel, 't1').operations;
      expect(unlinkOps.single.type, OperationType.unlink);
      expect(unlinkOps.single.data, {'todos': 't1'});
    });
  });

  group('TypedTx (integration, sqflite-ffi)', () {
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
          persistenceDir: 'test_typed_tx_$testId',
        ),
      );
    });

    tearDown(() async => db.dispose());

    test('typed create round-trips through the DB', () async {
      await db.transact(db.txFor(t).create(id: 't1')
        ..set(t.title, 'Run')
        ..set(t.priority, 3));
      final r = await db.queryOnce({'todos': {}});
      final todo = r.documents.firstWhere((d) => d['id'] == 't1');
      expect(todo['title'], 'Run');
      expect(todo['priority'], 3);
    });

    test('typed update changes a field', () async {
      await db.transact(db.txFor(t).create(id: 't1')..set(t.priority, 1));
      await db.transact(db.txFor(t).update('t1')..set(t.priority, 2));
      final r = await db.queryOnce({'todos': {}});
      final todo = r.documents.firstWhere((d) => d['id'] == 't1');
      expect(todo['priority'], 2);
    });

    test('typed lookup upserts by unique attr', () async {
      await db.transact(
          db.txFor(t).lookup(t.email, 'a@b.com')..set(t.title, 'First'));
      await db.transact(
          db.txFor(t).lookup(t.email, 'a@b.com')..set(t.title, 'Second'));
      final r = await db.queryOnce({'todos': {}});
      final matches =
          r.documents.where((d) => d['email'] == 'a@b.com').toList();
      expect(matches.length, 1); // upsert, not duplicate
      expect(matches.single['title'], 'Second');
    });

    test('typed delete removes the entity', () async {
      await db.transact(db.txFor(t).create(id: 't1')..set(t.title, 'Gone'));
      await db.transact(db.txFor(t).delete('t1'));
      final r = await db.queryOnce({'todos': {}});
      expect(r.documents.where((d) => d['id'] == 't1'), isEmpty);
    });
  });
}
