import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

const Color _magenta = Color(0xFFC13BFF);

/// What the launcher hands back: which journey to drill and how intense.
class LetsGoChoice {
  const LetsGoChoice({
    required this.journeyId,
    required this.title,
    required this.intensity,
  });

  final String journeyId;
  final String title;

  /// Backend intensity key: 'on_the_go' (light, voice-friendly) or 'deep_dive'.
  final String intensity;
}

/// The in-the-moment launcher: pick intensity and scope, then go. Shown as a
/// bottom sheet from Home's "Let's go" — deliberately two quick choices, not a
/// settings screen. [journeys] are the drillable journeys (each with a
/// `progress` map), used to offer a scope and to auto-pick "most due".
Future<LetsGoChoice?> showLetsGoSheet(
  BuildContext context,
  List<Map<String, dynamic>> journeys,
) {
  return showModalBottomSheet<LetsGoChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LetsGoSheet(journeys: journeys),
  );
}

class _LetsGoSheet extends StatefulWidget {
  const _LetsGoSheet({required this.journeys});
  final List<Map<String, dynamic>> journeys;

  @override
  State<_LetsGoSheet> createState() => _LetsGoSheetState();
}

class _LetsGoSheetState extends State<_LetsGoSheet> {
  String _intensity = 'on_the_go';

  /// Selected journey id, or null = "wherever I'm most due" (auto-pick).
  String? _scopeJourneyId;

  int _due(Map<String, dynamic> j) =>
      ((j['progress'] as Map<String, dynamic>?)?['due'] as num?)?.toInt() ?? 0;

  /// The journey to actually drill given the current scope.
  Map<String, dynamic> get _target {
    if (_scopeJourneyId != null) {
      return widget.journeys.firstWhere((j) => j['id'] == _scopeJourneyId);
    }
    // Auto: most due, tie-broken by first in list.
    final sorted = [...widget.journeys]..sort((a, b) => _due(b).compareTo(_due(a)));
    return sorted.first;
  }

  void _go() {
    HapticFeedback.selectionClick();
    final t = _target;
    Navigator.pop(
      context,
      LetsGoChoice(
        journeyId: t['id'] as String,
        title: t['title'] as String? ?? 'Journey',
        intensity: _intensity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How do you want it right now?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: _IntensityCard(
                    emoji: '🎧',
                    name: 'On the go',
                    blurb: 'Quick recall. Light enough for a commute.',
                    selected: _intensity == 'on_the_go',
                    onTap: () => setState(() => _intensity = 'on_the_go'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _IntensityCard(
                    emoji: '✍️',
                    name: 'Deep dive',
                    blurb: 'Real problems. For when you’ve got a desk.',
                    selected: _intensity == 'deep_dive',
                    onTap: () => setState(() => _intensity = 'deep_dive'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Text('Focus on',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    )),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                _ScopeChip(
                  label: 'Most due',
                  selected: _scopeJourneyId == null,
                  onTap: () => setState(() => _scopeJourneyId = null),
                ),
                for (final j in widget.journeys)
                  _ScopeChip(
                    label: j['title'] as String? ?? 'Journey',
                    due: _due(j),
                    selected: _scopeJourneyId == j['id'],
                    onTap: () => setState(() => _scopeJourneyId = j['id'] as String),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  gradient: const LinearGradient(colors: [brandSeed, _magenta]),
                  boxShadow: [
                    BoxShadow(
                      color: brandSeed.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FilledButton(
                  onPressed: _go,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Let’s go  →',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntensityCard extends StatelessWidget {
  const _IntensityCard({
    required this.emoji,
    required this.name,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.card),
          gradient: selected
              ? LinearGradient(
                  colors: [
                    brandSeed.withValues(alpha: 0.28),
                    _magenta.withValues(alpha: 0.16),
                  ],
                )
              : null,
          color: selected ? null : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected
                ? brandSeed
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: Space.sm),
            Text(name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(blurb,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    )),
          ],
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.due,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? due;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          color: selected
              ? brandSeed.withValues(alpha: 0.18)
              : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected
                ? brandSeed
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                )),
            if (due != null && due! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _magenta.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('$due',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _magenta)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
