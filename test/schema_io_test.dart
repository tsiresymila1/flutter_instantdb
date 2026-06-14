import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/schema/instant_schema_io.dart';

const todosTs = '''
import { i } from '@instantdb/react';

const schema = i.schema({
  entities: {
    todos: i.entity({
      id: i.string().unique(),
      text: i.string(),
      completed: i.boolean(),
      createdAt: i.number(),
    }),
  },
  links: {},
  rooms: {},
});

export type AppSchema = typeof schema;
export default schema;
''';

const optionalTs = '''
const schema = i.schema({
  entities: {
    notes: i.entity({
      text: i.string(),
      note: i.string().optional(),
    }),
  },
  links: {},
  rooms: {},
});
export default schema;
''';

const jsonDateTs = '''
const schema = i.schema({
  entities: {
    events: i.entity({
      title: i.string(),
      meta: i.json(),
      at: i.date(),
    }),
  },
  links: {},
  rooms: {},
});
export default schema;
''';

void main() {
  group('parseInstantTs', () {
    test('parses i.schema entities + modifiers + system flag', () {
      final sample =
          File('example/scripts/instant.schema.ts').readAsStringSync();
      final s = parseInstantTs(sample);

      final todos = s.entities.firstWhere((e) => e.name == 'todos');
      expect(
        todos.fields.map((f) => f.name),
        containsAll(['id', 'text', 'completed', 'createdAt']),
      );

      final files = s.entities.firstWhere((e) => e.name == r'$files');
      expect(files.system, isTrue);

      final users = s.entities.firstWhere((e) => e.name == r'$users');
      expect(users.system, isTrue);

      // path is unique + indexed
      final path = files.fields.firstWhere((f) => f.name == 'path');
      expect(path.unique, isTrue);
      expect(path.indexed, isTrue);

      // $users.email is optional
      final email = users.fields.firstWhere((f) => f.name == 'email');
      expect(email.optional, isTrue);
    });
  });

  group('emitDart (TS -> Dart)', () {
    test('emits @InstantModel classes from TS', () {
      final dart = emitDart(parseInstantTs(todosTs));
      expect(dart, contains("@InstantModel('todos')"));
      expect(dart, contains('class Todo'));
      expect(dart, contains('final String id;'));
      expect(dart, contains('final String text;'));
      expect(dart, contains('final bool completed;'));
      expect(dart, contains('final num createdAt;'));
      expect(dart, contains("part '"));
      expect(
        dart,
        contains("import 'package:flutter_instantdb/flutter_instantdb.dart';"),
      );
    });

    test('optional field -> nullable + optional param', () {
      final dart = emitDart(parseInstantTs(optionalTs));
      expect(dart, contains('final String? note;'));
      expect(dart, contains('final String text;'));
      // required id + text, optional note
      expect(dart, contains('required this.id'));
      expect(dart, contains('required this.text'));
      expect(dart, contains('this.note'));
      expect(dart, isNot(contains('required this.note')));
    });

    test('json/date -> nullable optional, generator-safe', () {
      final dart = emitDart(parseInstantTs(jsonDateTs));
      expect(dart, contains('Map<String, dynamic>? meta'));
      expect(dart, contains('DateTime? at'));
      expect(dart, isNot(contains('required this.meta')));
      expect(dart, isNot(contains('required this.at')));
    });

    test('system entities not emitted as Dart classes', () {
      final sample =
          File('example/scripts/instant.schema.ts').readAsStringSync();
      final dart = emitDart(parseInstantTs(sample));
      expect(dart, isNot(contains('class File')));
      expect(dart, isNot(contains('class User')));
      expect(dart, contains('class Todo'));
      expect(dart, contains('class Tile'));
      expect(dart, contains('class Message'));
    });
  });
}
