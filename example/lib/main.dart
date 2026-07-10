// getAnonymousUserId is intentionally used for a synchronous guest id (the
// getLocalId replacement is async and doesn't fit these initState call sites).
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/aggregations_page.dart';
import 'pages/playground_page.dart';
import 'pages/auth_page.dart';
import 'pages/avatars_page.dart';
import 'pages/collab_widgets_page.dart';
import 'pages/cursors_page.dart';
import 'pages/custom_cursors_page.dart';
import 'pages/reactions_page.dart';
import 'pages/storage_page.dart';
import 'pages/tile_game_page.dart';

// Import all example pages
import 'pages/todos_page.dart';
import 'pages/typing_page.dart';

/// Mirrors example/scripts/instant.schema.ts. Only used so the devtool lists
/// every table (todos, tiles, messages) even before any rows exist.
final _exampleSchema = InstantSchema(
  entities: {
    'todos': InstantEntity(
      validator: Schema.object({
        'text': Schema.string(),
        'completed': Schema.boolean(),
        'createdAt': Schema.optional(Schema.number()),
      }),
    ),
    'tiles': InstantEntity(
      validator: Schema.object({
        'row': Schema.number(),
        'col': Schema.number(),
        'userId': Schema.string(),
        'userName': Schema.string(),
        'color': Schema.number(),
        'timestamp': Schema.number(),
      }),
    ),
    'messages': InstantEntity(
      validator: Schema.object({
        'userId': Schema.string(),
        'userName': Schema.string(),
        'text': Schema.string(),
        'timestamp': Schema.number(),
      }),
    ),
  },
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  final appId = dotenv.env['INSTANTDB_API_ID']!;
  final db = await InstantDB.init(
    appId: appId,
    // Declaring the schema makes every table show in the devtool Explorer even
    // when empty (the explorer lists schema entities, not just tables with rows).
    schema: _exampleSchema,
    config: InstantConfig(
      syncEnabled: true, // Enable real-time sync
      verboseLogging: true, // Use the debug preference
    ),
  );
  runApp(InstantDBExamplesApp(db: db));
}

class InstantDBExamplesApp extends StatelessWidget {
  final InstantDB db;

  const InstantDBExamplesApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstantDB Examples',
      theme: ThemeData(useMaterial3: true),
      // Provider under the Navigator so debug:true can mount the devtool (which
      // opens sheets/dialogs). One flag — no manual InstantDevTool wrapping.
      home: InstantProvider(
        db: db,
        debug: true,
        child: const ExamplesRootScreen(),
      ),
    );
  }
}

class ExamplesRootScreen extends StatefulWidget {
  const ExamplesRootScreen({super.key});

  @override
  State<ExamplesRootScreen> createState() => _ExamplesRootScreenState();
}

class _ExamplesRootScreenState extends State<ExamplesRootScreen> {
  String? _error;
  bool _debugEnabled = true; // Default to debug enabled

  @override
  void initState() {
    super.initState();
  }

  Future<void> _toggleDebug() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _debugEnabled = !_debugEnabled;
    });
    await prefs.setBool('debug_enabled', _debugEnabled);

    // Update logging level dynamically
    InstantDBLogging.updateLogLevel(_debugEnabled ? Level.FINE : Level.WARNING);

    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _debugEnabled ? 'Debug logging enabled' : 'Debug logging disabled',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: _debugEnabled ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize InstantDB',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    }
    return ExamplesNavigationScreen(
      debugEnabled: _debugEnabled,
      onToggleDebug: _toggleDebug,
    );
  }
}

class ExamplesNavigationScreen extends StatefulWidget {
  final bool debugEnabled;
  final VoidCallback onToggleDebug;

  const ExamplesNavigationScreen({
    super.key,
    required this.debugEnabled,
    required this.onToggleDebug,
  });

  @override
  State<ExamplesNavigationScreen> createState() =>
      _ExamplesNavigationScreenState();
}

class _ExamplesNavigationScreenState extends State<ExamplesNavigationScreen> {
  int _selectedIndex = 0;
  String? _userIdSuffix;

