import 'dart:async';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'instant_builder.dart';
import 'presence.dart';

/// Reactive equivalent of InstantDB's React `usePresence` / `room.usePresence`.
///
/// Joins [roomId] when mounted, publishes [initialPresence] (if any), and
/// rebuilds whenever any peer's presence changes. The [InstantRoom] handle is
/// passed to [builder] so children can call `room.setPresence(...)`.
///
/// ```dart
/// PresenceBuilder(
///   roomId: 'doc-42',
///   initialPresence: {'name': 'Alice'},
///   builder: (context, room, peers) => Text('${peers.length} online'),
/// )
/// ```
class PresenceBuilder extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic>? initialPresence;
  final Widget Function(
    BuildContext context,
    InstantRoom room,
    Map<String, PresenceData> peers,
  )
  builder;

  const PresenceBuilder({
    super.key,
    required this.roomId,
    this.initialPresence,
    required this.builder,
  });

  @override
  State<PresenceBuilder> createState() => _PresenceBuilderState();
}

class _PresenceBuilderState extends State<PresenceBuilder> {
  InstantRoom? _room;
  Signal<Map<String, PresenceData>>? _presence;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_room == null) {
      final db = InstantProvider.of(context);
      _room = db.presence.joinRoom(
        widget.roomId,
        initialPresence: widget.initialPresence,
      );
      _presence = _room!.getPresence();
    }
  }

  @override
  void dispose() {
    _room?.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return widget.builder(context, _room!, _presence?.value ?? const {});
    });
  }
}

/// Reactive equivalent of InstantDB's React `useTopicEffect`.
///
/// Subscribes to ephemeral [topic] messages in [roomId] and invokes [onEvent]
/// for each one. Renders [child] unchanged (it is a side-effect widget). Use
/// the [InstantRoom] from [PresenceBuilder] or `db.presence` to publish.
///
/// ```dart
/// TopicListener(
///   roomId: 'doc-42',
///   topic: 'emoji',
///   onEvent: (data) => _showFloatingEmoji(data['emoji']),
///   child: const Editor(),
/// )
/// ```
class TopicListener extends StatefulWidget {
  final String roomId;
  final String topic;
  final void Function(Map<String, dynamic> data) onEvent;
  final Widget child;

  const TopicListener({
    super.key,
    required this.roomId,
    required this.topic,
    required this.onEvent,
    required this.child,
  });

  @override
  State<TopicListener> createState() => _TopicListenerState();
}

class _TopicListenerState extends State<TopicListener> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= _subscribe();
  }

  StreamSubscription<Map<String, dynamic>> _subscribe() {
    final db = InstantProvider.of(context);
    db.presence.joinRoom(widget.roomId);
    return db.presence
        .subscribeTopic(widget.roomId, widget.topic)
        .listen(widget.onEvent);
  }

  @override
  void didUpdateWidget(TopicListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId || oldWidget.topic != widget.topic) {
      _sub?.cancel();
      _sub = _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rebuilds with the set of peers currently typing in [roomId].
///
/// Equivalent to InstantDB's typing-indicator presence pattern.
///
/// ```dart
/// TypingIndicatorBuilder(
///   roomId: 'doc-42',
///   builder: (context, typing) =>
///       typing.isEmpty ? const SizedBox() : Text('${typing.length} typing…'),
/// )
/// ```
class TypingIndicatorBuilder extends StatefulWidget {
  final String roomId;
  final Widget Function(BuildContext context, Map<String, DateTime> typing)
  builder;

  const TypingIndicatorBuilder({
    super.key,
    required this.roomId,
    required this.builder,
  });

  @override
  State<TypingIndicatorBuilder> createState() => _TypingIndicatorBuilderState();
}

class _TypingIndicatorBuilderState extends State<TypingIndicatorBuilder> {
  Signal<Map<String, DateTime>>? _typing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_typing == null) {
      final db = InstantProvider.of(context);
      final room = db.presence.joinRoom(widget.roomId);
      _typing = room.getTyping();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return widget.builder(context, _typing?.value ?? const {});
    });
  }
}

/// Rebuilds with the live list of reactions broadcast in [roomId].
///
/// ```dart
/// ReactionsBuilder(
///   roomId: 'doc-42',
///   builder: (context, reactions) => Wrap(
///     children: [for (final r in reactions) Text(r.emoji)],
///   ),
/// )
/// ```
class ReactionsBuilder extends StatefulWidget {
  final String roomId;
  final Widget Function(BuildContext context, List<ReactionData> reactions)
  builder;

  const ReactionsBuilder({
    super.key,
    required this.roomId,
    required this.builder,
  });

  @override
  State<ReactionsBuilder> createState() => _ReactionsBuilderState();
}

class _ReactionsBuilderState extends State<ReactionsBuilder> {
  Signal<List<ReactionData>>? _reactions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reactions == null) {
      final db = InstantProvider.of(context);
      final room = db.presence.joinRoom(widget.roomId);
      _reactions = room.getReactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return widget.builder(context, _reactions?.value ?? const []);
    });
  }
}

/// Multiplayer cursor layer — Flutter equivalent of InstantDB's `<Cursors>`.
///
/// Wrap any content in [CursorOverlay]; it tracks the local pointer, publishes
/// it to [roomId], and paints every peer's cursor on top. Provide [userName] /
/// [userColor] to label the local cursor, and override [cursorBuilder] to
/// customize how remote cursors render.
///
/// ```dart
/// CursorOverlay(
///   roomId: 'doc-42',
///   userName: 'Alice',
///   userColor: '#E91E63',
///   child: const Canvas(),
/// )
/// ```
class CursorOverlay extends StatefulWidget {
  final String roomId;
  final Widget child;
  final String? userName;
  final String? userColor;

  /// Builds the visual for a single remote cursor. Defaults to a pointer
  /// triangle plus an optional name label tinted with the peer's color.
  final Widget Function(BuildContext context, CursorData cursor)? cursorBuilder;

  const CursorOverlay({
    super.key,
    required this.roomId,
    required this.child,
    this.userName,
    this.userColor,
    this.cursorBuilder,
  });

  @override
  State<CursorOverlay> createState() => _CursorOverlayState();
}

class _CursorOverlayState extends State<CursorOverlay> {
  InstantRoom? _room;
  Signal<Map<String, CursorData>>? _cursors;
  String? _selfId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_room == null) {
      final db = InstantProvider.of(context);
      _room = db.presence.joinRoom(widget.roomId);
      _cursors = _room!.getCursors();
      _selfId = db.auth.currentUser.value?.id ?? db.getAnonymousUserId();
    }
  }

  void _onHover(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    _room?.updateCursor(
      x: local.dx,
      y: local.dy,
      userName: widget.userName,
      userColor: widget.userColor,
    );
  }

  @override
  void dispose() {
    _room?.removeCursor();
    super.dispose();
  }

  Widget _defaultCursor(BuildContext context, CursorData c) {
    final color = _parseColor(c.userColor) ?? Theme.of(context).primaryColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.navigation, size: 18, color: color),
        if (c.userName != null)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              c.userName!,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _onHover,
      child: Stack(
        children: [
          widget.child,
          Watch((context) {
            final cursors = _cursors?.value ?? const <String, CursorData>{};
            return Stack(
              children: [
                for (final entry in cursors.entries)
                  if (entry.key != _selfId)
                    Positioned(
                      left: entry.value.x,
                      top: entry.value.y,
                      child: IgnorePointer(
                        child:
                            widget.cursorBuilder?.call(context, entry.value) ??
                            _defaultCursor(context, entry.value),
                      ),
                    ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
