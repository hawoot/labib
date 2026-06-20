import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/app_motion.dart';
import '../widgets/pressable.dart';
import '../widgets/skeleton.dart';
import 'drill_screen.dart';
import 'journey_screen.dart';

/// Magenta companion to the brand violet — used only for the "today" gradient
/// accents (hero, Let's go), matching the landing screen.
const Color _magenta = Color(0xFFC13BFF);

/// Home: a "today" hero (what's due across all your journeys + Let's go) over
/// the list of journeys. The journey list keeps its full management (create,
/// archive, delete); account/switching now lives in the Profile tab.
class JourneysScreen extends StatefulWidget {
  const JourneysScreen({super.key});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  List<Map<String, dynamic>>? _journeys;
  String? _error;
  bool _showArchived = false;

  /// Total skills due across all active journeys — the daily driver shown in
  /// the hero. Null while loading or in the archived view.
  int? get _dueTotal {
    if (_journeys == null || _showArchived) return null;
    var n = 0;
    for (final j in _journeys!) {
      final p = j['progress'] as Map<String, dynamic>?;
      if (p != null) n += (p['due'] as num?)?.toInt() ?? 0;
    }
    return n;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Api.ensureUser();
      final js = _showArchived
          ? [
              for (final j in await Api.listJourneys(archived: true))
                Map<String, dynamic>.from(j as Map)
            ]
          : await Api.journeysWithProgress();
      if (mounted) setState(() => _journeys = js);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// "Let's go": start the most-pressing session right now. Picks the active
  /// journey with the most due skills; if nothing's due, the first journey
  /// that's ready to drill. (A true cross-journey session comes later.)
  void _letsGo() {
    HapticFeedback.selectionClick();
    final active = _journeys ?? const [];
    Map<String, dynamic>? best;
    var bestDue = -1;
    for (final j in active) {
      final p = j['progress'] as Map<String, dynamic>?;
      final due = (p?['due'] as num?)?.toInt() ?? 0;
      final ready = j['status'] == 'ready' || (p?['skill_count'] as num? ?? 0) > 0;
      if (!ready) continue;
      if (due > bestDue) {
        bestDue = due;
        best = j;
      }
    }
    if (best == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add material to a journey first, then come back to drill.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => DrillScreen(
          journeyId: best!['id'] as String,
          title: best['title'] as String? ?? 'Journey',
        ),
      ),
    ).then((_) => _load());
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
        children: [
          if (!_showArchived) ...[
            _TodayHero(due: _dueTotal, onLetsGo: _letsGo),
            const SizedBox(height: Space.xl),
            Padding(
              padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
              child: Text(
                'Your journeys',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
          for (final j in _journeys!) ...[
            Dismissible(
              key: ValueKey(j['id']),
              direction: DismissDirection.endToStart,
              background: _swipeBackground(),
              confirmDismiss: (_) async {
                final jid = j['id'] as String;
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
                onArchive: () => _archive(j['id'] as String),
                onUnarchive: () => _unarchive(j['id'] as String),
                onDelete: () => _confirmDelete(j),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
        ],
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

/// The "today" hero: how much is due across all journeys right now, with the
/// one big action — Let's go. Uses the violet→magenta brand gradient.
class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.due, required this.onLetsGo});

  /// Total due across journeys; null while progress is still loading.
  final int? due;
  final VoidCallback onLetsGo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = due;
    final headline = n == null
        ? '…'
        : n == 0
            ? 'All caught up'
            : '$n';
    final sub = n == null
        ? 'Checking what’s due…'
        : n == 0
            ? 'Nothing due right now — get ahead with a quick session.'
            : 'to revisit today, across your journeys';

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card + 6),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            brandSeed.withValues(alpha: 0.18),
            _magenta.withValues(alpha: 0.10),
            scheme.surface.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  height: 1.0,
                ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            sub,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.control),
                gradient: const LinearGradient(
                  colors: [brandSeed, _magenta],
                ),
                boxShadow: [
                  BoxShadow(
                    color: brandSeed.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: onLetsGo,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Let’s go  →',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One journey, as a tappable card. When progress is available it shows a
/// mastery bar and what's due; otherwise it falls back to the intent line.
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
    final progress = journey['progress'] as Map<String, dynamic>?;
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
                  if (progress != null && (progress['skill_count'] as num? ?? 0) > 0)
                    _ProgressLine(progress: progress)
                  else
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

/// Mastery bar + a "N to revisit" hint, shown on journeys that have skills.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});
  final Map<String, dynamic> progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mastered = (progress['mastered'] as num?)?.toInt() ?? 0;
    final total = (progress['skill_count'] as num?)?.toInt() ?? 0;
    final due = (progress['due'] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : (mastered / total).clamp(0.0, 1.0);
    final label = due > 0 ? '$due to revisit' : 'Up to date';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation(brandSeed),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(pct * 100).round()}% mastered · $label',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: due > 0 ? _magenta : scheme.onSurfaceVariant,
                fontWeight: due > 0 ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ],
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
