import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Relational reconstruction (change A)', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_rel_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
    });

    tearDown(() async => db.dispose());

    test('a to-many link surfaces as a list of target ids', () async {
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(db.tx['todos']['t1'].update({'title': 'Run'}));
      await db.transact(db.tx['todos']['t2'].update({'title': 'Lift'}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));

      final r = await db.queryOnce({'goals': {}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = goal['todos'];
      expect(todos, isA<List>());
      expect((todos as List).map((e) => e.toString()).toSet(), {'t1', 't2'});
    });

    test('a scalar attribute stays scalar', () async {
      await db.transact(db.tx['goals']['g2'].update({'title': 'Solo'}));
      final r = await db.queryOnce({'goals': {}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g2');
      expect(goal['title'], 'Solo'); // not a list
    });
  });
}
