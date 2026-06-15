import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

/// Demonstrates the reactive presence widgets (the new high-level API) instead
/// of driving the [PresenceManager] / [InstantRoom] manually:
///   - [CursorOverlay]      multiplayer cursors
///   - [PresenceBuilder]    live peer count
///   - [TypingIndicatorBuilder] typing indicator
///   - [ReactionsBuilder]   live emoji reactions
///   - [TopicListener]      ephemeral topic events ("ping")
class CollabWidgetsPage extends StatefulWidget {
  const CollabWidgetsPage({super.key});

  @override
  State<CollabWidgetsPage> createState() => _CollabWidgetsPageState();
}

class _CollabWidgetsPageState extends State<CollabWidgetsPage> {
  static const _roomId = 'demo-room';
  static const _reactionEmojis = ['👍', '❤️', '🎉', '😂', '🔥'];

  final _textController = TextEditingController();
  Timer? _typingTimer;
  InstantRoom? _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _room ??= InstantProvider.of(context).presence.joinRoom(_roomId);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _textController.dispose();
    _room?.setTyping(false);
    super.dispose();
  }

  void _onTyping() {
    _typingTimer?.cancel();
    _room?.setTyping(true);
    _typingTimer = Timer(
      const Duration(seconds: 2),
      () => _room?.setTyping(false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CursorOverlay(
      roomId: _roomId,
      userName: 'You',
      userColor: '#E91E63',
      child: TopicListener(
        roomId: _roomId,
        topic: 'ping',
        onEvent: (data) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ping received: ${data['message'] ?? 'ping'}'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Collaboration Widgets',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Move your cursor around — open in another window to see peers.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // Live peer count via PresenceBuilder.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PresenceBuilder(
                    roomId: _roomId,
                    initialPresence: const {'name': 'User'},
                    builder: (context, room, peers) {
                      return Row(
                        children: [
                          const Icon(Icons.group, color: Colors.green),
                          const SizedBox(width: 12),
                          Text(
                            '${peers.length} online',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Reactions.
              const Text(
                'Reactions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final emoji in _reactionEmojis)
                            ElevatedButton(
                              onPressed: () => _room?.sendReaction(emoji),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Live reactions:'),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ReactionsBuilder(
                          roomId: _roomId,
                          builder: (context, reactions) {
                            if (reactions.isEmpty) {
                              return Text(
                                'No reactions yet — tap an emoji above.',
                                style: TextStyle(color: Colors.grey[600]),
                              );
                            }
                            return Wrap(
                              spacing: 4,
                              children: [
                                for (final r in reactions)
                                  Text(
                                    r.emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Typing indicator + text field.
              const Text(
                'Typing indicator',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _textController,
                        decoration: const InputDecoration(
                          hintText: 'Start typing…',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _onTyping(),
                      ),
                      const SizedBox(height: 8),
                      TypingIndicatorBuilder(
                        roomId: _roomId,
                        builder: (context, typing) {
                          if (typing.isEmpty) {
                            return Text(
                              'Nobody else is typing.',
                              style: TextStyle(color: Colors.grey[600]),
                            );
                          }
                          return Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text('${typing.length} typing…'),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Topic broadcast (handled by TopicListener above).
              OutlinedButton.icon(
                onPressed: () {
                  InstantProvider.of(context).presence.publishTopic(
                    _roomId,
                    'ping',
                    {'message': 'Hello from a peer!'},
                  );
                },
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Broadcast "ping" topic'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
