import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/instant_db.dart';
import '../core/types.dart';
import 'instant_builder.dart';

/// Debugger-only theme brightness (dark by default). Kept module-level so the
/// choice persists across sheet opens without touching the host app's theme.
final ValueNotifier<bool> _devDark = ValueNotifier<bool>(true);

/// A React-devtool-style inspector for InstantDB. Wrap your app subtree (must
/// be inside an [InstantProvider]) and a draggable floating button appears; tap
/// it to open a bottom sheet with three read-only tabs:
///
///  - **Status**   — appId, connection lifecycle, current auth user.
///  - **Explorer** — table viewer: namespaces → rows grid → create/edit/delete.
///  - **Query**    — run a raw InstaQL query and see the JSON result.
///
/// Place it UNDER the app's [Navigator] (e.g. wrap `home` or a screen body) so
/// it can open the sheet — wrapping `MaterialApp` itself, or `MaterialApp.builder`,
/// puts it above the Navigator and the sheet fails to open.
///
/// The Explorer tab is a table viewer: pick a namespace, browse its rows in a
/// grid, and create / edit / delete rows inline (writes go through the normal
/// optimistic sync path). Gate with `kDebugMode`
/// to keep it out of release builds:
///
/// ```dart
/// MaterialApp(
///   home: kDebugMode
///       ? const InstantDevTool(child: HomeScreen())
///       : const HomeScreen(),
/// )
/// ```
class InstantDevTool extends StatefulWidget {
  final Widget child;
  const InstantDevTool({super.key, required this.child});

  @override
  State<InstantDevTool> createState() => _InstantDevToolState();
}

class _InstantDevToolState extends State<InstantDevTool> {
  OverlayEntry? _entry;
  Offset? _pos; // null → default bottom-right

