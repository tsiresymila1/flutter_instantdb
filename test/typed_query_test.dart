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
}
