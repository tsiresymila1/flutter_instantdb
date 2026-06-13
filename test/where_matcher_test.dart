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
}
