import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';

/// One editable reminder row (kept in memory while the screen is open).
class _Reminder {
  _Reminder({required this.minutes, required this.days, this.enabled = true});
  int minutes; // local minutes past midnight
  List<bool> days; // [Mon..Sun]
  bool enabled;

  TimeOfDay get time => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

/// Reminders: a simple table of times + days. The server fires a push at each
/// enabled time on the chosen days (see the worker's reminder scheduler).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  List<_Reminder> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.getSchedules();
      final items = (data['items'] as List?) ?? const [];
      _items = [
        for (final it in items)
          _Reminder(
            minutes: (it['minutes'] as num).toInt(),
            days: [for (final d in (it['days'] as List)) d == true],
            enabled: it['enabled'] == true,
          ),
      ];
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Persist the whole set (replace-all). Fire-and-forget with an error toast.
  Future<void> _save() async {
    setState(() => _saving = true);
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final payload = [
      for (final r in _items)
        {'minutes': r.minutes, 'days': r.days, 'enabled': r.enabled}
    ];
    try {
      await Api.saveSchedules(payload, offset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save reminders: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addReminder() async {
    HapticFeedback.selectionClick();
    setState(() => _items.add(_Reminder(
          minutes: 9 * 60,
          days: List<bool>.filled(7, true),
        )));
    _sort();
    await _save();
  }

  Future<void> _editTime(_Reminder r) async {
    final picked = await showTimePicker(context: context, initialTime: r.time);
    if (picked == null) return;
    setState(() => r.minutes = picked.hour * 60 + picked.minute);
    _sort();
    await _save();
  }

  void _sort() => _items.sort((a, b) => a.minutes.compareTo(b.minutes));

  String _fmt(_Reminder r) {
    final t = r.time;
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: Space.lg,
        title: const Text('Reminders'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: Space.lg),
              child: Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.lg, Space.lg, 96),
              children: [
                Text(
                  'Get a nudge to practise at the times that suit you. Each '
                  'reminder fires on the days you pick.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.lg),
                if (_items.isEmpty)
                  _EmptyState(onAdd: _addReminder)
                else ...[
                  for (final r in _items) _reminderCard(r),
                  const SizedBox(height: Space.sm),
                  OutlinedButton.icon(
                    onPressed: _addReminder,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add a time'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _reminderCard(_Reminder r) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  onTap: () => _editTime(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: Text(
                      _fmt(r),
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                  ),
                ),
                const Spacer(),
                Switch(
                  value: r.enabled,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => r.enabled = v);
                    _save();
                  },
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _items.remove(r));
                    _save();
                  },
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayChip(
                        label: _dayLabels[i],
                        on: r.days[i],
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => r.days[i] = !r.days[i]);
                          _save();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          color: on ? brandSeed.withValues(alpha: 0.20) : scheme.surfaceContainerHighest,
          border: Border.all(
            color: on ? brandSeed : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: Space.md),
          Text('No reminders yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Add a time and we’ll nudge you to practise.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a time'),
          ),
        ],
      ),
    );
  }
}
