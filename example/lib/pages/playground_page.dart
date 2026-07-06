import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

/// One screen that exercises every InstantDB flow: auth, live query (stream),
/// queryOnce, transactions, aggregations, storage upload/download/list, and
/// presence (presence/typing/reactions/topics). Each button runs one SDK call
/// and appends the result (or error) to a shared log.
///
/// ponytail: deliberately one dense page instead of ten polished ones — it's a
/// manual test harness, not product UI.
class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  static const _roomId = 'playground';

  final _log = <String>[];
  final _email = TextEditingController(text: 'test@example.com');
  final _code = TextEditingController();
  final _todo = TextEditingController(text: 'Playground todo');

  InstantRoom? _room;

  InstantDB get _db => InstantProvider.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _room ??= _db.presence.joinRoom(_roomId, initialPresence: {'name': 'me'});
  }

  @override
  void dispose() {
    _room?.leave();
    _email.dispose();
    _code.dispose();
    _todo.dispose();
    super.dispose();
  }

  void _put(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  /// Run [fn], log its result or error. Every button funnels through here.
  Future<void> _run(String label, Future<Object?> Function() fn) async {
    _put('▶ $label…');
    try {
      final result = await fn();
      _put('✓ $label → ${_short(result)}');
    } catch (e) {
      _put('✗ $label → $e');
    }
  }

  String _short(Object? v) {
    final s = v?.toString() ?? 'null';
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  // --- flows ---------------------------------------------------------------

  Future<String?> _firstTodoId() async {
    final r = await _db.queryOnce({
      'todos': {'limit': 1},
    });
    final list = (r.data?['todos'] as List?) ?? const [];
    return list.isEmpty ? null : (list.first as Map)['id'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Playground'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: ConnectionStateBuilder(
            builder: (context, status) => Container(
              width: double.infinity,
              color: Colors.black12,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Text('connection: ${status.name}'),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _authSection(),
                _querySection(),
                _txSection(),
                _aggSection(),
                _storageSection(),
                _presenceSection(),
              ],
            ),
          ),
          const Divider(height: 1),
          _logView(),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    ),
  );

  Widget _btn(String label, VoidCallback onTap) =>
      ElevatedButton(onPressed: onTap, child: Text(label));

  Widget _authSection() => _card('Auth', [
    AuthBuilder(
      builder: (context, user) => Text(
        'user: ${user?.email ?? '(none)'}${user?.isGuest == true ? ' [guest]' : ''}',
      ),
    ),
    SizedBox(
      width: 180,
      child: TextField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'email'),
      ),
    ),
    SizedBox(
      width: 120,
      child: TextField(
        controller: _code,
        decoration: const InputDecoration(labelText: 'code'),
      ),
    ),
    _btn(
      'Guest sign-in',
      () => _run('signInAsGuest', () => _db.auth.signInAsGuest()),
    ),
    _btn(
      'Send magic code',
      () => _run('sendMagicCode', () async {
        await _db.auth.sendMagicCode(email: _email.text);
        return 'sent to ${_email.text}';
      }),
    ),
    _btn(
      'Verify code',
      () => _run(
        'verifyMagicCode',
        () => _db.auth.verifyMagicCode(email: _email.text, code: _code.text),
      ),
    ),
    _btn(
      'Sign out',
      () => _run('signOut', () async {
        await _db.auth.signOut();
        return 'signed out';
      }),
    ),
  ]);

  Widget _querySection() => _card('Query', [
    // Live stream: rebuilds as todos change.
    InstantBuilder(
      query: const {'todos': {}},
      loadingBuilder: (_) => const Text('stream: loading…'),
      builder: (context, data) =>
          Text('stream todos: ${(data['todos'] as List).length}'),
    ),
    _btn(
      'queryOnce todos',
      () => _run('queryOnce', () async {
        final r = await _db.queryOnce({'todos': {}});
        return '${(r.data?['todos'] as List?)?.length ?? 0} todos';
      }),
    ),
    _btn(
      'queryOnce where',
      () => _run('queryOnce(where completed=false)', () async {
        final r = await _db.queryOnce({
          'todos': {
            'where': {'completed': false},
          },
        });
        return '${(r.data?['todos'] as List?)?.length ?? 0} open';
      }),
    ),
  ]);

  Widget _txSection() => _card('Transactions', [
    _btn(
      'Create',
      () => _run('create todo', () async {
        final id = _db.id();
        await _db.transact(
          _db.create('todos', {
            'id': id,
            'text': _todo.text,
            'completed': false,
          }),
        );
        return id;
      }),
    ),
    _btn(
      'Toggle first',
      () => _run('update first todo', () async {
        final id = await _firstTodoId();
        if (id == null) return 'no todo';
        await _db.transact(_db.update(id, {'completed': true}));
        return 'toggled $id';
      }),
    ),
    _btn(
      'Delete first',
      () => _run('delete first todo', () async {
        final id = await _firstTodoId();
        if (id == null) return 'no todo';
        await _db.transact(_db.tx['todos'][id].delete());
        return 'deleted $id';
      }),
    ),
  ]);

  Widget _aggSection() => _card('Aggregations', [
    _btn('count', () => _run('count todos', () => _db.count('todos'))),
    _btn(
      'count open',
      () => _run(
        'count open',
        () => _db.count('todos', where: {'completed': false}),
      ),
    ),
    _btn(
      'group by completed',
      () => _run(
        'aggregate groupBy',
        () => _db.aggregate(
          'todos',
          aggregates: {'count': '*'},
          groupBy: ['completed'],
        ),
      ),
    ),
  ]);

  Widget _storageSection() => _card('Storage', [
    _btn(
      'Upload text file',
      () => _run('uploadFile', () async {
        final path = 'playground/${_db.id()}.txt';
        final bytes = Uint8List.fromList(utf8.encode('hello from playground'));
        final f = await _db.storage.uploadFile(
          path,
          bytes,
          contentType: 'text/plain',
        );
        return 'uploaded ${f.path}';
      }),
    ),
    _btn(
      'List files',
      () => _run('storage.list', () async {
        final files = await _db.storage.list(limit: 20);
        return '${files.length} files';
      }),
    ),
    _btn(
      'Download URL of first',
      () => _run('getDownloadUrl', () async {
        final files = await _db.storage.list(limit: 1);
        if (files.isEmpty) return 'no files';
        return _db.storage.getDownloadUrl(files.first.path);
      }),
    ),
    _btn(
      'Delete first',
      () => _run('storage.delete', () async {
        final files = await _db.storage.list(limit: 1);
        if (files.isEmpty) return 'no files';
        await _db.storage.delete(files.first.path);
        return 'deleted ${files.first.path}';
      }),
    ),
  ]);

  Widget _presenceSection() => TopicListener(
    roomId: _roomId,
    topic: 'ping',
    onEvent: (data) => _put('◆ topic ping → $data'),
    child: _card('Presence (room "$_roomId")', [
      PresenceBuilder(
        roomId: _roomId,
        builder: (context, room, peers) => Text('peers: ${peers.length}'),
      ),
      TypingIndicatorBuilder(
        roomId: _roomId,
        builder: (context, typing) => Text('typing: ${typing.length}'),
      ),
      ReactionsBuilder(
        roomId: _roomId,
        builder: (context, reactions) => Text('reactions: ${reactions.length}'),
      ),
      _btn(
        'Set presence',
        () => _run('setPresence', () async {
          await _room?.setPresence({
            'name': 'me',
            'at': DateTime.now().toIso8601String(),
          });
          return 'ok';
        }),
      ),
      _btn(
        'Typing on',
        () => _run('setTyping(true)', () async {
          await _room?.setTyping(true);
          return 'ok';
        }),
      ),
      _btn(
        'Typing off',
        () => _run('setTyping(false)', () async {
          await _room?.setTyping(false);
          return 'ok';
        }),
      ),
      _btn(
        'React 🎉',
        () => _run('sendReaction', () async {
          await _room?.sendReaction('🎉');
          return 'ok';
        }),
      ),
      _btn(
        'Publish topic',
        () => _run('publishTopic(ping)', () async {
          await _room?.publishTopic('ping', {
            'ts': DateTime.now().millisecondsSinceEpoch,
          });
          return 'ok';
        }),
      ),
    ]),
  );

  Widget _logView() => SizedBox(
    height: 180,
    child: Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        reverse: true,
        itemCount: _log.length,
        itemBuilder: (_, i) => Text(
          _log[i],
          style: const TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}
