import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/sync/datalog_convert.dart';

void main() {
  // Sample attribute cache: namespace -> { attrName -> attrId }
  final attributeCache = {
    'todos': {
      'text': 'attr-text',
      'completed': 'attr-completed',
      '__type': 'attr-type',
    },
  };

  group('extractJoinRows', () {
    test('extracts direct join-rows structure', () {
      final candidate = {
        'join-rows': [
          ['e1', 'attr-text', 'Buy milk'],
          ['e1', 'attr-completed', false],
        ],
      };
      final rows = extractJoinRows(candidate);
      expect(rows.length, 2);
      expect(rows[0][2], 'Buy milk');
    });

    test('unwraps nested join-rows structure', () {
      final candidate = {
        'join-rows': [
          [
            ['e1', 'attr-text', 'Buy milk'],
            ['e2', 'attr-text', 'Walk dog'],
          ],
        ],
      };
      final rows = extractJoinRows(candidate);
      expect(rows.length, 2);
      expect(rows[1][0], 'e2');
    });

    test('supports joinRows and rows aliases', () {
      expect(
        extractJoinRows({
          'joinRows': [
            ['e1', 'attr-text', 'x'],
          ],
        }).length,
        1,
      );
      expect(
        extractJoinRows({
          'rows': [
            ['e1', 'attr-text', 'x'],
          ],
        }).length,
        1,
      );
    });

    test('returns empty for non-map or missing rows', () {
      expect(extractJoinRows('not a map'), isEmpty);
      expect(extractJoinRows({'other': 1}), isEmpty);
    });
  });

  group('parseJoinRowsToEntities', () {
    test('reconstructs entities keyed by id with resolved attr names', () {
      final rows = [
        ['e1', 'attr-text', 'Buy milk'],
        ['e1', 'attr-completed', false],
        ['e2', 'attr-text', 'Walk dog'],
      ];
      final entities = parseJoinRowsToEntities(rows, attributeCache);
      expect(entities.length, 2);

      final byId = {for (final e in entities) e['id']: e};
      expect(byId['e1']!['text'], 'Buy milk');
      expect(byId['e1']!['completed'], false);
      expect(byId['e2']!['text'], 'Walk dog');
    });

    test('uses first element when entity id is an array', () {
      final rows = [
        [
          ['e1', 'extra'],
          'attr-text',
          'Buy milk',
        ],
      ];
      final entities = parseJoinRowsToEntities(rows, attributeCache);
      expect(entities.single['id'], 'e1');
      expect(entities.single['text'], 'Buy milk');
    });

    test('infers "completed" for unknown attr id with bool value', () {
      final rows = [
        ['e1', 'unknown-attr', true],
      ];
      final entities = parseJoinRowsToEntities(rows, attributeCache);
      expect(entities.single['completed'], true);
    });

    test('drops unknown non-bool attribute values', () {
      final rows = [
        ['e1', 'unknown-attr', 'mystery'],
      ];
      final entities = parseJoinRowsToEntities(rows, attributeCache);
      // Only the id key survives; the unknown string value is not attached.
      expect(entities.single.keys.toList(), ['id']);
    });

    test('ignores rows with fewer than 3 columns', () {
      final rows = [
        ['e1', 'attr-text'],
      ];
      final entities = parseJoinRowsToEntities(rows, attributeCache);
      expect(entities, isEmpty);
    });
  });

  group('groupEntitiesByType', () {
    test('buckets by __type field when present', () {
      final entities = [
        {'id': 'e1', '__type': 'todos'},
        {'id': 'e2', '__type': 'messages'},
        {'id': 'e3', '__type': 'todos'},
      ];
      final out = <String, List<Map<String, dynamic>>>{};
      groupEntitiesByType(entities, out);
      expect(out['todos']!.length, 2);
      expect(out['messages']!.length, 1);
    });

    test('uses defaultType when __type missing', () {
      final entities = [
        {'id': 'e1'},
      ];
      final out = <String, List<Map<String, dynamic>>>{};
      groupEntitiesByType(entities, out, defaultType: 'tiles');
      expect(out['tiles']!.length, 1);
    });

    test('falls back to todos when no type and no default', () {
      final entities = [
        {'id': 'e1'},
      ];
      final out = <String, List<Map<String, dynamic>>>{};
      groupEntitiesByType(entities, out);
      expect(out['todos']!.length, 1);
    });
  });

  group('tryConvertDatalogToCollectionFormat end-to-end', () {
    test('converts datalog-result join-rows into typed collection', () {
      final resultData = {
        'datalog-result': {
          'join-rows': [
            ['e1', 'attr-text', 'Buy milk'],
            ['e1', 'attr-completed', false],
            ['e2', 'attr-text', 'Walk dog'],
          ],
        },
      };
      final out = tryConvertDatalogToCollectionFormat(
        resultData,
        attributeCache,
        queryEntityType: 'todos',
      );
      expect(out.containsKey('todos'), isTrue);
      expect(out['todos']!.length, 2);
      final byId = {for (final e in out['todos']!) e['id']: e};
      expect(byId['e1']!['text'], 'Buy milk');
      expect(byId['e1']!['completed'], false);
    });

    test('uses query-entity-type collection fallback', () {
      final resultData = {
        'tiles': [
          {'id': 't1', 'color': 'red'},
        ],
      };
      final out = tryConvertDatalogToCollectionFormat(
        resultData,
        attributeCache,
        queryEntityType: 'tiles',
      );
      expect(out['tiles']!.single['color'], 'red');
    });

    test('legacy todos fallback', () {
      final resultData = {
        'todos': [
          {'id': 'e1', 'text': 'x'},
        ],
      };
      final out = tryConvertDatalogToCollectionFormat(resultData, attributeCache);
      expect(out['todos']!.single['text'], 'x');
    });

    test('generic collection-like array fallback', () {
      final resultData = {
        'messages': [
          {'id': 'm1', 'body': 'hi'},
        ],
      };
      final out = tryConvertDatalogToCollectionFormat(resultData, attributeCache);
      expect(out['messages']!.single['body'], 'hi');
    });

    test('non-map result returns empty', () {
      expect(
        tryConvertDatalogToCollectionFormat('nope', attributeCache),
        isEmpty,
      );
    });
  });
}
