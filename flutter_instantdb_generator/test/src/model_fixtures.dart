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

class InstantLink {
  final String? attr;
  const InstantLink({this.attr});
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

  Map<String, dynamic> toMap(Todo m) => {
        'id': m.id,
        'title': m.title,
        'priority': m.priority,
      };
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

extension TodoTxX on TypedTx<TodoTable> {
  TransactionChunk createModel(Todo m) => createFromMap(TodoTable().toMap(m));
  TransactionChunk updateModel(String id, Todo m) =>
      updateFromMap(id, TodoTable().toMap(m));
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

  Map<String, dynamic> toMap(Profile m) => {
        'id': m.id,
        'created_at': m.createdAt,
        'nickname': m.nickname,
      };
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

extension ProfileTxX on TypedTx<ProfileTable> {
  TransactionChunk createModel(Profile m) =>
      createFromMap(ProfileTable().toMap(m));
  TransactionChunk updateModel(String id, Profile m) =>
      updateFromMap(id, ProfileTable().toMap(m));
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

@ShouldThrow(
  'Field "title" on MismatchModel has no matching named constructor parameter. '
  'The generated fromRow needs `MismatchModel({required ... title})`.',
)
@InstantModel('mismatch')
class MismatchModel {
  final String id;
  final String title;
  const MismatchModel({required this.id, required String heading})
      : title = heading;
}

// ---------------------------------------------------------------------------
// Relation fixtures for @InstantLink (nested-2)
// ---------------------------------------------------------------------------

// Author is the to-one relation target for Post.
@ShouldGenerate(r'''
class AuthorTable extends InstantModelTable<AuthorTable, Author> {
  AuthorTable() : super('authors');

  final id = const Col<String>('id');
  final name = const Col<String>('name');

  @override
  Author fromRow(Map<String, dynamic> m) => Author(
        id: m['id'] as String,
        name: m['name'] as String,
      );

  Map<String, dynamic> toMap(Author m) => {
        'id': m.id,
        'name': m.name,
      };
}

extension AuthorQueryX on TypedQuery<AuthorTable> {
  Future<List<Author>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(AuthorTable().fromRow)
          .toList();

  ReadonlySignal<List<Author>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(AuthorTable().fromRow).toList());
  }
}

extension AuthorTxX on TypedTx<AuthorTable> {
  TransactionChunk createModel(Author m) =>
      createFromMap(AuthorTable().toMap(m));
  TransactionChunk updateModel(String id, Author m) =>
      updateFromMap(id, AuthorTable().toMap(m));
}
''')
@InstantModel('authors')
class Author {
  final String id;
  final String name;
  const Author({required this.id, required this.name});
}

// Goal has a to-many @InstantLink to Todo.
@ShouldGenerate(r'''
class GoalTable extends InstantModelTable<GoalTable, Goal> {
  GoalTable() : super('goals');

  final id = const Col<String>('id');
  final title = const Col<String>('title');

  TypedQuery<TodoTable> get todos =>
      TypedQuery<TodoTable>(TodoTable(), relationAttr: 'todos');

  static const todosRel = RelationRef<TodoTable>('todos');

  @override
  Goal fromRow(Map<String, dynamic> m) => Goal(
        id: m['id'] as String,
        title: m['title'] as String,
        todos: (m['todos'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(TodoTable().fromRow)
                .toList() ??
            const <Todo>[],
      );

  Map<String, dynamic> toMap(Goal m) => {
        'id': m.id,
        'title': m.title,
      };
}

extension GoalQueryX on TypedQuery<GoalTable> {
  Future<List<Goal>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(GoalTable().fromRow)
          .toList();

  ReadonlySignal<List<Goal>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(GoalTable().fromRow).toList());
  }
}

extension GoalTxX on TypedTx<GoalTable> {
  TransactionChunk createModel(Goal m) => createFromMap(GoalTable().toMap(m));
  TransactionChunk updateModel(String id, Goal m) =>
      updateFromMap(id, GoalTable().toMap(m));
}
''')
@InstantModel('goals')
class Goal {
  final String id;
  final String title;
  @InstantLink()
  final List<Todo> todos;
  const Goal({required this.id, required this.title, required this.todos});
}

// Post has a to-one @InstantLink to Author (nullable).
@ShouldGenerate(r'''
class PostTable extends InstantModelTable<PostTable, Post> {
  PostTable() : super('posts');

  final id = const Col<String>('id');
  final title = const Col<String>('title');

  TypedQuery<AuthorTable> get author =>
      TypedQuery<AuthorTable>(AuthorTable(), relationAttr: 'author');

  static const authorRel = RelationRef<AuthorTable>('author');

  @override
  Post fromRow(Map<String, dynamic> m) => Post(
        id: m['id'] as String,
        title: m['title'] as String,
        author: (() {
          final l = (m['author'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>();
          return (l == null || l.isEmpty)
              ? null
              : AuthorTable().fromRow(l.first);
        })(),
      );

  Map<String, dynamic> toMap(Post m) => {
        'id': m.id,
        'title': m.title,
      };
}

extension PostQueryX on TypedQuery<PostTable> {
  Future<List<Post>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(PostTable().fromRow)
          .toList();

  ReadonlySignal<List<Post>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(PostTable().fromRow).toList());
  }
}

extension PostTxX on TypedTx<PostTable> {
  TransactionChunk createModel(Post m) => createFromMap(PostTable().toMap(m));
  TransactionChunk updateModel(String id, Post m) =>
      updateFromMap(id, PostTable().toMap(m));
}
''')
@InstantModel('posts')
class Post {
  final String id;
  final String title;
  @InstantLink()
  final Author? author;
  const Post({required this.id, required this.title, this.author});
}

// NonModel is NOT annotated with @InstantModel — used for the @ShouldThrow below.
class NonModel {
  final String id;
  const NonModel({required this.id});
}

@ShouldThrow(
  'Relation field "target" on BadLink targets "NonModel", which is not an @InstantModel.',
)
@InstantModel('badlinks')
class BadLink {
  final String id;
  @InstantLink()
  final List<NonModel> target;
  const BadLink({required this.id, required this.target});
}
