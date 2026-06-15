# Flutter InstantDB

**Real-time, offline-first database for Flutter.** A Dart port of [InstantDB](https://instantdb.com) — local-first storage, instant sync, reactive widgets, and type-safe queries. Build collaborative apps in minutes.

[![pub package](https://img.shields.io/pub/v/flutter_instantdb.svg)](https://pub.dev/packages/flutter_instantdb)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

📚 **[Docs](https://flutter-instantdb.vercel.app)** · 🚀 **[Quick Start](https://flutter-instantdb.vercel.app/docs/getting-started/quick-start)** · 🧩 **[Example app](example/)** · 🤖 **[llms.txt](https://flutter-instantdb.vercel.app/llms.txt)**

---

## Why

- ⚡ **Real-time sync** — changes propagate to every connected client over WebSocket.
- 📴 **Offline-first** — reads/writes hit local SQLite instantly; sync resumes when online.
- 🔄 **Reactive UI** — widgets rebuild automatically when data changes (powered by signals).
- 🔒 **Type-safe** — InstaQL queries, an optional typed DSL, and code generation.
- 👥 **Multiplayer** — presence, cursors, typing, reactions, and ephemeral topics out of the box.
- 🔑 **Batteries included** — auth (magic code + OAuth), file storage, aggregations, pagination.

## Install

```sh
flutter pub add flutter_instantdb
```

Requires Flutter SDK ≥ 3.8.0 and an InstantDB App ID (free at [instantdb.com](https://instantdb.com)).

| Platform | Storage |
|----------|---------|
| Android · iOS · macOS · Windows · Linux | SQLite |
| Web | SQLite (WASM) persisted in IndexedDB |

## Quick start

### 1. Initialize and provide the client

```dart
import 'package:flutter/material.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await InstantDB.init(
    appId: 'YOUR_APP_ID',
    config: const InstantConfig(syncEnabled: true),
  );

  // InstantProvider exposes the client to the widget tree.
  runApp(InstantProvider(db: db, child: const MyApp()));
}
```

### 2. Read data reactively

`InstantBuilder` subscribes to a query and rebuilds on every change:

```dart
InstantBuilder(
  query: const {
    'todos': {
      'where': {'done': false},
      'order': {'serverCreatedAt': 'desc'},
      'limit': 20,
    },
  },
  builder: (context, data) {
    final todos = (data['todos'] as List).cast<Map<String, dynamic>>();
    return ListView(
      children: [for (final t in todos) Text(t['text'] as String)],
    );
  },
)
```

### 3. Write data

Transactions are optimistic — the UI updates immediately and rolls back if the server rejects.

```dart
final db = InstantProvider.of(context);

// Create
await db.transact(db.create('todos', {'text': 'Ship it', 'done': false}));

// Update / delete
await db.transact(db.update(id, {'done': true}));
await db.transact(db.tx['todos'][id].delete());

// Link a relation
await db.transact(db.update(todoId).link({'author': userId}));
```

## Queries (InstaQL)

Queries are plain maps. Filter, order, paginate, and include relations:

```dart
const {
  'posts': {
    'where': {'published': true, 'views': {r'$gte': 100}},
    'order': {'serverCreatedAt': 'desc'},
    'limit': 10,
    'include': {'author': {}},   // resolve the linked author
  },
}
```

One-shot reads, infinite scroll, and aggregations:

```dart
final result = await db.queryOnce({'todos': {}});

// Aggregations: count / sum / avg / min / max (+ optional groupBy)
final open = await db.count('todos', where: {'done': false});
final byStatus = await db.aggregate(
  'todos',
  aggregates: {'count': '*', 'avg': 'priority'},
  groupBy: ['status'],
);

// Infinite scroll
final feed = db.infiniteQuery({'posts': {}}, entityType: 'posts', pageSize: 20);
```

## Reactive widgets

Flutter equivalents of InstantDB's React hooks:

| Widget | React equivalent | Purpose |
|--------|------------------|---------|
| `InstantBuilder` / `InstantBuilderTyped` | `useQuery` | Reactive query results |
| `InstantInfiniteBuilder` | — | Paginated / infinite lists |
| `AuthBuilder` / `AuthGuard` | `useAuth` | Auth state + route gating |
| `ConnectionStateBuilder` | — | Connection lifecycle |
| `PresenceBuilder` | `usePresence` | Live peer presence in a room |
| `CursorOverlay` | `<Cursors>` | Multiplayer cursor layer |
| `TypingIndicatorBuilder` | — | Who's typing |
| `ReactionsBuilder` | — | Live reaction stream |
| `TopicListener` | `useTopicEffect` | React to ephemeral topic events |
| `OAuthButton` | — | Provider sign-in button |

## Authentication

```dart
// Magic code
await db.auth.sendMagicCode(email: 'me@example.com');
await db.auth.verifyMagicCode(email: 'me@example.com', code: '123456');

// Guest / sign out
await db.auth.signInAsGuest();
await db.auth.signOut();

// React to auth state
AuthBuilder(builder: (context, user) =>
    user == null ? const LoginScreen() : const HomeScreen());
```

### OAuth

Provider id-token sign-in (token comes from `google_sign_in`, `sign_in_with_apple`, Clerk, Firebase, …):

```dart
await db.auth.signInWithGoogle(idToken: idToken);
await db.auth.signInWithApple(idToken: idToken);
```

Or the redirect flow with PKCE built in:

```dart
final flow = db.auth.createAuthorizationUrl(
  clientName: 'google',
  redirectUri: 'myapp://oauth',
);
// open flow.url, capture the ?code= on redirect, then:
await db.auth.exchangeCodeForToken(code: code, codeVerifier: flow.codeVerifier);
```

The `OAuthButton` widget wires this up — you supply the launcher (e.g. `url_launcher`), so no extra dependency is forced on you.

## Presence & collaboration

```dart
// Live cursors + presence count, no manual wiring:
CursorOverlay(
  roomId: 'doc-42',
  userName: 'Alice',
  userColor: '#E91E63',
  child: PresenceBuilder(
    roomId: 'doc-42',
    initialPresence: const {'name': 'Alice'},
    builder: (context, room, peers) => Text('${peers.length} online'),
  ),
)
```

`TypingIndicatorBuilder`, `ReactionsBuilder`, and `TopicListener` cover typing, reactions, and ephemeral messaging. For lower-level control use `db.presence.joinRoom(roomId)` → `InstantRoom`.

## File storage

```dart
final file = await db.storage.uploadFile('avatars/me.png', bytes,
    contentType: 'image/png');
final url = await db.storage.getDownloadUrl('avatars/me.png');
final files = await db.storage.list(order: {'serverCreatedAt': 'desc'});
await db.storage.delete('avatars/me.png');
```

## Typed API

Skip string maps. `Col<T>` and `TypedQuery` give compile-time-checked queries and writes:

```dart
final q = TodoTable()
    .query()
    .where((t) => t.done.eq(false) & t.priority.gte(2))
    .order((t) => t.createdAt.desc())
    .limit(20);

final result = await db.queryOnceTyped(q);

// Field-checked writes
await db.transact(db.txFor(TodoTable()).create()
  ..set(TodoTable.text, 'Ship')
  ..set(TodoTable.done, false));
```

Tables can be **generated** with `@InstantModel` / `@InstantLink` (see [`flutter_instantdb_generator`](flutter_instantdb_generator/)) — or **hand-written**, no codegen required:

```dart
class TodoTable extends InstantTable<TodoTable> {
  TodoTable() : super('todos');
  static const text = Col<String>('text');
  static const done = Col<bool>('done');
  static const authorRel = RelationRef<UserTable>('author'); // relation, by hand
}

// Linking works with or without codegen:
await db.transact(db.txFor(TodoTable()).linkRel(todoId, TodoTable.authorRel, userId));
```

See [Typed Relations → Without code generation](https://flutter-instantdb.vercel.app/docs/typed/relations#without-code-generation).

## Documentation

Full docs at **[flutter-instantdb.vercel.app](https://flutter-instantdb.vercel.app)**:

- **Getting started** — [Installation](https://flutter-instantdb.vercel.app/docs/getting-started/installation) · [Quick Start](https://flutter-instantdb.vercel.app/docs/getting-started/quick-start)
- **Queries** — [Basics](https://flutter-instantdb.vercel.app/docs/queries/basics) · [Operators](https://flutter-instantdb.vercel.app/docs/queries/operators) · [Pagination](https://flutter-instantdb.vercel.app/docs/queries/pagination) · [Aggregations](https://flutter-instantdb.vercel.app/docs/queries/aggregations)
- **Typed API** — [Overview](https://flutter-instantdb.vercel.app/docs/typed/overview) · [Query DSL](https://flutter-instantdb.vercel.app/docs/typed/query-dsl) · [Relations](https://flutter-instantdb.vercel.app/docs/typed/relations) · [Code Generation](https://flutter-instantdb.vercel.app/docs/typed/codegen)
- **Auth** — [Users](https://flutter-instantdb.vercel.app/docs/auth/users) · [Sessions](https://flutter-instantdb.vercel.app/docs/auth/sessions) · [Permissions](https://flutter-instantdb.vercel.app/docs/auth/permissions)
- **Real-time** — [Sync](https://flutter-instantdb.vercel.app/docs/realtime/sync) · [Presence](https://flutter-instantdb.vercel.app/docs/realtime/presence) · [Collaboration](https://flutter-instantdb.vercel.app/docs/realtime/collaboration)
- **Advanced** — [Offline](https://flutter-instantdb.vercel.app/docs/advanced/offline) · [Storage](https://flutter-instantdb.vercel.app/docs/advanced/storage) · [Performance](https://flutter-instantdb.vercel.app/docs/advanced/performance) · [Troubleshooting](https://flutter-instantdb.vercel.app/docs/advanced/troubleshooting)

For LLMs/agents: [`/llms.txt`](https://flutter-instantdb.vercel.app/llms.txt) (index) and [`/llms-full.txt`](https://flutter-instantdb.vercel.app/llms-full.txt) (complete docs).

## Tips

- Let `db.id()` generate ids — custom non-UUID string ids cause server errors.
- Scope queries (`where` / `limit`) instead of fetching whole namespaces.
- Keep `syncEnabled: true` for real-time; the app still works fully offline.

## Contributing

Contributions welcome — see the [Contributing Guide](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

[InstantDB](https://instantdb.com) · [signals_flutter](https://pub.dev/packages/signals_flutter) · [SQLite](https://sqlite.org)
