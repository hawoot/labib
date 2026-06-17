import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Api.loadServerUrl();
    // Native first run: no server address yet — show the setup prompt.
    if (Api.configurable && !Api.hasServer) {
      if (mounted) setState(() => _error = null);
      return;
    }
    setState(() => _error = null);
    try {
      await Api.ensureUser();
      final js = await Api.listJourneys(archived: _showArchived);
      if (mounted) setState(() => _journeys = js);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Native only: enter/update the backend's public URL. Stored on the device,
  /// so the URL changing (e.g. on a server migration) just means updating this
  /// — no rebuild.
  Future<void> _serverDialog() async {
    final controller = TextEditingController(text: Api.serverUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The public URL where your labib backend is running — '
                'the same address you open the web app at.'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://…',
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
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return;
    await Api.setServerUrl(controller.text.trim());
    setState(() {
      _journeys = null;
      _error = null;
    });
    await _load();
  }

  Future<void> _archive(String jid) async {
    await Api.archiveJourney(jid);
    await _load();
  }

  Future<void> _unarchive(String jid) async {
    await Api.unarchiveJourney(jid);
    await _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> j) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${j['title']}”?'),
        content: const Text(
            'This permanently deletes the journey and everything in it — '
            'material, questions, and your practice history. This cannot be '
            'undone.\n\nTo just hide it instead, use Archive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteJourney(j['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
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

  Future<void> _accountDialog() async {
    final codeInput = TextEditingController();
    final switched = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your code — save it to get back in on any device or '
                'browser. No password needed.'),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              child: ListTile(
                title: SelectableText(
                  Api.code ?? '…',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      letterSpacing: 2),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: Api.code == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: Api.code!));
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Code copied')),
                          );
                        },
                ),
              ),
            ),
            const Divider(height: 32),
            const Text('Have a code from another device? Enter it to switch '
                'to that account.'),
            const SizedBox(height: 8),
            TextField(
              controller: codeInput,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Enter a code',
                hintText: 'XXXX-XXXX',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (switched != true) return;
    final entered = codeInput.text.trim();
    if (entered.isEmpty) return;
    try {
      final ok = await Api.loginWithCode(entered);
      if (!mounted) return;
      if (ok) {
        setState(() => _journeys = null);
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No account with that code.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived' : 'labib'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            tooltip: _showArchived ? 'Back to active' : 'View archived',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
                _journeys = null;
              });
              _load();
            },
          ),
          if (Api.configurable)
            IconButton(
              icon: const Icon(Icons.dns_outlined),
              tooltip: 'Server address',
              onPressed: _serverDialog,
            ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Your account',
            onPressed: _accountDialog,
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton.extended(
              onPressed: _createDialog,
              icon: const Icon(Icons.add),
              label: const Text('New journey'),
            ),
      body: _body(),
    );
  }

  Widget _body() {
    if (Api.configurable && !Api.hasServer) {
      return _Centered(
        icon: Icons.dns_outlined,
        text: 'Connect to your labib server\n\n'
            'Enter the address where your backend is running to get started.',
        action: FilledButton(
            onPressed: _serverDialog,
            child: const Text('Set server address')),
      );
    }
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
      return _Centered(
        icon: _showArchived
            ? Icons.archive_outlined
            : Icons.auto_stories_outlined,
        text: _showArchived
            ? 'Nothing archived.'
            : 'What do you want to learn?\n\n'
                'Tap “New journey” to paste or upload something.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _journeys!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final j = _journeys![i] as Map<String, dynamic>;
          final intent = (j['intent'] as String?) ?? '';
          final status = j['status'] as String?;
          return Card(
            child: ListTile(
              leading: _StatusAvatar(status: status),
              title: Text(j['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(intent.isNotEmpty ? intent : 'No intent set'),
              trailing: _journeyMenu(j, status),
              onTap: () => _open(j),
            ),
          );
        },
      ),
    );
  }

  Widget _journeyMenu(Map<String, dynamic> j, String? status) {
    final jid = j['id'] as String;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(status: status),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) {
            switch (v) {
              case 'archive':
                _archive(jid);
              case 'unarchive':
                _unarchive(jid);
              case 'delete':
                _confirmDelete(j);
            }
          },
          itemBuilder: (_) => [
            if (_showArchived)
              const PopupMenuItem(
                value: 'unarchive',
                child: ListTile(
                    leading: Icon(Icons.unarchive_outlined),
                    title: Text('Unarchive'),
                    contentPadding: EdgeInsets.zero),
              )
            else
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Archive'),
                    contentPadding: EdgeInsets.zero),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small colored circle that hints at a journey's state at a glance.
class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      'ready' => (Icons.check_circle_outline, Colors.green),
      'crunching' => (Icons.hourglass_top, Colors.orange),
      _ => (Icons.auto_stories_outlined, Theme.of(context).colorScheme.primary),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      foregroundColor: color,
      child: Icon(icon),
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
  const _Centered({required this.text, this.action, this.icon});
  final String text;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 56, color: scheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
            ],
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
