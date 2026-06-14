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

const dartModelsSrc = '''
import 'package:flutter_instantdb/flutter_instantdb.dart';

part 'app_schema.instant.dart';

@InstantModel('todos')
class Todo {
  final String id;
  final String text;
  final bool completed;
  final num createdAt;
  const Todo({
    required this.id,
    required this.text,
    required this.completed,
    required this.createdAt,
  });
}
''';

// todos.owner -> users (to-one); users.todos -> todos (to-many)
const linkTs = '''
const schema = i.schema({
  entities: {
    users: i.entity({
      name: i.string(),
    }),
    todos: i.entity({
      text: i.string(),
    }),
  },
  links: {
    todoOwner: {
      forward: { on: 'todos', has: 'one', label: 'owner' },
      reverse: { on: 'users', has: 'many', label: 'todos' },
    },
  },
  rooms: {},
});
export default schema;
''';

// todos.author -> \$users (system); only the user-side field should appear.
const sysLinkTs = '''
const schema = i.schema({
  entities: {
    "\$users": i.entity({
      email: i.string().optional(),
    }),
    todos: i.entity({
      text: i.string(),
    }),
  },
  links: {
    todoAuthor: {
      forward: { on: 'todos', has: 'one', label: 'author' },
      reverse: { on: '\$users', has: 'many', label: 'authoredTodos' },
    },
  },
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

  group('parseDartModels + emitInstantTs (Dart -> TS)', () {
    test('emits instant.schema.ts from Dart models', () {
      final ts = emitInstantTs(parseDartModels(dartModelsSrc));
      expect(ts, contains("import { i } from '@instantdb/react'"));
      expect(ts, contains('todos: i.entity({'));
      expect(ts, contains('i.boolean()'));
      expect(ts, contains('i.string().unique()')); // id
      expect(ts, contains('export default schema'));
      expect(ts, contains('i.number()')); // createdAt
    });

    test('@InstantField(unique/indexed) round-trips to modifiers', () {
      final ts = emitInstantTs(parseDartModels(
        "@InstantModel('users') class User { final String id; "
        "@InstantField('email', unique: true, indexed: true) final String email; "
        "const User({required this.id, required this.email}); }",
      ));
      expect(ts, contains('i.string().unique().indexed()'));
    });
  });

  group('links round-trip', () {
    test('forward/reverse <-> @InstantLink both sides', () {
      final s = parseInstantTs(linkTs);
      final dart = emitDart(s);
      expect(dart, contains('@InstantLink()'));
      expect(dart, contains('User? owner')); // to-one
      expect(dart, contains('List<Todo> todos')); // to-many

      final ts2 = emitInstantTs(parseDartModels(dart));
      expect(ts2, contains('links: {'));
      expect(ts2, contains("has: 'one'"));
      expect(ts2, contains("has: 'many'"));
    });

    test('system-entity link emits only the user-side @InstantLink', () {
      final dart = emitDart(parseInstantTs(sysLinkTs));
      expect(dart, contains('User? author'));
      expect(dart, isNot(contains('class User')));
      // no reverse field landing on a system entity
      expect(dart, isNot(contains('authoredTodos')));
    });
  });

  group('round-trip stability', () {
    test('TS -> Dart -> TS preserves user entities', () {
      final s1 = parseInstantTs(todosTs);
      final ts2 = emitInstantTs(parseDartModels(emitDart(s1)));
      final s2 = parseInstantTs(ts2);
      expect(
        s2.entities.map((e) => e.name),
        containsAll(
          s1.entities.where((e) => !e.system).map((e) => e.name),
        ),
      );
      // field types preserved (number -> num -> number)
      final todos2 = s2.entities.firstWhere((e) => e.name == 'todos');
      expect(
        todos2.fields.firstWhere((f) => f.name == 'createdAt').instantType,
        'number',
      );
      expect(
        todos2.fields.firstWhere((f) => f.name == 'completed').instantType,
        'boolean',
      );
    });
  });

  group('edge cases', () {
    test('a full modifier chain parses all flags', () {
      const ts = '''
const schema = i.schema({
  entities: {
    users: i.entity({
      handle: i.string().unique().indexed().optional(),
    }),
  },
  links: {},
});
''';
      final f = parseInstantTs(ts)
          .entities
          .firstWhere((e) => e.name == 'users')
          .fields
          .firstWhere((f) => f.name == 'handle');
      expect(f.optional, isTrue);
      expect(f.unique, isTrue);
      expect(f.indexed, isTrue);
      final dart = emitDart(parseInstantTs(ts));
      expect(dart, contains('final String? handle;'));
    });

    test('@InstantField with double quotes parses the attr name', () {
      const src = '''
@InstantModel('users')
class User {
  final String id;
  @InstantField("email_addr", unique: true)
  final String email;
  const User({required this.id, required this.email});
}
''';
      final ts = emitInstantTs(parseDartModels(src));
      expect(ts, contains('email_addr: i.string().unique()'));
    });

    test('colliding class names fail loudly', () {
      const ts = '''
const schema = i.schema({
  entities: {
    stats: i.entity({ v: i.number() }),
    stat: i.entity({ v: i.number() }),
  },
  links: {},
});
''';
      expect(() => emitDart(parseInstantTs(ts)), throwsArgumentError);
    });
  });
}
