import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

import 'fixtures/sample.dart';

void main() {
  group('Generated table end-to-end', () {
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
          persistenceDir: 'test_cg_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      for (var i = 0; i < 4; i++) {
        await db.transact(
          db.tx['widgets']['w$i'].update({'name': 'w$i', 'weight': i}),
        );
      }
    });

    tearDown(() async => db.dispose());

    test('getAll returns typed List<Widget2> filtered + ordered', () async {
      final widgets = await Widget2Table()
          .query()
          .where((t) => t.weight.gte(2))
          .order((t) => t.weight.asc())
          .getAll(db);

      expect(widgets, isA<List<Widget2>>());
      expect(widgets.map((w) => w.weight), [2, 3]);
      expect(widgets.first.name, 'w2');
    });
  });
}
