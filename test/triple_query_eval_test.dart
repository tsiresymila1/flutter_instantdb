import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/storage/triple_query_eval.dart';

void main() {
  group('matchesWhere - simple equality and logical operators', () {
    final entity = {'id': '1', 'name': 'Alice', 'age': 30, 'active': true};

    test('simple equality matches', () {
      expect(matchesWhere(entity, {'name': 'Alice'}), isTrue);
      expect(matchesWhere(entity, {'name': 'Bob'}), isFalse);
    });

    test('multiple fields must all match (implicit AND)', () {
      expect(matchesWhere(entity, {'name': 'Alice', 'age': 30}), isTrue);
      expect(matchesWhere(entity, {'name': 'Alice', 'age': 31}), isFalse);
    });

    test('missing field fails', () {
      expect(matchesWhere(entity, {'missing': 'x'}), isFalse);
    });

    test('\$or matches when any condition matches', () {
      expect(
        matchesWhere(entity, {
          '\$or': [
            {'name': 'Bob'},
            {'name': 'Alice'},
          ],
        }),
        isTrue,
      );
      expect(
        matchesWhere(entity, {
          '\$or': [
            {'name': 'Bob'},
            {'name': 'Carol'},
          ],
        }),
        isFalse,
      );
    });

    test('\$and requires all conditions', () {
      expect(
        matchesWhere(entity, {
          '\$and': [
            {'name': 'Alice'},
            {'age': 30},
          ],
        }),
        isTrue,
      );
      expect(
        matchesWhere(entity, {
          '\$and': [
            {'name': 'Alice'},
            {'age': 99},
          ],
        }),
        isFalse,
      );
    });

    test('\$not inverts the inner condition', () {
      expect(
        matchesWhere(entity, {
          '\$not': {'name': 'Bob'},
        }),
        isTrue,
      );
      expect(
        matchesWhere(entity, {
          '\$not': {'name': 'Alice'},
        }),
        isFalse,
      );
    });
  });

  group('matchesOperator - comparison operators', () {
    test('\$gt / \$gte', () {
      expect(matchesOperator(10, {'\$gt': 5}), isTrue);
      expect(matchesOperator(5, {'\$gt': 5}), isFalse);
      expect(matchesOperator(5, {'\$gte': 5}), isTrue);
      expect(matchesOperator(4, {'\$gte': 5}), isFalse);
    });

    test('\$lt / \$lte', () {
      expect(matchesOperator(3, {'\$lt': 5}), isTrue);
      expect(matchesOperator(5, {'\$lt': 5}), isFalse);
      expect(matchesOperator(5, {'\$lte': 5}), isTrue);
      expect(matchesOperator(6, {'\$lte': 5}), isFalse);
    });

    test('\$ne', () {
      expect(matchesOperator(5, {'\$ne': 6}), isTrue);
      expect(matchesOperator(5, {'\$ne': 5}), isFalse);
    });

    test('\$in / \$nin', () {
      expect(matchesOperator('b', {'\$in': ['a', 'b', 'c']}), isTrue);
      expect(matchesOperator('z', {'\$in': ['a', 'b', 'c']}), isFalse);
      expect(matchesOperator('z', {'\$nin': ['a', 'b', 'c']}), isTrue);
      expect(matchesOperator('a', {'\$nin': ['a', 'b', 'c']}), isFalse);
    });

    test('\$like is case sensitive, \$ilike is not', () {
      expect(matchesOperator('Hello World', {'\$like': 'Hello%'}), isTrue);
      expect(matchesOperator('hello world', {'\$like': 'Hello%'}), isFalse);
      expect(matchesOperator('hello world', {'\$ilike': 'HELLO%'}), isTrue);
    });

    test('\$exists / \$isNull', () {
      expect(matchesOperator('x', {'\$exists': true}), isTrue);
      expect(matchesOperator(null, {'\$exists': true}), isFalse);
      expect(matchesOperator(null, {'\$isNull': true}), isTrue);
      expect(matchesOperator('x', {'\$isNull': true}), isFalse);
    });

    test('\$contains and \$size on lists and strings', () {
      expect(matchesOperator([1, 2, 3], {'\$contains': 2}), isTrue);
      expect(matchesOperator([1, 2, 3], {'\$contains': 9}), isFalse);
      expect(matchesOperator('abcdef', {'\$contains': 'cd'}), isTrue);
      expect(matchesOperator([1, 2, 3], {'\$size': 3}), isTrue);
      expect(matchesOperator('abc', {'\$size': 3}), isTrue);
    });
  });

  group('compareEntities / compareSingleField ordering', () {
    final a = {'name': 'Alice', 'age': 30};
    final b = {'name': 'Bob', 'age': 25};

    test('ascending string order', () {
      expect(compareEntities(a, b, 'name asc'), lessThan(0));
      expect(compareEntities(b, a, 'name asc'), greaterThan(0));
    });

    test('descending order flips sign', () {
      expect(compareEntities(a, b, 'name desc'), greaterThan(0));
    });

    test('numeric order', () {
      expect(compareEntities(a, b, 'age asc'), greaterThan(0));
      expect(compareEntities(a, b, 'age desc'), lessThan(0));
    });

    test('multi-field list ordering falls through to second field', () {
      final x = {'group': 'g', 'age': 30};
      final y = {'group': 'g', 'age': 25};
      final order = [
        {'group': 'asc'},
        {'age': 'asc'},
      ];
      expect(compareEntities(x, y, order), greaterThan(0));
    });

    test('null handling in compareSingleField', () {
      final withNull = {'age': null};
      final withVal = {'age': 5};
      expect(compareSingleField(withNull, withVal, 'age', 'asc'), -1);
      expect(compareSingleField(withVal, withNull, 'age', 'asc'), 1);
      expect(compareSingleField(withNull, withNull, 'age', 'asc'), 0);
    });
  });

  group('calculateAggregates', () {
    final entities = [
      {'cat': 'a', 'val': 10},
      {'cat': 'a', 'val': 20},
      {'cat': 'b', 'val': 5},
    ];

    test('count', () {
      expect(calculateAggregates(entities, {'count': '*'})['count'], 3);
    });

    test('sum / avg / min / max', () {
      expect(calculateAggregates(entities, {'sum': 'val'})['sum'], 35);
      expect(calculateAggregates(entities, {'avg': 'val'})['avg'], 35 / 3);
      expect(calculateAggregates(entities, {'min': 'val'})['min'], 5);
      expect(calculateAggregates(entities, {'max': 'val'})['max'], 20);
    });

    test('sum of empty is 0', () {
      expect(calculateAggregates(<Map<String, dynamic>>[], {'sum': 'val'})['sum'], 0);
    });
  });

  group('processAggregations with groupBy', () {
    final entities = [
      {'cat': 'a', 'val': 10},
      {'cat': 'a', 'val': 20},
      {'cat': 'b', 'val': 5},
    ];

    test('groups and aggregates per group', () {
      final result = processAggregations(entities, {'sum': 'val'}, ['cat']);
      expect(result.length, 2);
      final byCat = {for (final r in result) r['cat']: r['sum']};
      expect(byCat['a'], 30);
      expect(byCat['b'], 5);
    });

    test('no groupBy returns single aggregate row', () {
      final result = processAggregations(entities, {'count': '*'}, null);
      expect(result.length, 1);
      expect(result.first['count'], 3);
    });
  });

  group('parseValue', () {
    test('parses int, double, bool, string, empty', () {
      expect(parseValue('42'), 42);
      expect(parseValue('3.14'), 3.14);
      expect(parseValue('true'), true);
      expect(parseValue('false'), false);
      expect(parseValue('hello'), 'hello');
      expect(parseValue(''), isNull);
    });
  });

  group('deepMerge', () {
    test('merges nested maps recursively', () {
      final target = {
        'a': 1,
        'nested': {'x': 1, 'y': 2},
      };
      final source = {
        'b': 2,
        'nested': {'y': 20, 'z': 30},
      };
      final result = deepMerge(target, source);
      expect(result['a'], 1);
      expect(result['b'], 2);
      expect(result['nested'], {'x': 1, 'y': 20, 'z': 30});
    });

    test('source overwrites non-map values', () {
      expect(deepMerge({'a': 1}, {'a': 2}), {'a': 2});
    });

    test('does not mutate target', () {
      final target = {'a': 1};
      deepMerge(target, {'b': 2});
      expect(target, {'a': 1});
    });
  });
}
