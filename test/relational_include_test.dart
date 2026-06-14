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

  group('Include via relation triples (change B)', () {
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
          persistenceDir: 'test_inc_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
    });

    tearDown(() async => db.dispose());

    Future<void> seed() async {
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(db.tx['todos']['t1'].update({'title': 'Run', 'n': 1}));
      await db.transact(db.tx['todos']['t2'].update({'title': 'Lift', 'n': 2}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));
    }

    test('to-many include populates full related entities', () async {
      await seed();
      final r = await db.queryOnce({'goals': {'include': {'todos': {}}}});
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      expect(todos.length, 2);
      expect(todos.map((t) => t['title']).toSet(), {'Run', 'Lift'});
    });

    test('nested where/order/limit filters the related set', () async {
      await seed();
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {
              'where': {'n': {r'$gte': 2}},
              'order': {'n': 'asc'},
              'limit': 1,
            },
          },
        },
      });
      final goal = r.documents.firstWhere((g) => g['id'] == 'g1');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      expect(todos.length, 1);
      expect(todos.single['title'], 'Lift');
    });

    test('to-one link resolves to a single-element related list', () async {
      await db.transact(db.tx['posts']['p1'].update({'title': 'Hello'}));
      await db.transact(db.tx['users']['u1'].update({'name': 'Ana'}));
      await db.transact(db.tx['posts']['p1'].link({'owner': 'u1'}));

      final r = await db.queryOnce({'posts': {'include': {'owner': {}}}});
      final post = r.documents.firstWhere((p) => p['id'] == 'p1');
      final owner = (post['owner'] as List).cast<Map<String, dynamic>>();
      expect(owner.single['name'], 'Ana');
    });

    test('deep nested include populates two levels', () async {
      await db.transact(db.tx['goals']['g9'].update({'title': 'G'}));
      await db.transact(db.tx['todos']['td9'].update({'title': 'T'}));
      await db.transact(db.tx['tags']['tg9'].update({'label': 'urgent'}));
      await db.transact(db.tx['todos']['td9'].link({'tags': ['tg9']}));
      await db.transact(db.tx['goals']['g9'].link({'todos': ['td9']}));

      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {'include': {'tags': {}}},
          },
        },
      });
      final goal = r.documents.firstWhere((g) => g['id'] == 'g9');
      final todos = (goal['todos'] as List).cast<Map<String, dynamic>>();
      final tags = (todos.single['tags'] as List).cast<Map<String, dynamic>>();
      expect(tags.single['label'], 'urgent');
    });
  });

  group('Include cursor pagination + fields (nested-3)', () {
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
          persistenceDir:
              'test_n3_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      // Seed: one goal linked to three ordered todos (n=1,2,3).
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(
          db.tx['todos']['t1'].update({'title': 'Run', 'n': 1}));
      await db.transact(
          db.tx['todos']['t2'].update({'title': 'Lift', 'n': 2}));
      await db.transact(
          db.tx['todos']['t3'].update({'title': 'Swim', 'n': 3}));
      await db.transact(
          db.tx['goals']['g1'].link({'todos': ['t1', 't2', 't3']}));
    });

    tearDown(() async => db.dispose());

    test('nested first windows the related set after order', () async {
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {'order': {'n': 'asc'}, 'first': 1},
          },
        },
      });
      final todos =
          (r.documents.firstWhere((g) => g['id'] == 'g1')['todos'] as List)
              .cast<Map<String, dynamic>>();
      expect(todos.length, 1);
      expect(todos.single['n'], 1);
    });

    test('nested after cursor advances the window', () async {
      final firstId = 't1'; // deterministic seed id
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {
              'order': {'n': 'asc'},
              'after': firstId,
              'first': 1,
            },
          },
        },
      });
      final todos =
          (r.documents.firstWhere((g) => g['id'] == 'g1')['todos'] as List)
              .cast<Map<String, dynamic>>();
      expect(todos.single['n'], 2);
    });

    test('nested fields projection drops non-whitelisted attrs (untyped)',
        () async {
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {'fields': ['title']},
          },
        },
      });
      final t =
          (r.documents.firstWhere((g) => g['id'] == 'g1')['todos'] as List)
              .cast<Map<String, dynamic>>()
              .first;
      expect(t.keys.toSet(), {'id', 'title'}); // 'n' dropped, id always kept
    });

    test('nested cursor does not double-apply limit', () async {
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {'order': {'n': 'asc'}, 'first': 2},
          },
        },
      });
      final todos =
          (r.documents.firstWhere((g) => g['id'] == 'g1')['todos'] as List)
              .cast<Map<String, dynamic>>();
      expect(todos.map((t) => t['n']).toList(), [1, 2]);
    });
  });

  group('Include per-relation pageInfo (nested-4)', () {
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
          persistenceDir:
              'test_n4_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      // Seed: one goal (g1) linked to three ordered todos (n=1,2,3).
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(
          db.tx['todos']['t1'].update({'title': 'Run', 'n': 1}));
      await db.transact(
          db.tx['todos']['t2'].update({'title': 'Lift', 'n': 2}));
      await db.transact(
          db.tx['todos']['t3'].update({'title': 'Swim', 'n': 3}));
      await db.transact(
          db.tx['goals']['g1'].link({'todos': ['t1', 't2', 't3']}));
    });

    tearDown(() async => db.dispose());

    test('paginated relation surfaces composite pageInfo', () async {
      final r = await db.queryOnce({
        'goals': {'include': {'todos': {'order': {'n': 'asc'}, 'first': 1}}},
      });
      final pi = r.pageInfo?['goals.todos'];
      expect(pi, isNotNull);
      expect(pi!['hasNextPage'], true);
      expect(pi['hasPreviousPage'], false);
      expect(pi['startCursor'], 't1');
      expect(pi['endCursor'], 't1');
    });

    test('second page via after cursor flips hasPreviousPage', () async {
      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {
              'order': {'n': 'asc'},
              'after': 't1',
              'first': 1,
            },
          },
        },
      });
      final todos =
          (r.documents.firstWhere((g) => g['id'] == 'g1')['todos'] as List)
              .cast<Map<String, dynamic>>();
      expect(todos.single['n'], 2);
      final pi = r.pageInfo!['goals.todos']!;
      expect(pi['hasPreviousPage'], true);
    });

    test('non-paginated include produces no composite pageInfo key', () async {
      final r = await db.queryOnce({'goals': {'include': {'todos': {}}}});
      expect(r.pageInfo?['goals.todos'], isNull);
    });

    test('deep nested paginated relation surfaces a dotted-path key', () async {
      // Seed g9 + td9 linked to g9; tg9/tg10/tg11 linked to td9.
      await db.transact(db.tx['goals']['g9'].update({'title': 'G'}));
      await db.transact(db.tx['todos']['td9'].update({'title': 'T'}));
      await db.transact(
          db.tx['tags']['tg9'].update({'label': 'alpha'}));
      await db.transact(
          db.tx['tags']['tg10'].update({'label': 'beta'}));
      await db.transact(
          db.tx['tags']['tg11'].update({'label': 'gamma'}));
      await db.transact(
          db.tx['todos']['td9'].link({'tags': ['tg9', 'tg10', 'tg11']}));
      await db.transact(db.tx['goals']['g9'].link({'todos': ['td9']}));

      final r = await db.queryOnce({
        'goals': {
          'include': {
            'todos': {
              'include': {
                'tags': {'first': 1, 'order': {'label': 'asc'}},
              },
            },
          },
        },
      });
      expect(r.pageInfo?['goals.todos.tags'], isNotNull);
      expect(r.pageInfo!['goals.todos.tags']!['hasNextPage'], true);
    });
  });
}
