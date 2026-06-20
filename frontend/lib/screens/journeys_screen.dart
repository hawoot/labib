import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/app_motion.dart';
import '../widgets/pressable.dart';
import '../widgets/skeleton.dart';
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
    setState(() => _error = null);
    try {
      await Api.ensureUser();
      final js = await Api.listJourneys(archived: _showArchived);
      if (mounted) setState(() => _journeys = js);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _archive(String jid) async {
    HapticFeedback.lightImpact();
    await Api.archiveJourney(jid);
    await _load();
  }

  Future<void> _unarchive(String jid) async {
    HapticFeedback.lightImpact();
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
    HapticFeedback.selectionClick();
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
            const SizedBox(height: Space.md),
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
      AppPageRoute(builder: (_) => JourneyScreen(journey: j)),
    ).then((_) => _load());
  }

  Future<void> _accountDialog() async {
    HapticFeedback.selectionClick();
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
            const SizedBox(height: Space.sm),
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
            const SizedBox(height: Space.sm),
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
        titleSpacing: Space.lg,
        title: Text(_showArchived ? 'Archived' : 'labib'),
        actions: [
          IconButton(
            icon: Icon(_showArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            tooltip: _showArchived ? 'Back to active' : 'View archived',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _showArchived = !_showArchived;
                _journeys = null;
              });
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Your account',
            onPressed: _accountDialog,
          ),
          const SizedBox(width: Space.xs),
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
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Something went wrong',
        message: '$_error',
        action: FilledButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_journeys == null) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: Space.md),
        itemBuilder: (_, __) => const SkeletonCard(),
      );
    }
    if (_journeys!.isEmpty) {
      return _EmptyState(
        icon: _showArchived
            ? Icons.archive_outlined
            : Icons.auto_stories_outlined,
        title: _showArchived ? 'Nothing archived' : 'What do you want to learn?',
        message: _showArchived
            ? 'Journeys you archive will show up here.'
            : 'Start a journey, then paste or upload something to learn from.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
        itemCount: _journeys!.length,
        separatorBuilder: (_, __) => const SizedBox(height: Space.md),
        itemBuilder: (_, i) {
          final j = _journeys![i] as Map<String, dynamic>;
          final jid = j['id'] as String;
          return Dismissible(
            key: ValueKey(jid),
            direction: DismissDirection.endToStart,
            background: _swipeBackground(),
            confirmDismiss: (_) async {
              // Do the work, but don't remove the tile ourselves — _load()
              // rebuilds the list, which avoids the "dismissed but still in
              // tree" assertion.
              if (_showArchived) {
                await _unarchive(jid);
              } else {
                await _archive(jid);
              }
              return false;
            },
            child: _JourneyCard(
              journey: j,
              showArchived: _showArchived,
              onTap: () => _open(j),
              onArchive: () => _archive(jid),
              onUnarchive: () => _unarchive(jid),
              onDelete: () => _confirmDelete(j),
            ),
          );
        },
      ),
    );
  }

  Widget _swipeBackground() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Space.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Icon(
        _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// One journey, as a tappable card with a status hint and a context menu.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.journey,
    required this.showArchived,
    required this.onTap,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
  });

  final Map<String, dynamic> journey;
  final bool showArchived;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final intent = (journey['intent'] as String?) ?? '';
    final status = journey['status'] as String?;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(Radii.card),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            _StatusAvatar(status: status),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          journey['title'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _StatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    intent.isNotEmpty ? intent : 'No intent set',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            _JourneyMenu(
              showArchived: showArchived,
              onArchive: onArchive,
              onUnarchive: onUnarchive,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyMenu extends StatelessWidget {
  const _JourneyMenu({
    required this.showArchived,
    required this.onArchive,
    required this.onUnarchive,
    required this.onDelete,
  });

  final bool showArchived;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control)),
      onSelected: (v) {
        switch (v) {
          case 'archive':
            onArchive();
          case 'unarchive':
            onUnarchive();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        if (showArchived)
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
    );
  }
}

/// A small rounded badge that hints at a journey's state at a glance.
class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final palette = StatusPalette(Theme.of(context).brightness);
    final (icon, color) = switch (status) {
      'ready' => (Icons.check_circle_outline, palette.success),
      'crunching' => (Icons.hourglass_top, palette.warning),
      _ => (Icons.auto_stories_outlined, Theme.of(context).colorScheme.primary),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final palette = StatusPalette(Theme.of(context).brightness);
    final s = status ?? 'new';
    final (label, color) = switch (s) {
      'ready' => ('Ready', palette.success),
      'crunching' => ('Crunching', palette.warning),
      _ => ('New', palette.neutral),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 34, color: scheme.primary),
            ),
            const SizedBox(height: Space.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}
