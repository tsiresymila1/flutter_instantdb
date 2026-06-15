import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

/// Demonstrates the aggregation helpers: [InstantDB.count] and
/// [InstantDB.aggregate] (with grouping).
class AggregationsPage extends StatefulWidget {
  const AggregationsPage({super.key});

  @override
  State<AggregationsPage> createState() => _AggregationsPageState();
}

class _AggregationsPageState extends State<AggregationsPage> {
  bool _loading = false;
  String? _error;

  int? _total;
  int? _pending;
  List<Map<String, dynamic>> _byCompleted = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_total == null && !_loading) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final db = InstantProvider.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Total count of todos.
      final total = await db.count('todos');

      // Filtered count: only pending (not completed) todos.
      final pending = await db.count('todos', where: {'completed': false});

      // Grouped aggregate: count of todos per `completed` value.
      final byCompleted = await db.aggregate(
        'todos',
        aggregates: {'count': '*'},
        groupBy: ['completed'],
      );

      if (!mounted) return;
      setState(() {
        _total = total;
        _pending = pending;
        _byCompleted = byCompleted;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _insertRandomTodo() async {
    final db = InstantProvider.of(context);
    final rng = Random();
    final n = rng.nextInt(10000);

    try {
      await db.transact(
        db.create('todos', {
          'id': db.id(),
          'text': 'Random todo #$n',
          'completed': rng.nextBool(),
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to insert todo: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Aggregations',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Live counts and grouped aggregates over the "todos" namespace.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Error: $_error',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            ),

          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Total todos',
                  value: _total,
                  loading: _loading,
                  color: Colors.blue,
                  icon: Icons.checklist,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Pending',
                  value: _pending,
                  loading: _loading,
                  color: Colors.orange,
                  icon: Icons.pending_actions,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text(
            'Grouped by completed',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_loading && _byCompleted.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_byCompleted.isEmpty)
            Text('No groups yet.', style: TextStyle(color: Colors.grey[600]))
          else
            ..._byCompleted.map((row) {
              final completed = row['completed'] == true;
              final count = row['count'];
              return Card(
                child: ListTile(
                  leading: Icon(
                    completed ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: completed ? Colors.green : Colors.grey,
                  ),
                  title: Text(completed ? 'Completed' : 'Not completed'),
                  trailing: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _insertRandomTodo,
                  icon: const Icon(Icons.add),
                  label: const Text('Insert random todo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int? value;
  final bool loading;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.loading,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 4),
            loading && value == null
                ? const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '${value ?? '-'}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
