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

    test('getAll without include yields empty gadgets list', () async {
      final widgets = await Widget2Table().query().getAll(db);
      // gadgets is not included → fromRow guard yields [].
      expect(widgets.every((w) => w.gadgets.isEmpty), isTrue);
    });

    test('getAll with include populates typed nested relation', () async {
      await db.transact(db.tx['gadgets']['g1'].update({'label': 'A'}));
      await db.transact(db.tx['widgets']['w0'].link({'gadgets': ['g1']}));
      final widgets = await Widget2Table()
          .query()
          .include((w) => w.gadgets)
          .getAll(db);
      final w0 = widgets.firstWhere((w) => w.id == 'w0');
      expect(w0.gadgets.map((g) => g.label), ['A']);
    });

    test('createModel round-trips a whole model', () async {
      await db.transact(
        db.txFor(Widget2Table()).createModel(
              const Widget2(id: 'wm', name: 'M', weight: 7, gadgets: []),
            ),
      );
      final got =
          await Widget2Table().query().where((t) => t.id.eq('wm')).getAll(db);
      expect(got.single.name, 'M');
      expect(got.single.weight, 7);
    });

    test('updateModel round-trips a changed field', () async {
      await db.transact(
        db.txFor(Widget2Table()).createModel(
              const Widget2(id: 'wu', name: 'Before', weight: 1, gadgets: []),
            ),
      );
      await db.transact(
        db.txFor(Widget2Table()).updateModel(
              'wu',
              const Widget2(id: 'wu', name: 'After', weight: 2, gadgets: []),
            ),
      );
      final got =
          await Widget2Table().query().where((t) => t.id.eq('wu')).getAll(db);
      expect(got.single.name, 'After');
      expect(got.single.weight, 2);
    });

    test('linkRel links via the generated RelationRef', () async {
      await db.transact(db.tx['gadgets']['g1'].update({'label': 'A'}));
      await db.transact(
        db.txFor(Widget2Table()).createModel(
              const Widget2(id: 'wl', name: 'L', weight: 1, gadgets: []),
            ),
      );
      await db.transact(
        db.txFor(Widget2Table()).linkRel('wl', Widget2Table.gadgetsRel, ['g1']),
      );
      final w = (await Widget2Table()
              .query()
              .where((t) => t.id.eq('wl'))
              .include((x) => x.gadgets)
              .getAll(db))
          .single;
      expect(w.gadgets.map((g) => g.label), ['A']);
    });
  });
}
