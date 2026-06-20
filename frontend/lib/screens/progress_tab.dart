import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

const Color _magenta = Color(0xFFC13BFF);

/// Progress: an at-a-glance read on how you're doing across every journey —
/// overall mastery, how much is due, and a per-journey breakdown. Streaks and
/// mastery-over-time charts land in a later step.
class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  List<Map<String, dynamic>>? _journeys;
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
      final js = await Api.journeysWithProgress();
      if (mounted) setState(() => _journeys = js);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Only journeys that actually have skills count toward the totals.
  List<Map<String, dynamic>> get _withSkills => [
        for (final j in _journeys ?? const [])
          if (((j['progress'] as Map<String, dynamic>?)?['skill_count'] as num?
                      ?? 0) >
                  0)
            j
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: Space.lg, title: const Text('Progress')),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text('$_error')),
          const SizedBox(height: Space.lg),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }
    if (_journeys == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final tracked = _withSkills;
    if (tracked.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.insights_outlined,
              size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: Space.md),
          Center(
            child: Text('No progress yet',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: Space.xs),
          Center(
            child: Text('Drill a journey and it’ll show up here.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ],
      );
    }

    var mastered = 0, totalSkills = 0, due = 0;
    for (final j in tracked) {
      final p = j['progress'] as Map<String, dynamic>;
      mastered += (p['mastered'] as num?)?.toInt() ?? 0;
      totalSkills += (p['skill_count'] as num?)?.toInt() ?? 0;
      due += (p['due'] as num?)?.toInt() ?? 0;
    }
    final pct = totalSkills == 0 ? 0.0 : mastered / totalSkills;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
      children: [
        _OverallCard(pct: pct, mastered: mastered, total: totalSkills, due: due),
        const SizedBox(height: Space.xl),
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text('By journey',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  )),
        ),
        for (final j in tracked) ...[
          _JourneyProgress(journey: j),
          const SizedBox(height: Space.md),
        ],
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard(
      {required this.pct,
      required this.mastered,
      required this.total,
      required this.due});

  final double pct;
  final int mastered;
  final int total;
  final int due;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card + 6),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            brandSeed.withValues(alpha: 0.16),
            _magenta.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall mastery',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
          const SizedBox(height: Space.xs),
          Text('${(pct * 100).round()}%',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5,
                  )),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(brandSeed),
            ),
          ),
          const SizedBox(height: Space.md),
          Text('$mastered of $total skills mastered · $due to revisit',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _JourneyProgress extends StatelessWidget {
  const _JourneyProgress({required this.journey});
  final Map<String, dynamic> journey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = journey['progress'] as Map<String, dynamic>;
    final mastered = (p['mastered'] as num?)?.toInt() ?? 0;
    final total = (p['skill_count'] as num?)?.toInt() ?? 0;
    final due = (p['due'] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : mastered / total;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(journey['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text('${(pct * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: brandSeed,
                        fontWeight: FontWeight.w800,
                      )),
            ],
          ),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(brandSeed),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            due > 0 ? '$due to revisit' : 'Up to date',
            style: TextStyle(
              color: due > 0 ? _magenta : scheme.onSurfaceVariant,
              fontWeight: due > 0 ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