  @override
  void initState() {
    super.initState();
    // Insert the floating button into the app's Overlay (under the Navigator →
    // has Directionality and floats above every screen, without wrapping or
    // rebuilding the app subtree the way a Stack would). Deferred to after the
    // frame so we don't mark the Overlay dirty while the tree is still building
    // (InstantProvider builds us during its own build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry != null) return;
      _entry = OverlayEntry(builder: _buildButton);
      Overlay.of(context).insert(_entry!);
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  bool _sheetOpen = false;

  void _open() {
    if (_sheetOpen) {
      Navigator.of(context).pop(); // second tap closes it (toggle)
      return;
    }
    _sheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // M3 caps sheet width at 640 on wide screens; force full width on desktop.
      constraints: const BoxConstraints(maxWidth: double.infinity),
      backgroundColor:
          Colors.transparent, // _DevSheet paints its own themed surface
      builder: (_) => InstantProvider(
        db: InstantProvider.of(context),
        child: const _DevSheet(),
      ),
    ).whenComplete(() => _sheetOpen = false);

    // The sheet route is pushed above our button entry; re-insert the button on
    // top so it stays tappable (second tap toggles the sheet closed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final entry = _entry;
      if (!mounted || entry == null || !entry.mounted) return;
      final overlay = Overlay.of(context);
      entry.remove();
      overlay.insert(entry);
    });
  }

  Widget _buildButton(BuildContext overlayContext) {
    final media = MediaQuery.of(overlayContext);
    final pos = _pos ?? Offset(media.size.width - 72, media.size.height - 100);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          final p = (_pos ?? pos) + d.delta;
          _pos = Offset(
            p.dx.clamp(0.0, media.size.width - 56),
            p.dy.clamp(media.padding.top, media.size.height - 56),
          );
          _entry?.markNeedsBuild();
        },
        child: Material(
          color: Colors.transparent,
          child: FloatingActionButton.small(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            heroTag: 'instant-devtool',
            onPressed: _open,
            // package: needed — the asset ships with this package, not the app.
            child: Image.asset(
              'assets/logo.png',
              package: 'flutter_instantdb',
              width: 24,
              height: 24,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DevSheet extends StatelessWidget {
  const _DevSheet();

  @override
  Widget build(BuildContext context) {
    // Fixed-tall sheet; each tab owns its own scrolling. Wrapped in its own
    // Theme so the dark/light toggle only affects the debugger, not the app.
    final mq = MediaQuery.of(context);
    final height = mq.size.height * 0.6;
    return ValueListenableBuilder<bool>(
      valueListenable: _devDark,
      builder: (context, dark, _) {
        // Very small radius on every surface/control in the devtool.
        final r = BorderRadius.circular(3);
        final shape = RoundedRectangleBorder(borderRadius: r);
        final btn = ButtonStyle(shape: WidgetStatePropertyAll(shape));
        final theme = ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          useMaterial3: true,
          // Small, dense text everywhere in the devtool.
          visualDensity: VisualDensity.comfortable,
          // Switzer, bundled with this package — scoped to the devtool only.
          // Package-bundled fonts must be referenced with the packages/ prefix.
          fontFamily: 'packages/flutter_instantdb/Switzer',
          cardTheme: CardThemeData(shape: shape),
          dialogTheme: DialogThemeData(shape: shape),
          bottomSheetTheme: BottomSheetThemeData(shape: shape),
          popupMenuTheme: PopupMenuThemeData(shape: shape),
          filledButtonTheme: FilledButtonThemeData(style: btn),
          elevatedButtonTheme: ElevatedButtonThemeData(style: btn),
          outlinedButtonTheme: OutlinedButtonThemeData(style: btn),
          textButtonTheme: TextButtonThemeData(style: btn),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: r),
          ),
        );
        return Theme(
          data: theme,
          // Shrink every text in the devtool uniformly (incl. explicit sizes).
          child: MediaQuery(
            data: mq.copyWith(textScaler: const TextScaler.linear(0.95)),
            child: Material(
              color: theme.colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              child: SizedBox(
                height: height,
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: theme.dividerColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              dark ? Icons.light_mode : Icons.dark_mode,
                            ),
                            tooltip: 'Toggle debugger theme',
                            onPressed: () => _devDark.value = !dark,
                          ),
                        ],
                      ),
                      const TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          Tab(text: 'Status'),
                          Tab(text: 'Explorer'),
                          Tab(text: 'Query'),
                        ],
                      ),
                      const Expanded(
                        child: TabBarView(
                          children: [_StatusTab(), _ExplorerTab(), _QueryTab()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab();

  static Color _statusColor(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.authenticated:
        return Colors.green;
      case ConnectionStatus.opened:
        return Colors.lightBlue;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.closed:
        return Colors.grey;
      case ConnectionStatus.errored:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);
    final entities = db.schema?.entities.keys.toList() ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _header(context, 'Connection'),
          ConnectionStateBuilder(
            builder: (context, status) => _stat(
              context,
              Icons.circle,
              'Status',
              status.name,
              dotColor: _statusColor(status),
            ),
          ),
          _stat(context, Icons.cloud_outlined, 'App ID', db.appId, copy: true),
          _stat(
            context,
            Icons.storage_outlined,
            'Storage',
            'SQLite (triple store)',
          ),
          _header(context, 'Auth'),
          AuthBuilder(
            builder: (context, user) => user == null
                ? _stat(
                    context,
                    Icons.person_off_outlined,
                    'User',
                    '(signed out)',
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _stat(
                        context,
                        Icons.person_outline,
                        'Email',
                        user.email.isEmpty ? '(none)' : user.email,
                      ),
                      _stat(
                        context,
                        Icons.badge_outlined,
                        'User ID',
                        user.id,
                        copy: true,
                      ),
                      _stat(
                        context,
                        Icons.verified_user_outlined,
                        'Type',
                        user.isGuest == true ? 'guest' : 'registered',
                      ),
                    ],
                  ),
          ),
          _header(context, 'Schema'),
          _stat(
            context,
            Icons.table_chart_outlined,
            'Entities',
            entities.isEmpty ? '(no schema)' : entities.join(', '),
          ),
          FutureBuilder<List<String>>(
            future: db.listNamespaces(),
            builder: (context, snap) => _stat(
              context,
              Icons.list_alt_outlined,
              'Namespaces',
              snap.hasData ? '${snap.data!.length}' : '…',
            ),
          ),
        ],
      ),
    );
  }

  // Full-width header — forces a new line in the Wrap.
  Widget _header(BuildContext context, String title) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );

  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? dotColor,
    bool copy = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: dotColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (copy) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied $label'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Icon(Icons.copy, size: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ExplorerTab extends StatefulWidget {
  const _ExplorerTab();

  @override
  State<_ExplorerTab> createState() => _ExplorerTabState();
}

