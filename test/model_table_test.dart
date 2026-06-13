import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

// Hand-written model + table mimicking what the generator will emit, to test
// the runtime InstantModelTable base independently of code generation.
class Sample {
  final String id;
  final String title;
  final int n;
  Sample({required this.id, required this.title, required this.n});
}

class SampleTable extends InstantModelTable<SampleTable, Sample> {
  SampleTable() : super('samples');
  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final n = const Col<int>('n');

  @override
  Sample fromRow(Map<String, dynamic> m) => Sample(
        id: m['id'] as String,
        title: m['title'] as String,
        n: m['n'] as int,
      );
}

void main() {
  group('InstantModelTable', () {
    test('is usable as a 6a InstantTable (query compiles)', () {
      final q = SampleTable().query().where((t) => t.n.gte(1));
      expect(q.toQuery(), {
        'samples': {r'$': {'where': {'n': {r'$gte': 1}}}},
      });
    });

    test('fromRow maps a document to a typed object', () {
      final s = SampleTable().fromRow({'id': 'a', 'title': 'T', 'n': 3});
      expect(s.id, 'a');
      expect(s.title, 'T');
      expect(s.n, 3);
    });

    test('queryOnceTyped + fromRow yields typed objects', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_mt_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      for (var i = 0; i < 3; i++) {
        await db.transact(
          db.tx['samples']['s$i'].update({'title': 'T$i', 'n': i}),
        );
      }
      final table = SampleTable();
      final result =
          await db.queryOnceTyped(table.query().where((t) => t.n.gte(1)));
      final samples = result.documents.map(table.fromRow).toList();
      expect(samples.map((s) => s.n).toList()..sort(), [1, 2]);
      await db.dispose();
    });
  });
}
