import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/typed/typed_query.dart';

void main() {
  group('Col operators -> Filter.toMap', () {
    final title = Col<String>('title');
    final priority = Col<int>('priority');

    test('eq emits direct equality', () {
      expect(title.eq('Run').toMap(), {'title': 'Run'});
    });

    test('ne / isNull / inList', () {
      expect(title.ne('Run').toMap(), {'title': {r'$ne': 'Run'}});
      expect(title.isNull(true).toMap(), {'title': {r'$isNull': true}});
      expect(priority.inList([1, 2]).toMap(), {'priority': {r'$in': [1, 2]}});
    });

    test('comparable operators', () {
      expect(priority.gt(5).toMap(), {'priority': {r'$gt': 5}});
      expect(priority.gte(5).toMap(), {'priority': {r'$gte': 5}});
      expect(priority.lt(5).toMap(), {'priority': {r'$lt': 5}});
      expect(priority.lte(5).toMap(), {'priority': {r'$lte': 5}});
    });

    test('string like / ilike', () {
      expect(title.like('%x%').toMap(), {'title': {r'$like': '%x%'}});
      expect(title.ilike('%x%').toMap(), {'title': {r'$ilike': '%x%'}});
    });
  });

  group('Filter combinators', () {
    final title = Col<String>('title');
    final priority = Col<int>('priority');

    test('and via &', () {
      final f = priority.gte(8) & title.ilike('%x%');
      expect(f.toMap(), {
        'and': [
          {'priority': {r'$gte': 8}},
          {'title': {r'$ilike': '%x%'}},
        ],
      });
    });

    test('or via |', () {
      final f = title.eq('A') | title.eq('B');
      expect(f.toMap(), {
        'or': [
          {'title': 'A'},
          {'title': 'B'},
        ],
      });
    });
  });

  group('Order', () {
    test('asc / desc', () {
      expect(Col<int>('createdAt').asc().toMap(), {'createdAt': 'asc'});
      expect(Col<int>('createdAt').desc().toMap(), {'createdAt': 'desc'});
    });
  });

  group('TypedQuery.toQuery', () {
    test('empty query yields just the namespace with empty options', () {
      expect(Todos().query().toQuery(), {
        'todos': {r'$': <String, dynamic>{}},
      });
    });

    test('where + order + first + fields compile to the \$ clause', () {
      final q = Todos()
          .query()
          .where((t) => t.priority.gte(8) & t.title.ilike('%x%'))
          .order((t) => t.createdAt.desc())
          .first(20)
          .select((t) => [t.title, t.priority]);

      expect(q.toQuery(), {
        'todos': {
          r'$': {
            'where': {
              'and': [
                {'priority': {r'$gte': 8}},
                {'title': {r'$ilike': '%x%'}},
              ],
            },
            'order': {'createdAt': 'desc'},
            'first': 20,
            'fields': ['title', 'priority'],
          },
        },
      });
    });

    test('pagination + limit/offset options', () {
      final q = Todos()
          .query()
          .after('cursor1')
          .last(5)
          .before('cursor9')
          .afterInclusive(true)
          .beforeInclusive(true)
          .limit(3)
          .offset(2);
      expect(q.toQuery()['todos'][r'$'], {
        'after': 'cursor1',
        'last': 5,
        'before': 'cursor9',
        'afterInclusive': true,
        'beforeInclusive': true,
        'limit': 3,
        'offset': 2,
      });
    });

    test('builders are immutable: base query is not mutated', () {
      final base = Todos().query();
      final a = base.where((t) => t.priority.gte(1)).first(2);
      // base must remain empty; a must carry its options
      expect(base.toQuery(), {'todos': {r'$': <String, dynamic>{}}});
      expect(a.toQuery()['todos'][r'$']['first'], 2);
    });
  });

  group('Typed include (nested-2)', () {
    test('include serializes nested where/order/limit under the \$ options', () {
      final goals = _GoalsTable();
      final q = goals.query().include(
            (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
                .where((t) => t.n.gte(2))
                .order((t) => t.n.asc())
                .limit(1),
          );
      final m = q.toQuery();
      final opts = (m['goals'] as Map)[r'$'] as Map;
      final inc = opts['include'] as Map;
      expect(inc.keys, ['todos']);
      final todos = inc['todos'] as Map;
      expect(todos['where'], {'n': {r'$gte': 2}});
      expect(todos['order'], {'n': 'asc'});
      expect(todos['limit'], 1);
    });

    test('include nests recursively', () {
      final goals = _GoalsTable();
      final q = goals.query().include(
            (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
                .include((t) =>
                    TypedQuery<_TagsTable>(_TagsTable(), relationAttr: 'tags')),
          );
      final inc =
          (((q.toQuery()['goals'] as Map)[r'$'] as Map)['include']) as Map;
      expect(((inc['todos'] as Map)['include'] as Map).keys, ['tags']);
    });

    test('include does not mutate the source query', () {
      final goals = _GoalsTable();
      final base = goals.query();
      base.include((g) =>
          TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos'));
      expect((base.toQuery()['goals'] as Map)[r'$'], isNot(contains('include')));
    });

    test('include serializes nested cursor keys', () {
      final goals = _GoalsTable();
      final q = goals.query().include(
            (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
                .order((t) => t.n.asc())
                .first(2)
                .after('cursor-1')
                .afterInclusive(true),
          );
      final todos = ((((q.toQuery()['goals'] as Map)[r'$'] as Map)['include'])
          as Map)['todos'] as Map;
      expect(todos['first'], 2);
      expect(todos['after'], 'cursor-1');
      expect(todos['afterInclusive'], true);
      expect(todos['order'], {'n': 'asc'});
      expect(todos.containsKey('fields'), isFalse); // never serialized
    });

    test('include throws if the relation sub-query uses select()', () {
      final goals = _GoalsTable();
      expect(
        () => goals.query().include(
              (g) => TypedQuery<_TodosTable>(_TodosTable(), relationAttr: 'todos')
                  .select((t) => [t.n]),
            ),
        throwsArgumentError,
      );
    });
  });
}

/// Test table used by the TypedQuery tests above.
class Todos extends InstantTable<Todos> {
  Todos() : super('todos');
  final title = Col<String>('title');
  final priority = Col<int>('priority');
  final createdAt = Col<int>('createdAt');
}

class _GoalsTable extends InstantTable<_GoalsTable> {
  _GoalsTable() : super('goals');
}

class _TodosTable extends InstantTable<_TodosTable> {
  _TodosTable() : super('todos');
  final n = const Col<int>('n');
}

class _TagsTable extends InstantTable<_TagsTable> {
  _TagsTable() : super('tags');
}
