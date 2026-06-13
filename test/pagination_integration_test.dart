import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Pagination + fields integration', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: 'test_pg_$id'),
      );
      // Seed 5 todos with a sortable index.
      for (var i = 0; i < 5; i++) {
        await db.transact(db.tx['todos']['t$i'].update({'n': i}));
      }
    });

    tearDown(() async => db.dispose());

    test('first + order returns a leading page with pageInfo', () async {
      final r = await db.queryOnce({
        'todos': {
          '\$': {
            'order': {'n': 'asc'},
            'first': 2,
          },
        },
      });
      final items = r.documents;
      expect(items.length, 2);
      expect(items.map((e) => e['n']), [0, 1]);
      expect(r.pageInfo?['todos']?['hasNextPage'], isTrue);
      expect(r.pageInfo?['todos']?['hasPreviousPage'], isFalse);
    });

    test('after cursor pages forward', () async {
      final first = await db.queryOnce({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2},
        },
      });
      final cursor = first.pageInfo?['todos']?['endCursor'] as String;

      final next = await db.queryOnce({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2, 'after': cursor},
        },
      });
      expect(next.documents.map((e) => e['n']), [2, 3]);
    });

    test('fields projection limits returned keys', () async {
      final r = await db.queryOnce({
        'todos': {
          '\$': {'fields': ['n']},
        },
      });
      for (final doc in r.documents) {
        expect(doc.keys.toSet().difference({'id', 'n'}), isEmpty);
      }
    });

    test('infiniteQuery accumulates pages via loadMore', () async {
      final inf = db.infiniteQuery({
        'todos': {
          '\$': {'order': {'n': 'asc'}, 'first': 2},
        },
      }, pageSize: 2, entityType: 'todos');

      // initial page (queryOnce has an internal ~100ms settle delay)
      await Future.delayed(const Duration(milliseconds: 150));
      expect(inf.items.value.length, 2);

      await inf.loadMore();
      await Future.delayed(const Duration(milliseconds: 150));
      expect(inf.items.value.length, 4);

      await inf.loadMore();
      await Future.delayed(const Duration(milliseconds: 150));
      expect(inf.items.value.length, 5);
      expect(inf.hasMore.value, isFalse);

      inf.dispose();
    });
  });
}
