import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/query/pagination.dart';

List<Map<String, dynamic>> rows(int n) =>
    List.generate(n, (i) => {'id': 'e$i', 'n': i});

void main() {
  group('paginate - first/after', () {
    test('first n takes the leading window', () {
      final r = paginate(rows(5), first: 2);
      expect(r.items.map((e) => e['id']), ['e0', 'e1']);
      expect(r.pageInfo['startCursor'], 'e0');
      expect(r.pageInfo['endCursor'], 'e1');
      expect(r.pageInfo['hasNextPage'], isTrue);
      expect(r.pageInfo['hasPreviousPage'], isFalse);
    });

    test('after cursor is exclusive by default', () {
      final r = paginate(rows(5), after: 'e1', first: 2);
      expect(r.items.map((e) => e['id']), ['e2', 'e3']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isTrue);
    });

    test('afterInclusive includes the cursor row', () {
      final r = paginate(rows(5), after: 'e1', afterInclusive: true, first: 2);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
    });

    test('reaching the end sets hasNextPage false', () {
      final r = paginate(rows(3), after: 'e0', first: 5);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
      expect(r.pageInfo['hasNextPage'], isFalse);
    });
  });

  group('paginate - last/before', () {
    test('last n takes the trailing window', () {
      final r = paginate(rows(5), last: 2);
      expect(r.items.map((e) => e['id']), ['e3', 'e4']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isFalse);
    });

    test('before cursor is exclusive by default', () {
      final r = paginate(rows(5), before: 'e3', last: 2);
      expect(r.items.map((e) => e['id']), ['e1', 'e2']);
    });

    test('beforeInclusive includes the cursor row', () {
      final r = paginate(rows(5), before: 'e3', beforeInclusive: true, last: 2);
      expect(r.items.map((e) => e['id']), ['e2', 'e3']);
    });
  });

  group('paginate - offset/limit (no cursor keys)', () {
    test('offset then limit, in the correct order', () {
      final r = paginate(rows(10), offset: 2, limit: 3);
      expect(r.items.map((e) => e['id']), ['e2', 'e3', 'e4']);
      expect(r.pageInfo['hasPreviousPage'], isTrue);
      expect(r.pageInfo['hasNextPage'], isTrue);
    });
  });

  group('paginate - fields projection', () {
    test('keeps id plus requested fields only', () {
      final r = paginate([
        {'id': 'a', 'title': 'T', 'status': 'open', 'secret': 1},
      ], fields: ['title', 'status']);
      expect(r.items.single.keys.toSet(), {'id', 'title', 'status'});
    });
  });

  group('paginate - empty', () {
    test('empty input yields null cursors and no pages', () {
      final r = paginate(<Map<String, dynamic>>[], first: 5);
      expect(r.items, isEmpty);
      expect(r.pageInfo['startCursor'], isNull);
      expect(r.pageInfo['endCursor'], isNull);
      expect(r.pageInfo['hasNextPage'], isFalse);
      expect(r.pageInfo['hasPreviousPage'], isFalse);
    });
  });
}
