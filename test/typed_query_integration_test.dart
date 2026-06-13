import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final n = Col<int>('n');
}

void main() {
  group('Typed query through db', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: 'test_typed_$id'),
      );
      for (var i = 0; i < 5; i++) {
        await db.transact(
          db.tx['todos']['t$i'].update({'title': 'todo$i', 'n': i}),
        );
      }
    });

    tearDown(() async => db.dispose());

    test('queryOnceTyped filters + paginates like the hand-written map', () async {
      final typed = await db.queryOnceTyped(
        Todos()
            .query()
            .where((t) => t.n.gte(1))
            .order((t) => t.n.asc())
            .first(2),
      );
      expect(typed.documents.map((e) => e['n']), [1, 2]);

      // Parity with the equivalent hand-written map.
      final manual = await db.queryOnce({
        'todos': {
          r'$': {
            'where': {'n': {r'$gte': 1}},
            'order': {'n': 'asc'},
            'first': 2,
          },
        },
      });
      expect(
        typed.documents.map((e) => e['n']).toList(),
        manual.documents.map((e) => e['n']).toList(),
      );
    });

    test('queryTyped returns a reactive signal', () async {
      final sig = db.queryTyped(Todos().query().where((t) => t.title.eq('todo3')));
      // Allow the async query to settle.
      await Future.delayed(const Duration(milliseconds: 150));
      expect(sig.value.documents.single['title'], 'todo3');
    });
  });
}
