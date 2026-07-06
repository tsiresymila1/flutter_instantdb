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
  Offset? _pos; // null → default bottom-right

  void _open() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // _DevSheet paints its own themed surface
      builder: (_) => InstantProvider(
        db: InstantProvider.of(context),
        child: const _DevSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final pos = _pos ??
        Offset(media.size.width - 72, media.size.height - 100);
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              final p = (_pos ?? pos) + d.delta;
              _pos = Offset(
                p.dx.clamp(0, media.size.width - 56),
                p.dy.clamp(media.padding.top, media.size.height - 56),
              );
            }),
            child: FloatingActionButton.small(
              elevation: 2,
              heroTag: 'instant-devtool',
              onPressed: _open,
              child: const Icon(Icons.bug_report_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

class _DevSheet extends StatelessWidget {
  const _DevSheet();

  @override
  Widget build(BuildContext context) {
    // Fixed-tall sheet; each tab owns its own scrolling. Wrapped in its own
    // Theme so the dark/light toggle only affects the debugger, not the app.
    final height = MediaQuery.of(context).size.height * 0.6;
    return ValueListenableBuilder<bool>(
      valueListenable: _devDark,
      builder: (context, dark, _) {
        final theme = ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          useMaterial3: true,
        );
        return Theme(
          data: theme,
          child: Material(
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
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
                              dark ? Icons.light_mode : Icons.dark_mode),
                          tooltip: 'Toggle debugger theme',
                          onPressed: () => _devDark.value = !dark,
                        ),
                      ],
                    ),
                    const TabBar(tabs: [
                      Tab(text: 'Status'),
                      Tab(text: 'Explorer'),
                      Tab(text: 'Query'),
                    ]),
                    const Expanded(
                      child: TabBarView(children: [
                        _StatusTab(),
                        _ExplorerTab(),
                        _QueryTab(),
                      ]),
                    ),
                  ],
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

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _section(context, 'Connection'),
        ConnectionStateBuilder(
          builder: (context, status) => _row(
            context,
            icon: Icons.circle,
            iconColor: _statusColor(status),
            label: 'Status',
            value: status.name,
          ),
        ),
        _row(context,
            icon: Icons.cloud_outlined, label: 'App ID', value: db.appId,
            copy: true),
        _row(context,
            icon: Icons.storage_outlined,
            label: 'Storage',
            value: 'SQLite (triple store)'),

        _section(context, 'Auth'),
        AuthBuilder(
          builder: (context, user) {
            if (user == null) {
              return _row(context,
                  icon: Icons.person_off_outlined,
                  label: 'User',
                  value: '(signed out)');
            }
            return Column(
              children: [
                _row(context,
                    icon: Icons.person_outline,
                    label: 'Email',
                    value: user.email.isEmpty ? '(none)' : user.email),
                _row(context,
                    icon: Icons.badge_outlined,
                    label: 'User ID',
                    value: user.id,
                    copy: true),
                _row(context,
                    icon: Icons.verified_user_outlined,
                    label: 'Type',
                    value: user.isGuest == true ? 'guest' : 'registered'),
              ],
            );
          },
        ),

        _section(context, 'Schema'),
        _row(context,
            icon: Icons.table_chart_outlined,
            label: 'Entities',
            value: entities.isEmpty
                ? '(no schema)'
                : '${entities.length}: ${entities.join(", ")}'),
        FutureBuilder<List<String>>(
          future: db.listNamespaces(),
          builder: (context, snap) => _row(context,
              icon: Icons.list_alt_outlined,
              label: 'Namespaces',
              value: snap.hasData ? '${snap.data!.length}' : '…'),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _row(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String label,
    required String value,
    bool copy = false,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, size: 18, color: iconColor),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      subtitle: Text(value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      trailing: copy
          ? IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Copied $label'),
                      duration: const Duration(seconds: 1)),
                );
              },
            )
          : null,
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
      _fields = _db.namespaceFields(ns);
      _fieldTypes = _db.namespaceFieldTypes(ns);
      // Reactive: the table rebuilds on every store change (local writes AND
      // remote sync), so no manual refresh is needed.
      _query = _db.query({ns: {'limit': 200}});
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
      setState(() => _query = _db.query({_ns!: {'limit': 200}}));
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

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete row?'),
        content: Text(id),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _db.transact(_db.tx[_ns!][id].delete());
    // Table is reactive — it refreshes itself from the store change.
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
    if (_ns == null) {
      final names = _namespaces ?? const <String>[];
      return Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              const Expanded(
                child: Text('Tables',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload tables',
                onPressed: _nsLoading ? null : _loadNamespaces,
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _nsLoading && _namespaces == null
                ? const Center(child: CircularProgressIndicator())
                : names.isEmpty
                    ? const Center(
                        child: Text('No namespaces yet — tap refresh once '
                            'connected'))
                    : ListView(
                        children: [
                          for (final n in names)
                            ListTile(
                              leading:
                                  const Icon(Icons.table_chart_outlined),
                              title: Text(n),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _open(n),
                            ),
                        ],
                      ),
          ),
        ],
      );
    }

    final ns = _ns!;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _ns = null;
                _rows = const [];
              }),
            ),
            Expanded(
              child: Text('$ns  (${_rows.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
            return SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('')),
                    for (final c in columns) DataColumn(label: Text(c)),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(cells: [
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => _edit(row: row),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _delete(row['id'] as String),
                            ),
                          ],
                        )),
                        for (final c in columns)
                          DataCell(Text('${row[c] ?? ''}')),
                      ]),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
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
    final dt = DateTime(date.year, date.month, date.day,
        time?.hour ?? 0, time?.minute ?? 0);
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
            : DateTime.fromMillisecondsSinceEpoch(ms).toString().split('.').first;
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
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
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
        width: double.maxFinite,
        child: widget.fields.isEmpty
            ? const Text('No known fields yet — set a schema or connect so the '
                'table\'s attributes are known.')
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
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
