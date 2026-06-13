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

  ReadonlySignal<List<Todo>> watchAll(InstantDB db) {
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

@ShouldGenerate(r'''
class ProfileTable extends InstantModelTable<ProfileTable, Profile> {
  ProfileTable() : super('profiles');

  final id = const Col<String>('id');
  final createdAt = const Col<int>('created_at');
  final nickname = const Col<String>('nickname');

  @override
  Profile fromRow(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        createdAt: m['created_at'] as int,
        nickname: m['nickname'] as String?,
      );
}

extension ProfileQueryX on TypedQuery<ProfileTable> {
  Future<List<Profile>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(ProfileTable().fromRow)
          .toList();

  ReadonlySignal<List<Profile>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(ProfileTable().fromRow).toList());
  }
}
''')
@InstantModel('profiles')
class Profile {
  final String id;
  @InstantField('created_at')
  final int createdAt;
  final String? nickname;
  const Profile({required this.id, required this.createdAt, this.nickname});
}

@ShouldThrow(
  'Field "owner" on BadModel has unsupported type "Profile". '
  'Relations/non-primitive types are not yet generated; '
  'make the field nullable to skip it until nested support lands.',
)
@InstantModel('bad')
class BadModel {
  final String id;
  final Profile owner; // non-nullable relation -> error
  const BadModel({required this.id, required this.owner});
}