class _ExplorerTabState extends State<_ExplorerTab> {
  String? _ns;

  List<String>? _namespaces;
  bool _nsLoading = false;

  Signal<QueryResult>? _query;

  // Rows from the latest reactive query value; kept so _columns / _typeOf can
  // read them outside the Watch.
  List<Map<String, dynamic>> _rows = const [];

  // Selection (row ids) + client-side pagination.
  final Set<String> _selected = {};
  int _page = 0;
  int _pageSize = 25;
  static const _pageSizes = [10, 25, 50, 100];

  InstantDB get _db => InstantProvider.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_namespaces == null && !_nsLoading) _loadNamespaces();
  }

  Future<void> _loadNamespaces() async {
    setState(() => _nsLoading = true);
    final names = await _db.listNamespaces();
    if (mounted) {
      setState(() {
        _namespaces = names;
        _nsLoading = false;
      });
    }
  }

  // Field names known from schema / server attrs, so the grid and the row
  // editor show the right columns even for an empty table.
  List<String> _fields = const [];
  Map<String, String> _fieldTypes = const {};

  void _open(String ns) {
    setState(() {
      _ns = ns;
      _rows = const [];
      _selected.clear();
      _page = 0;
      _fields = _db.namespaceFields(ns);
      _fieldTypes = _db.namespaceFieldTypes(ns);
      // Reactive: the table rebuilds on every store change (local writes AND
      // remote sync), so no manual refresh is needed.
      _query = _db.query({
        ns: {'limit': 200},
      });
    });
  }

  static final _dateName = RegExp(r'(at|At|[dD]ate|[tT]ime|timestamp)$');

  /// Resolve a column's editor type: schema type first, else infer from the
  /// first non-null row value. A number named like a timestamp becomes a
  /// datetime picker.
  String _typeOf(String col) {
    final schemaType = _fieldTypes[col];
    if (schemaType == 'boolean') return 'boolean';
    if (schemaType == 'string') return 'string';
    if (schemaType == 'number') {
      return _dateName.hasMatch(col) ? 'datetime' : 'number';
    }
    for (final r in _rows) {
      final v = r[col];
      if (v is bool) return 'boolean';
      if (v is int) return _dateName.hasMatch(col) ? 'datetime' : 'number';
      if (v is double) return 'number';
      if (v is String) return 'string';
    }
    return 'string';
  }

  /// Force a re-subscribe (the query is already reactive; this just re-issues
  /// it, e.g. after connecting so newly-known rows appear).
  void _reload() {
    if (_ns != null) {
      setState(
        () => _query = _db.query({
          _ns!: {'limit': 200},
        }),
      );
    }
  }

  /// Column names: schema/server fields ∪ keys seen across rows (id first,
  /// __type dropped). Using the known fields means an empty table still shows
  /// its columns and the editor pre-fills the right fields.
  List<String> get _columns {
    final set = <String>{..._fields};
    for (final r in _rows) {
      set.addAll(r.keys);
    }
    set
      ..remove('__type')
      ..remove('id');
    final cols = set.toList()..sort();
    return ['id', ...cols];
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${ids.length} row${ids.length == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in ids) {
      await _db.transact(_db.tx[_ns!][id].delete());
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _edit({Map<String, dynamic>? row}) async {
    final specs = [
      for (final c in _columns)
        if (c != 'id') (name: c, type: _typeOf(c)),
    ];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RowEditor(fields: specs, row: row),
    );
    if (result == null) return;
    if (row == null) {
      final id = _db.id();
      await _db.transact(_db.create(_ns!, {'id': id, ...result}));
    } else {
      await _db.transact(_db.update(row['id'] as String, result));
    }
    // Table is reactive — it refreshes itself from the store change.
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 720;
    final names = _namespaces ?? const <String>[];

    // Desktop: persistent sidebar + table side by side (dashboard layout).
    if (wide) {
      if (_ns == null && names.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _ns == null && names.isNotEmpty) _open(names.first);
        });
      }
      return Row(
        children: [
          SizedBox(width: 190, child: _sidebar(names)),
          const VerticalDivider(width: 1),
          Expanded(
            child: _ns == null
                ? const Center(child: Text('Select a table'))
                : _detail(_ns!, wide: true),
          ),
        ],
      );
    }

    // Mobile: drill-in (sidebar → table).
    if (_ns == null) return _sidebar(names);
    return _detail(_ns!, wide: false);
  }

  Widget _sidebar(List<String> names) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Namespaces',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              InkWell(
                onTap: _nsLoading ? null : _loadNamespaces,
                child: const Icon(Icons.refresh, size: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _nsLoading && _namespaces == null
              ? const Center(child: CircularProgressIndicator())
              : names.isEmpty
              ? const Center(child: Text('No tables'))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final n in names)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        selected: n == _ns,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        title: Text(
                          n,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        onTap: () => _open(n),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _detail(String ns, {required bool wide}) {
    return Column(
      children: [
        Row(
          children: [
            if (!wide)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _ns = null;
                  _rows = const [];
                  _selected.clear();
                }),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              // Live count — reads the same signal, so it updates on writes /
              // sync and when switching namespaces (no manual refresh).
              child: Watch((context) {
                final r = _query?.value;
                final n = (r?.data?[ns] as List?)?.length ?? 0;
                return Text(
                  '$ns  ($n)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                );
              }),
            ),
            if (_selected.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('Delete ${_selected.length}'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _deleteSelected,
              ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New row',
              onPressed: () => _edit(),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          // Live: rebuilds whenever the query signal changes (local writes or
          // remote sync) — no manual refresh needed.
          child: Watch((context) {
            final result = _query?.value;
            if (result == null || result.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = ((result.data?[ns] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _rows = rows; // feed _columns / _typeOf / header count
            if (rows.isEmpty) {
              return const Center(child: Text('empty — tap + to add a row'));
            }
            final columns = _columns;
            final pageCount = (rows.length / _pageSize).ceil();
            final page = _page.clamp(0, pageCount - 1);
            final start = page * _pageSize;
            final pageRows = rows.skip(start).take(_pageSize).toList();
            final pageIds = {for (final r in pageRows) r['id'] as String};

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        // Fill the available width; scroll only if columns
                        // overflow it.
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: DataTable(
                            showCheckboxColumn: true,
                            headingRowHeight: 34,
                            dataRowMinHeight: 28,
                            dataRowMaxHeight: 34,
                            columnSpacing: 18,
                            horizontalMargin: 10,
                            dividerThickness: 0.5,
                            onSelectAll: (v) => setState(() {
                              if (v == true) {
                                _selected.addAll(pageIds);
                              } else {
                                _selected.removeAll(pageIds);
                              }
                            }),
                            columns: [
                              const DataColumn(label: Text('')),
                              for (final c in columns)
                                DataColumn(
                                  label: Text(
                                    c,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                            rows: [
                              for (final row in pageRows)
                                DataRow(
                                  selected: _selected.contains(row['id']),
                                  onSelectChanged: (v) => setState(() {
                                    final id = row['id'] as String;
                                    if (v == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  }),
                                  cells: [
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _edit(row: row),
                                      ),
                                    ),
                                    for (final c in columns)
                                      DataCell(
                                        Text(
                                          '${row[c] ?? ''}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _paginationBar(
                  rows.length,
                  page,
                  pageCount,
                  start,
                  pageRows.length,
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _paginationBar(
    int total,
    int page,
    int pageCount,
    int start,
    int shown,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          const Text('Rows:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          // PopupMenuButton, not DropdownButton: the latter asserts on menu
          // placement inside a scaled/short bottom sheet.
          PopupMenuButton<int>(
            initialValue: _pageSize,
            tooltip: 'Rows per page',
            padding: EdgeInsets.zero,
            onSelected: (v) => setState(() {
              _pageSize = v;
              _page = 0;
            }),
            itemBuilder: (context) => [
              for (final n in _pageSizes)
                PopupMenuItem(value: n, height: 36, child: Text('$n')),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_pageSize', style: const TextStyle(fontSize: 12)),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '${total == 0 ? 0 : start + 1}–${start + shown} of $total',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: page < pageCount - 1
                ? () => setState(() => _page = page + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// One typed input per column (label = column name). Field types come from the
/// schema (string / number / boolean) plus a datetime picker for number columns
/// named like a timestamp. Returns the typed field map on save, null on cancel.
/// `id` / `__type` are managed by the store and never shown.
class _RowEditor extends StatefulWidget {
  final List<({String name, String type})> fields;
  final Map<String, dynamic>? row;
  const _RowEditor({required this.fields, this.row});

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, bool> _bools = {};
  final Map<String, int?> _dates = {}; // epoch ms

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.row?[f.name];
      switch (f.type) {
        case 'boolean':
          _bools[f.name] = v is bool ? v : false;
        case 'datetime':
          _dates[f.name] = v is int ? v : (v is num ? v.toInt() : null);
        default:
          _text[f.name] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String name) async {
    final current = _dates[name] != null
        ? DateTime.fromMillisecondsSinceEpoch(_dates[name]!)
        : DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() => _dates[name] = dt.millisecondsSinceEpoch);
  }

  void _save() {
    final map = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case 'boolean':
          map[f.name] = _bools[f.name] ?? false;
        case 'datetime':
          map[f.name] = _dates[f.name];
        case 'number':
          final s = _text[f.name]!.text.trim();
          map[f.name] = s.isEmpty ? null : num.tryParse(s);
        default:
          final s = _text[f.name]!.text;
          map[f.name] = s.isEmpty ? null : s;
      }
    }
    Navigator.pop(context, map);
  }

  Widget _field(({String name, String type}) f) {
    switch (f.type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.name),
          value: _bools[f.name] ?? false,
          onChanged: (v) => setState(() => _bools[f.name] = v),
        );
      case 'datetime':
        final ms = _dates[f.name];
        final label = ms == null
            ? 'not set'
            : DateTime.fromMillisecondsSinceEpoch(
                ms,
              ).toString().split('.').first;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.name),
          subtitle: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ms != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _dates[f.name] = null),
                ),
              IconButton(
                icon: const Icon(Icons.event),
                onPressed: () => _pickDate(f.name),
              ),
            ],
          ),
        );
      case 'number':
        return TextField(
          controller: _text[f.name],
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(labelText: f.name, isDense: true),
        );
      default:
        return TextField(
          controller: _text[f.name],
          decoration: InputDecoration(labelText: f.name, isDense: true),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.row == null ? 'New row' : 'Edit row'),
      content: SizedBox(
        width: 360,
        child: widget.fields.isEmpty
            ? const Text(
                'No known fields yet — set a schema or connect so the '
                'table\'s attributes are known.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in widget.fields)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _field(f),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.fields.isNotEmpty)
          FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _QueryTab extends StatefulWidget {
  const _QueryTab();

  @override
  State<_QueryTab> createState() => _QueryTabState();
}

class _QueryTabState extends State<_QueryTab> {
  final _input = TextEditingController(text: '{"todos": {}}');
  String _output = '';
  bool _running = false;

  Future<void> _run() async {
    final db = InstantProvider.of(context);
    setState(() => _running = true);
    try {
      final query = jsonDecode(_input.text) as Map<String, dynamic>;
      final r = await db.queryOnce(query);
      setState(() => _output = _pretty(r.data ?? {}));
    } catch (e) {
      setState(() => _output = 'Error: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _input,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'InstaQL query (JSON)',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Running…' : 'Run queryOnce'),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _pretty(Object? obj) {
  try {
    return const JsonEncoder.withIndent('  ').convert(obj);
  } catch (_) {
    return obj.toString();
  }
}
