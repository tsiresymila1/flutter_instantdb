# Flutter InstantDB

Real-time, offline-first database for Flutter with reactive bindings. Build collaborative apps in minutes.

- 📚 Docs: https://flutter-instantdb.vercel.app
- 🚀 Quick Start: https://flutter-instantdb.vercel.app/getting-started/quick-start
- 🧩 Example app: [example/](example/)

This package provides a Flutter/Dart port of [InstantDB](https://instantdb.com), enabling you to build real-time, collaborative applications with ease.

## Features

- ✅ **Real-time synchronization** - Changes sync instantly across all connected clients with differential sync for reliable deletions
- ✅ **Offline-first** - Local SQLite storage with automatic sync when online
- ✅ **Reactive UI** - Widgets automatically update when data changes using Signals
- ✅ **Type-safe queries** - InstaQL query language with schema validation
- ✅ **Transactions** - Atomic operations with optimistic updates and rollback
- ✅ **Authentication** - Built-in user authentication and session management
- ✅ **Presence system** - Real-time collaboration features (cursors, typing, reactions, avatars) with consistent multi-instance synchronization
- ✅ **Conflict resolution** - Automatic handling of concurrent data modifications
- ✅ **Flutter widgets** - Purpose-built reactive widgets for common patterns

## Requirements

- Flutter SDK >= 3.8.0
- Dart SDK >= 3.8.0
- An InstantDB App ID (create one at [instantdb.com](https://instantdb.com))

## Platform Support

| Platform | Support | Notes |
|----------|---------|------|
| Android | ✅ | SQLite storage |
| iOS | ✅ | SQLite storage |
| Web | ✅ | SQLite (WASM) persisted in IndexedDB |
| macOS | ✅ | SQLite storage |
| Windows | ✅ | SQLite storage |
| Linux | ✅ | SQLite storage |

## Documentation

- Getting Started: [Installation](https://flutter-instantdb.vercel.app/getting-started/installation) · [Quick Start](https://flutter-instantdb.vercel.app/getting-started/quick-start)
- Concepts: [Database](https://flutter-instantdb.vercel.app/concepts/database) · [Schema](https://flutter-instantdb.vercel.app/concepts/schema)
- API Reference: [InstantDB](https://flutter-instantdb.vercel.app/api/instantdb) · [Queries](https://flutter-instantdb.vercel.app/api/queries) · [Transactions](https://flutter-instantdb.vercel.app/api/transactions) · [Presence](https://flutter-instantdb.vercel.app/api/presence-api) · [Widgets](https://flutter-instantdb.vercel.app/api/widgets) · [Types](https://flutter-instantdb.vercel.app/api/types)
- Authentication: [Users](https://flutter-instantdb.vercel.app/auth/users) · [Sessions](https://flutter-instantdb.vercel.app/auth/sessions) · [Permissions](https://flutter-instantdb.vercel.app/auth/permissions)
- Real-time: [Sync](https://flutter-instantdb.vercel.app/realtime/sync) · [Presence](https://flutter-instantdb.vercel.app/realtime/presence) · [Collaboration](https://flutter-instantdb.vercel.app/realtime/collaboration)
- Advanced: [Offline](https://flutter-instantdb.vercel.app/advanced/offline) · [Performance](https://flutter-instantdb.vercel.app/advanced/performance) · [Migration](https://flutter-instantdb.vercel.app/advanced/migration) · [Troubleshooting](https://flutter-instantdb.vercel.app/advanced/troubleshooting)

## Quick Start

### 1. Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_instantdb: ^1.1.2
```

Or install from the command line:

```sh
flutter pub add flutter_instantdb
```

### 2. Initialize InstantDB

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables (optional, but recommended)
  await dotenv.load(fileName: '.env');

  // Initialize your database
  final appId = dotenv.env['INSTANTDB_API_ID']!;
  final db = await InstantDB.init(
    appId: appId, // Or use your App ID directly: 'your-app-id'
    config: InstantConfig(
      syncEnabled: true, // Enable real-time sync
      verboseLogging: true, // Enable debug logging in development
    ),
  );

  runApp(MyApp(db: db));
}
```

### 3. Define Your Schema (Optional)

```dart
final todoSchema = Schema.object({
  'id': Schema.id(),
  'text': Schema.string(minLength: 1),
  'completed': Schema.boolean(),
  'createdAt': Schema.number(),
});

final schema = InstantSchemaBuilder()
  .addEntity('todos', todoSchema)
  .build();
```

### 4. Build Reactive UI

```dart
// Wrap your app with InstantProvider
class MyApp extends StatelessWidget {
  final InstantDB db;

  const MyApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return InstantProvider(
      db: db,
      child: MaterialApp(
        title: 'My App',
        home: const TodosPage(),
      ),
    );
  }
}

// Access the database using InstantProvider.of(context)
class TodosPage extends StatelessWidget {
  const TodosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InstantBuilderTyped<List<Map<String, dynamic>>>(
      query: {'todos': {}},
      transformer: (data) {
        final todos = (data['todos'] as List).cast<Map<String, dynamic>>();
        // Sort client-side by createdAt in descending order
        todos.sort((a, b) {
          final aTime = a['createdAt'] as int? ?? 0;
          final bTime = b['createdAt'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });
        return todos;
      },
      loadingBuilder: (context) => const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error) => Center(child: Text('Error: $error')),
      builder: (context, todos) {
        if (todos.isEmpty) {
          return const Center(child: Text('No todos yet'));
        }

        return ListView.builder(
          itemCount: todos.length,
          itemBuilder: (context, index) {
            final todo = todos[index];
            return ListTile(
              title: Text(todo['text'] ?? ''),
              leading: Checkbox(
                value: todo['completed'] == true,
                onChanged: (value) => _toggleTodo(context, todo),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTodo(context, todo['id']),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleTodo(BuildContext context, Map<String, dynamic> todo) async {
    final db = InstantProvider.of(context);
    await db.transact(
      db.tx['todos'][todo['id']].update({'completed': !todo['completed']}),
    );
  }

  Future<void> _deleteTodo(BuildContext context, String todoId) async {
    final db = InstantProvider.of(context);
    await db.transact(db.tx['todos'][todoId].delete());
  }
}
```

### 5. Perform Mutations

```dart
Future<void> addTodo(BuildContext context, String text) async {
  final db = InstantProvider.of(context);

  // Create a new todo using the traditional transaction API
  final todoId = db.id(); // Generates a proper UUID - required by InstantDB
  await db.transact([
    ...db.create('todos', {
      'id': todoId,
      'text': text,
      'completed': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }),
  ]);
}

Future<void> toggleTodo(BuildContext context, Map<String, dynamic> todo) async {
  final db = InstantProvider.of(context);

  // Update using the tx namespace API (aligned with React InstantDB)
  await db.transact(
    db.tx['todos'][todo['id']].update({'completed': !todo['completed']}),
  );
}

Future<void> deleteTodo(BuildContext context, String todoId) async {
  final db = InstantProvider.of(context);

  // Delete using the tx namespace API
  await db.transact(db.tx['todos'][todoId].delete());
}

// Deep merge for nested updates
Future<void> updateUserPreferences(BuildContext context, String userId) async {
  final db = InstantProvider.of(context);
  await db.transact(
    db.tx['users'][userId].merge({
      'preferences': {
        'theme': 'dark',
        'notifications': {'email': false}
      }
    }),
  );
}
```

## Core Concepts

### Reactive Queries

Flutter InstantDB uses [Signals](https://pub.dev/packages/signals_flutter) for reactivity. Use `InstantBuilder` widgets for reactive UI updates, or `queryOnce` for one-time data fetching.

```dart
// In a widget, use InstantBuilder for reactive queries
InstantBuilder(
  query: {'todos': {}},
  loadingBuilder: (context) => const Center(child: CircularProgressIndicator()),
  errorBuilder: (context, error) => Center(child: Text('Error: $error')),
  builder: (context, data) {
    final todos = (data['todos'] as List? ?? []);
    return Text('Total: ${todos.length} todos');
  },
);

// One-time query (no subscriptions) - useful for operations like clearing all items
Future<void> clearAllTodos(BuildContext context) async {
  final db = InstantProvider.of(context);
  final queryResult = await db.queryOnce({'todos': {}});

  if (queryResult.data != null && queryResult.data!['todos'] is List) {
    final todos = (queryResult.data!['todos'] as List).cast<Map<String, dynamic>>();
    for (final todo in todos) {
      await db.transact(db.tx['todos'][todo['id']].delete());
    }
  }
}

// Using Watch widget for reactive updates with signals
Watch((context) {
  final db = InstantProvider.of(context);
  final cursors = room.getCursors().value;
  return Text('Active cursors: ${cursors.length}');
});
```

#### Cursor pagination & infinite scroll

```dart
// Cursor pagination
final page = await db.queryOnce({
  'todos': { r'$': { 'order': {'n': 'asc'}, 'first': 20 } },
});
final next = page.pageInfo?['todos']?['endCursor'];

// Infinite scroll
final feed = db.infiniteQuery(
  {'todos': {r'$': {'order': {'n': 'asc'}}}},
  entityType: 'todos', pageSize: 20,
);
await feed.loadMore();
```

### Transactions

All mutations happen within transactions, which provide atomicity and enable optimistic updates. Access the database using `InstantProvider.of(context)`:

```dart
// Using tx namespace API for updates and deletes (aligned with React InstantDB)
Future<void> toggleTodo(BuildContext context, Map<String, dynamic> todo) async {
  final db = InstantProvider.of(context);
  await db.transact(
    db.tx['todos'][todo['id']].update({'completed': !todo['completed']}),
  );
}

Future<void> deleteTodo(BuildContext context, String todoId) async {
  final db = InstantProvider.of(context);
  await db.transact(db.tx['todos'][todoId].delete());
}

// Using traditional API for creating new entities
Future<void> addTodo(BuildContext context, String text) async {
  final db = InstantProvider.of(context);
  await db.transact([
    ...db.create('todos', {
      'id': db.id(), // Always use db.id() for proper UUID generation
      'text': text,
      'completed': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }),
  ]);
}
```

```dart
// Upsert by unique attribute
await db.transact(
  db.tx['profiles'].lookup('email', 'a@b.com').update({'name': 'Alice'}),
);

// Strict update (no create) + rule params
await db.transact(
  db.tx['goals'][goalId]
      .update({'title': 'Get fit'}, opts: const TxOpts(upsert: false))
      .ruleParams({'token': token}),
);
```

### Real-time Sync

When sync is enabled, changes are automatically synchronized across all connected clients:

```dart
// Enable sync during initialization
final db = await InstantDB.init(
  appId: appId,
  config: InstantConfig(
    syncEnabled: true, // Enable real-time sync
    verboseLogging: true, // Enable debug logging in development
  ),
);

// Monitor connection status in your AppBar
ConnectionStatusBuilder(
  builder: (context, isOnline) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isOnline ? Icons.cloud_done : Icons.cloud_off,
          color: Colors.white70,
        ),
        const SizedBox(width: 4),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  },
)

// Reactive connection lifecycle (connecting/opened/authenticated/closed/errored)
ConnectionStateBuilder(
  builder: (context, status) => Text(status.name),
);

// Stable per-name local id (survives restarts)
final deviceId = await db.getLocalId('device');
```

#### Enhanced Sync Features

Flutter InstantDB includes advanced synchronization capabilities:

- **Differential Sync**: Automatically detects and syncs deletions between instances
- **Deduplication Logic**: Prevents duplicate entities during sync operations
- **Transaction Integrity**: Proper conversion to InstantDB's tx-steps format
- **Comprehensive Logging**: Built-in hierarchical logging for debugging sync issues

All CRUD operations (Create, Read, Update, Delete) sync reliably across multiple running instances, including edge cases like deleting the last entity in a collection.

### Presence System

InstantDB includes a real-time presence system for collaborative features. Use the room-based API for better organization:

```dart
class CursorsPage extends StatefulWidget {
  const CursorsPage({super.key});

  @override
  State<CursorsPage> createState() => _CursorsPageState();
}

class _CursorsPageState extends State<CursorsPage> {
  String? _userId;
  InstantRoom? _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId == null) {
      _initializeUser();
      _joinRoom();
    }
  }

  void _initializeUser() {
    final db = InstantProvider.of(context);
    final currentUser = db.auth.currentUser.value;
    _userId = currentUser?.id ?? db.getAnonymousUserId();
  }

  void _joinRoom() {
    final db = InstantProvider.of(context);
    // Join a room to get a scoped API
    _room = db.presence.joinRoom('cursors-room');
  }

  void _updateCursor(Offset position) {
    if (_room == null) return;
    // Update cursor position using the room-based API
    _room!.updateCursor(x: position.dx, y: position.dy);
  }

  void _removeCursor() {
    _room?.removeCursor();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) => _updateCursor(event.localPosition),
      onExit: (_) => _removeCursor(),
      child: Stack(
        children: [
          // Display all cursors using Watch for reactivity
          Watch((context) {
            if (_room == null) return const SizedBox.shrink();

            final cursors = _room!.getCursors().value;

            return Stack(
              children: cursors.entries.map((entry) {
                final userId = entry.key;
                final cursor = entry.value;
                return Positioned(
                  left: cursor.x,
                  top: cursor.y,
                  child: CursorWidget(userId: userId, isMe: userId == _userId),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}
```

**Typing Indicators:**

```dart
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  InstantRoom? _room;
  Timer? _typingTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = InstantProvider.of(context);
    // Join room with initial presence
    _room = db.presence.joinRoom(
      'chat-room',
      initialPresence: {'userName': 'Alice', 'status': 'online'},
    );
  }

  void _startTyping() {
    _typingTimer?.cancel();
    _room?.setTyping(true);
    // Auto-stop typing after 3 seconds of inactivity
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _room?.setTyping(false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Typing indicators
        Watch((context) {
          if (_room == null) return const SizedBox.shrink();

          final typingUsers = _room!.getTyping().value;
          if (typingUsers.isEmpty) return const SizedBox.shrink();

          return Text('${typingUsers.length} user(s) typing...');
        }),
        // Message input
        TextField(
          onChanged: (_) => _startTyping(),
          onSubmitted: (_) => _stopTyping(),
        ),
      ],
    );
  }
}
```

**Reactions:**

```dart
void sendReaction(BuildContext context, String emoji, Offset position) {
  final db = InstantProvider.of(context);
  final room = db.presence.joinRoom('reactions-room');

  // Send reaction with position metadata
  room.sendReaction(
    emoji,
    metadata: {'x': position.dx, 'y': position.dy},
  );
}

// Display reactions
Watch((context) {
  if (room == null) return const SizedBox.shrink();

  final reactions = room!.getReactions().value;

  return Stack(
    children: reactions.map((reaction) {
      return Positioned(
        left: (reaction.metadata?['x'] ?? 0.0).toDouble(),
        top: (reaction.metadata?['y'] ?? 0.0).toDouble(),
        child: Text(reaction.emoji, style: const TextStyle(fontSize: 32)),
      );
    }).toList(),
  );
});
```

## Widget Reference

### InstantProvider

Provides InstantDB instance to the widget tree:

```dart
InstantProvider(
  db: db,
  child: MyApp(),
)
```

### InstantBuilder

Generic reactive query widget:

```dart
InstantBuilder(
  query: {'todos': {}},
  builder: (context, data) => TodoList(todos: data['todos']),
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
)
```

### InstantBuilderTyped

Type-safe reactive query widget:

```dart
InstantBuilderTyped<List<Todo>>(
  query: {'todos': {}},
  transformer: (data) => Todo.fromList(data['todos']),
  builder: (context, todos) => TodoList(todos: todos),
)
```

### AuthBuilder

Reactive authentication state widget:

```dart
AuthBuilder(
  builder: (context, user) {
    if (user != null) {
      return WelcomeScreen(user: user);
    } else {
      return LoginScreen();
    }
  },
)
```

## Query Language (InstaQL)

InstantDB uses a declarative query language with advanced operators:

```dart
// Basic query
{'users': {}}

// Advanced operators
{
  'users': {
    'where': {
      // Comparison operators
      'age': {'\$gte': 18, '\$lt': 65},
      'salary': {'\$gt': 50000, '\$lte': 200000},
      'status': {'\$ne': 'inactive'},

      // String pattern matching
      'email': {'\$like': '%@company.com'},
      'name': {'\$ilike': '%john%'}, // Case insensitive

      // Array operations
      'tags': {'\$contains': 'vip'},
      'skills': {'\$size': {'\$gte': 3}},
      'roles': {'\$in': ['admin', 'moderator']},

      // Existence checks
      'profilePicture': {'\$exists': true},
      'deletedAt': {'\$isNull': true},

      // Logical operators
      '\$and': [
        {'age': {'\$gte': 18}},
        {'\$or': [
          {'department': 'engineering'},
          {'department': 'design'}
        ]}
      ]
    },
    'orderBy': {'createdAt': 'desc'},
    'limit': 10,
    'offset': 20,
  }
}

// With relationships and nested conditions
{
  'users': {
    'include': {
      'posts': {
        'where': {'published': true},
        'orderBy': {'createdAt': 'desc'},
        'limit': 5,
      },
      'profile': {}
    },
  }
}

// String match + logical combinators
db.query({
  'todos': {
    'where': {
      'or': [
        {'title': {r'$ilike': '%urgent%'}},
        {'priority': {r'$gte': 8}},
      ],
    },
  },
});

// Lookup references (reference by attribute instead of ID)
{
  'posts': {
    'where': {
      'author': lookup('users', 'email', 'john@example.com')
    }
  }
}
```

## Authentication

InstantDB includes built-in authentication with magic code (passwordless) and guest authentication:

```dart
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  String? _userEmail;

  // Send magic code to email
  Future<void> _sendMagicCode() async {
    final email = _emailController.text.trim();
    final db = InstantProvider.of(context);

    await db.auth.sendMagicCode(email: email);

    setState(() {
      _codeSent = true;
      _userEmail = email;
    });
  }

  // Verify the magic code
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    final db = InstantProvider.of(context);

    await db.auth.verifyMagicCode(email: _userEmail!, code: code);
    // User is now signed in!
  }

  // Sign in as guest
  Future<void> _signAsGuest() async {
    final db = InstantProvider.of(context);
    await db.auth.signInAsGuest();
  }

  // Sign out
  Future<void> _signOut() async {
    final db = InstantProvider.of(context);
    await db.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);

    // Listen to auth state changes with StreamBuilder
    return StreamBuilder<AuthUser?>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = snapshot.data;

        if (user != null) {
          return Column(
            children: [
              Text('Signed in as ${user.email}'),
              Text('User ID: ${user.id}'),
              if (user.isGuest == true) Text('(Guest user)'),
              ElevatedButton(
                onPressed: _signOut,
                child: const Text('Sign Out'),
              ),
            ],
          );
        }

        if (_codeSent) {
          return Column(
            children: [
              Text('Code sent to $_userEmail'),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Verification Code'),
              ),
              ElevatedButton(
                onPressed: _verifyCode,
                child: const Text('Verify Code'),
              ),
            ],
          );
        }

        return Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            ElevatedButton(
              onPressed: _sendMagicCode,
              child: const Text('Send Magic Code'),
            ),
            ElevatedButton(
              onPressed: _signAsGuest,
              child: const Text('Continue as Guest'),
            ),
          ],
        );
      },
    );
  }
}
```

**Getting Current User:**

```dart
// One-time check
final db = InstantProvider.of(context);
final currentUser = db.auth.currentUser.value;

// For anonymous/guest users
final anonymousId = db.getAnonymousUserId();

// Verify refresh token
if (user?.refreshToken != null) {
  await db.auth.verifyRefreshToken(refreshToken: user!.refreshToken!);
}
```

## Schema Validation

Define and validate your data schemas:

```dart
final userSchema = Schema.object({
  'name': Schema.string(minLength: 1, maxLength: 100),
  'email': Schema.email(),
  'age': Schema.number(min: 0, max: 150),
  'posts': Schema.array(Schema.string()).optional(),
}, required: ['name', 'email']);

// Validate data
final isValid = userSchema.validate({
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});
```

## Example App

Check out the [example todo app](example/) for a complete demonstration of:
- Real-time synchronization between multiple instances
- Offline functionality with local persistence
- Reactive UI updates
- CRUD operations with transactions

To run the example:

```bash
cd example
flutter pub get
flutter run
```

### Web Platform Setup

When deploying to web, you need to copy the SQLite web worker files to your `web/` directory:

1. Copy the required files from the example:
   ```bash
   cp example/web/sqflite_sw.js web/
   cp example/web/sqlite3.wasm web/
   ```

2. Or manually download them from the sqflite_common_ffi_web package:
   - Follow the setup instructions at: https://github.com/tekartik/sqflite/tree/master/packages_web/sqflite_common_ffi_web#setup-binaries

Without these files, you'll see an error: "An error occurred while initializing the web worker. This is likely due to a failure to find the worker javascript file at sqflite_sw.js"

## Testing

The package includes comprehensive tests. To run them:

```bash
flutter test
```

For integration testing with a real InstantDB instance, create a `.env` file:

```
INSTANTDB_API_ID=your-test-app-id
```

## Architecture

Flutter InstantDB is built on several key components:

- **Triple Store**: Local SQLite-based storage using the RDF triple model (supports pattern queries like `todos:*`)
- **Query Engine**: InstaQL parser and executor with reactive bindings using Signals
- **Sync Engine**: WebSocket-based real-time synchronization with conflict resolution and differential sync
- **Transaction System**: Atomic operations with optimistic updates and proper rollback handling
- **Reactive Layer**: Signals-based reactivity for automatic UI updates
- **Cross-Platform**: Uses SQLite for robust local storage on all Flutter platforms (iOS, Android, Web, macOS, Windows, Linux)

## Logging and Debugging

Flutter InstantDB includes comprehensive logging to help with development and debugging:

### Configuration Options

```dart
final db = await InstantDB.init(
  appId: 'your-app-id',
  config: const InstantConfig(
    syncEnabled: true,
    verboseLogging: true, // Enable detailed debug logging
  ),
);
```

### Dynamic Log Level Control

Update log levels at runtime for testing and debugging:

```dart
import 'package:logging/logging.dart';
import 'package:flutter_instantdb/src/core/logging_config.dart';

// Change log level dynamically
InstantDBLogging.updateLogLevel(Level.FINE);   // Verbose debugging
InstantDBLogging.updateLogLevel(Level.INFO);   // General information
InstantDBLogging.updateLogLevel(Level.WARNING); // Warnings and errors only
```

### Log Levels

- **Level.FINE** - Detailed debug information (WebSocket messages, query execution, sync operations)
- **Level.INFO** - General operational information (connections, transactions)
- **Level.WARNING** - Important warnings and errors only (production-friendly)
- **Level.SEVERE** - Critical errors only

### Component-Specific Logging

Enable logging for specific components:

```dart
// Set different log levels per component
InstantDBLogging.setLevel('sync', Level.FINE);        // Sync engine details
InstantDBLogging.setLevel('query', Level.INFO);       // Query operations
InstantDBLogging.setLevel('websocket', Level.WARNING); // WebSocket errors only
InstantDBLogging.setLevel('transaction', Level.FINE);  // Transaction details
```

### Production Usage

For production apps, use WARNING level to minimize console output while preserving error information:

```dart
final db = await InstantDB.init(
  appId: 'your-app-id',
  config: const InstantConfig(
    syncEnabled: true,
    verboseLogging: false, // Production-friendly logging
  ),
);
```

## Performance Tips

1. **Use specific queries**: Avoid querying all data when you only need a subset
2. **Implement pagination**: Use `limit` and `offset` for large datasets
3. **Cache management**: The package automatically manages query caches
4. **Dispose resources**: Properly dispose of InstantDB instances
5. **UUID Generation**: Always use `db.id()` for entity IDs to ensure server compatibility
6. **Log level optimization**: Use WARNING level in production to reduce console noise

```dart
// Good: Specific query with UUID
await db.transact([
  ...db.create('todos', {
    'id': db.id(), // Required UUID format
    'completed': false,
    'text': 'My todo',
  }),
]);

{'todos': {'where': {'completed': false}, 'limit': 20}}

// Avoid: Querying everything or custom IDs
{'todos': {}}

// Avoid: Custom string IDs (will cause server errors)
'id': 'my-custom-id' // ❌ Invalid - not a UUID
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


## Acknowledgments

- [InstantDB](https://instantdb.com) - The original JavaScript implementation
- [Signals Flutter](https://pub.dev/packages/signals_flutter) - Reactive state management
- [SQLite](https://sqlite.org) - Local data persistence
