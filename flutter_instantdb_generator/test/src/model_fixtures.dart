import 'package:source_gen_test/source_gen_test.dart';

// Test-local stand-ins for the annotations (same shape as the runtime ones).
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

class InstantField {
  final String name;
  const InstantField(this.name);
}

@ShouldGenerate(r'''
class TodoTable extends InstantModelTable<TodoTable, Todo> {
  TodoTable() : super('todos');

  final id = const Col<String>('id');
  final title = const Col<String>('title');
  final priority = const Col<int>('priority');

  @override
  Todo fromRow(Map<String, dynamic> m) => Todo(
        id: m['id'] as String,
        title: m['title'] as String,
        priority: m['priority'] as int,
      );
}

extension TodoQueryX on TypedQuery<TodoTable> {
  Future<List<Todo>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(TodoTable().fromRow)
          .toList();

  Signal<List<Todo>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(TodoTable().fromRow).toList());
  }
}
''')
@InstantModel('todos')
class Todo {
  final String id;
  final String title;
  final int priority;
  const Todo({required this.id, required this.title, required this.priority});
}
