import 'package:flutter/material.dart';

import '../api.dart';
import 'journey_screen.dart';

/// Home: the list of journeys, with a proactive empty state.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  List<dynamic>? _journeys;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Api.ensureUser();
      final js = await Api.listJourneys();
      if (mounted) setState(() => _journeys = js);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _createDialog() async {
    final title = TextEditingController();
    final intent = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New journey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'e.g. Calculus'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: intent,
              decoration: const InputDecoration(
                labelText: 'How do you want to learn it?',
                hintText: 'e.g. A-level exam prep',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final j = await Api.createJourney(title.text.trim(), intent.text.trim());
      await _load();
      _open(j);
    }
  }

  void _open(Map<String, dynamic> j) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JourneyScreen(journey: j)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('labib')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createDialog,
        icon: const Icon(Icons.add),
        label: const Text('New journey'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Centered(
        text: 'Something went wrong:\n$_error',
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_journeys == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_journeys!.isEmpty) {
      return const _Centered(
        text: 'What do you want to learn?\n\n'
            'Tap “New journey” to paste or upload something.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _journeys!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final j = _journeys![i] as Map<String, dynamic>;
          final intent = (j['intent'] as String?) ?? '';
          return Card(
            child: ListTile(
              title: Text(j['title'] ?? ''),
              subtitle: Text(intent.isNotEmpty ? intent : 'No intent set'),
              trailing: _StatusChip(status: j['status'] as String?),
              onTap: () => _open(j),
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final s = status ?? 'new';
    final color = switch (s) {
      'ready' => Colors.green,
      'crunching' => Colors.orange,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(s, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
