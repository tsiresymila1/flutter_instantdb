import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

// ---------------------------------------------------------------------------
// Hand-written model + table classes mimicking what the generator will emit,
// to test the runtime seam between TypedQuery.include() and the nested-1
// engine without relying on code generation.
// ---------------------------------------------------------------------------

class _Todo {
  final String id;
  final String title;
  final int n;
  _Todo({required this.id, required this.title, required this.n});
}

class _TodoTable extends InstantModelTable<_TodoTable, _Todo> {
  _TodoTable() : super('todos');
  final n = const Col<int>('n');

  @override
  _Todo fromRow(Map<String, dynamic> m) =>
      _Todo(id: m['id'] as String, title: m['title'] as String, n: m['n'] as int);
}

class _Goal {
  final String id;
  final String title;
  final List<_Todo> todos;
  _Goal({required this.id, required this.title, required this.todos});
}

class _GoalTable extends InstantModelTable<_GoalTable, _Goal> {
  _GoalTable() : super('goals');

  TypedQuery<_TodoTable> get todos =>
      TypedQuery<_TodoTable>(_TodoTable(), relationAttr: 'todos');

  @override
  _Goal fromRow(Map<String, dynamic> m) => _Goal(
        id: m['id'] as String,
        title: m['title'] as String,
        todos: (m['todos'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(_TodoTable().fromRow)
                .toList() ??
            const <_Todo>[],
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Typed include integration (nested-2)', () {
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
              'test_tr_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      // Seed: one goal with two linked todos (n=1 and n=2).
      await db.transact(db.tx['goals']['g1'].update({'title': 'Fit'}));
      await db.transact(db.tx['todos']['t1'].update({'title': 'Run', 'n': 1}));
      await db.transact(db.tx['todos']['t2'].update({'title': 'Lift', 'n': 2}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t1', 't2']}));
    });

    tearDown(() async => db.dispose());

    test('typed include populates a typed to-many relation', () async {
      final q = _GoalTable().query().include((g) => g.todos);
      final r = await db.queryOnceTyped(q);
      final goal = r.documents.firstWhere((d) => d['id'] == 'g1');
      final todos = _GoalTable().fromRow(goal).todos;
      expect(todos.map((t) => t.title).toSet(), {'Run', 'Lift'});
    });

    test('typed nested where narrows the included set', () async {
      final q = _GoalTable()
          .query()
          .include((g) => g.todos.where((t) => t.n.gte(2)));
      final r = await db.queryOnceTyped(q);
      final todos = _GoalTable()
          .fromRow(r.documents.firstWhere((d) => d['id'] == 'g1'))
          .todos;
      expect(todos.map((t) => t.title), ['Lift']);
    });

    test(
        'fromRow on an un-included parent yields an empty relation, not a crash',
        () async {
      // Query WITHOUT include — the todos key will be a list of id strings.
      final r = await db.queryOnceTyped(_GoalTable().query());
      final todos = _GoalTable()
          .fromRow(r.documents.firstWhere((d) => d['id'] == 'g1'))
          .todos;
      expect(todos, isEmpty);
    });

    test('typed include applies nested cursor window', () async {
      // Seed a third todo (n=3) linked to g1.
      await db.transact(
          db.tx['todos']['t3'].update({'title': 'Swim', 'n': 3}));
      await db.transact(db.tx['goals']['g1'].link({'todos': ['t3']}));

      final q = _GoalTable()
          .query()
          .include((g) => g.todos.order((t) => t.n.asc()).first(1));
      final r = await db.queryOnceTyped(q);
      final todos = _GoalTable()
          .fromRow(r.documents.firstWhere((d) => d['id'] == 'g1'))
          .todos;
      expect(todos.map((t) => t.n).toList(), [1]);
    });
  });
}
