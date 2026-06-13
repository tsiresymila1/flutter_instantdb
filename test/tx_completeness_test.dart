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
