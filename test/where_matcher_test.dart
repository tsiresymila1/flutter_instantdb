import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/query/where_matcher.dart';

void main() {
  group('evaluateWhere - direct equality', () {
    test('matches direct field equality', () {
      expect(evaluateWhere({'title': 'Run'}, {'title': 'Run'}), isTrue);
      expect(evaluateWhere({'title': 'Run'}, {'title': 'Walk'}), isFalse);
    });

    test('empty where matches everything', () {
      expect(evaluateWhere({'a': 1}, {}), isTrue);
    });
  });

  group('evaluateWhere - comparison operators', () {
    test(r'$eq / $ne', () {
      expect(evaluateWhere({'n': 5}, {'n': {r'$eq': 5}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$ne': 5}}), isFalse);
      expect(evaluateWhere({'n': 5}, {'n': {r'$ne': 6}}), isTrue);
    });

    test(r'$gt / $gte / $lt / $lte', () {
      expect(evaluateWhere({'n': 5}, {'n': {r'$gt': 4}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$gt': 5}}), isFalse);
      expect(evaluateWhere({'n': 5}, {'n': {r'$gte': 5}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$lt': 6}}), isTrue);
      expect(evaluateWhere({'n': 5}, {'n': {r'$lte': 5}}), isTrue);
    });

    test(r'$in / $nin', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$in': ['a', 'b']}}), isTrue);
      expect(evaluateWhere({'t': 'c'}, {'t': {r'$in': ['a', 'b']}}), isFalse);
      expect(evaluateWhere({'t': 'c'}, {'t': {r'$nin': ['a', 'b']}}), isTrue);
    });

    test(r'$exists / $isNull', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$exists': true}}), isTrue);
      expect(evaluateWhere({}, {'t': {r'$exists': false}}), isTrue);
      expect(evaluateWhere({'t': null}, {'t': {r'$isNull': true}}), isTrue);
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$isNull': false}}), isTrue);
    });

    test('non-comparable types do not throw, return false', () {
      expect(evaluateWhere({'n': 'abc'}, {'n': {r'$gt': 5}}), isFalse);
    });
  });

  group('evaluateWhere - string match operators', () {
    test(r'$like is case-sensitive, % = any run', () {
      expect(evaluateWhere({'t': 'You got promoted!'},
          {'t': {r'$like': '%promoted!'}}), isTrue);
      expect(evaluateWhere({'t': 'Code a bunch'},
          {'t': {r'$like': '%promoted!'}}), isFalse);
      expect(evaluateWhere({'t': 'Hello'},
          {'t': {r'$like': 'hello'}}), isFalse); // case-sensitive
    });

    test(r'$like with _ matches single char', () {
      expect(evaluateWhere({'t': 'cat'}, {'t': {r'$like': 'c_t'}}), isTrue);
      expect(evaluateWhere({'t': 'cart'}, {'t': {r'$like': 'c_t'}}), isFalse);
    });

    test(r'$ilike is case-insensitive', () {
      expect(evaluateWhere({'t': 'Hello'},
          {'t': {r'$ilike': '%ELLO'}}), isTrue);
    });

    test(r'$like on null field returns false', () {
      expect(evaluateWhere({'t': null}, {'t': {r'$like': '%x'}}), isFalse);
      expect(evaluateWhere({}, {'t': {r'$like': '%x'}}), isFalse);
    });

    test(r'$not is alias of $ne', () {
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$not': 'a'}}), isFalse);
      expect(evaluateWhere({'t': 'a'}, {'t': {r'$not': 'b'}}), isTrue);
    });
  });

  group('evaluateWhere - logical combinators', () {
    test('and requires all sub-clauses', () {
      final w = {'and': [{'a': 1}, {'b': 2}]};
      expect(evaluateWhere({'a': 1, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'a': 1, 'b': 9}, w), isFalse);
    });

    test('or requires at least one sub-clause', () {
      final w = {'or': [{'a': 1}, {'b': 2}]};
      expect(evaluateWhere({'a': 1, 'b': 9}, w), isTrue);
      expect(evaluateWhere({'a': 9, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'a': 9, 'b': 9}, w), isFalse);
    });

    test('logical keys AND with sibling field keys', () {
      final w = {'status': 'open', 'or': [{'p': 1}, {'p': 2}]};
      expect(evaluateWhere({'status': 'open', 'p': 1}, w), isTrue);
      expect(evaluateWhere({'status': 'closed', 'p': 1}, w), isFalse);
    });

    test('nested and/or', () {
      final w = {'or': [{'and': [{'a': 1}, {'b': 2}]}, {'c': 3}]};
      expect(evaluateWhere({'a': 1, 'b': 2}, w), isTrue);
      expect(evaluateWhere({'c': 3}, w), isTrue);
      expect(evaluateWhere({'a': 1, 'b': 9, 'c': 9}, w), isFalse);
    });
  });

  group('evaluateWhere - dot-notation nested fields', () {
    test('matches nested map value', () {
      final doc = {'meta': {'priority': 'high'}};
      expect(evaluateWhere(doc, {'meta.priority': 'high'}), isTrue);
      expect(evaluateWhere(doc, {'meta.priority': 'low'}), isFalse);
    });

    test('matches if any element in a nested list satisfies', () {
      final doc = {'todos': [{'title': 'Run'}, {'title': 'Code'}]};
      expect(evaluateWhere(doc, {'todos.title': 'Code'}), isTrue);
      expect(evaluateWhere(doc, {'todos.title': 'Swim'}), isFalse);
    });

    test('missing nested path does not throw', () {
      expect(evaluateWhere({'a': 1}, {'x.y.z': 'v'}), isFalse);
      expect(evaluateWhere({'a': 1}, {'x.y': {r'$isNull': true}}), isTrue);
    });
  });
}