  static const List<_ExampleConfig> _examples = [
    _ExampleConfig(
      title: 'Playground',
      icon: Icons.science_outlined,
      color: Colors.red,
      widget: PlaygroundPage(),
    ),
    _ExampleConfig(
      title: 'Todos',
      icon: Icons.checklist,
      color: Colors.blue,
      widget: TodosPage(),
    ),
    _ExampleConfig(
      title: 'Auth',
      icon: Icons.lock_outline,
      color: Colors.indigo,
      widget: AuthPage(),
    ),
    _ExampleConfig(
      title: 'Cursors',
      icon: Icons.mouse_outlined,
      color: Colors.purple,
      widget: CursorsPage(),
    ),
    _ExampleConfig(
      title: 'Custom',
      icon: Icons.edit_location_alt_outlined,
      color: Colors.deepPurple,
      widget: CustomCursorsPage(),
    ),
    _ExampleConfig(
      title: 'Reactions',
      icon: Icons.emoji_emotions_outlined,
      color: Colors.orange,
      widget: ReactionsPage(),
    ),
    _ExampleConfig(
      title: 'Typing',
      icon: Icons.keyboard_outlined,
      color: Colors.teal,
      widget: TypingPage(),
    ),
    _ExampleConfig(
      title: 'Avatars',
      icon: Icons.group_outlined,
      color: Colors.green,
      widget: AvatarsPage(),
    ),
    _ExampleConfig(
      title: 'Tiles',
      icon: Icons.grid_on_outlined,
      color: Colors.red,
      widget: TileGamePage(),
    ),
    _ExampleConfig(
      title: 'Aggregations',
      icon: Icons.functions,
      color: Colors.cyan,
      widget: AggregationsPage(),
    ),
    _ExampleConfig(
      title: 'Collab',
      icon: Icons.groups_outlined,
      color: Colors.pink,
      widget: CollabWidgetsPage(),
    ),
    _ExampleConfig(
      title: 'Storage',
      icon: Icons.folder_outlined,
      color: Colors.brown,
      widget: StoragePage(),
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize user ID suffix once
    if (_userIdSuffix == null) {
      final db = InstantProvider.of(context);
      final currentUser = db.auth.currentUser.value;
      if (currentUser != null) {
        final userId = currentUser.id;
        _userIdSuffix = ' (${userId.substring(userId.length - 4)})';
      } else {
        // For guest users, use consistent anonymous user ID
        final userId = db.getAnonymousUserId();
        _userIdSuffix = ' (${userId.substring(userId.length - 4)})';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentExample = _examples[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'InstantDB - ${currentExample.title}${_userIdSuffix ?? ''}',
        ),
        backgroundColor: currentExample.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              widget.debugEnabled
                  ? Icons.bug_report
                  : Icons.bug_report_outlined,
              color: Colors.white,
            ),
            tooltip: widget.debugEnabled
                ? 'Disable Debug Logging'
                : 'Enable Debug Logging',
            onPressed: widget.onToggleDebug,
          ),
          ConnectionStateBuilder(
            builder: (context, status) {
              final online = status == ConnectionStatus.authenticated;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      online ? Icons.cloud_done : Icons.cloud_off,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      online ? 'Online' : 'Offline',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        // Scrollable top tabs (replaces the cramped bottom nav for 12+ pages).
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: Colors.white,
            height: 46,
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _examples.length; i++)
                    _buildTab(i, currentExample.color),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: currentExample.widget,
        ),
      ),
    );
  }

  Widget _buildTab(int i, Color activeColor) {
    final example = _examples[i];
    final selected = i == _selectedIndex;
    final color = selected ? activeColor : Colors.grey;
    return InkWell(
      onTap: () => _onItemTapped(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? activeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(example.icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              example.title,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleConfig {
  final String title;
  final IconData icon;
  final Color color;
  final Widget widget;

  const _ExampleConfig({
    required this.title,
    required this.icon,
    required this.color,
    required this.widget,
  });
}
