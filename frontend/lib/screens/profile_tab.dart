import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../prefs.dart';
import '../streak.dart';
import '../theme.dart';

const Color _magenta = Color(0xFFC13BFF);

/// Profile: a temporary **Focus** (what to prioritise, for how long) and your
/// account code. Focus is the one persistent choice — set it here for a while
/// instead of being asked every time you tap "Let's go".
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _codeInput = TextEditingController();
  bool _ready = false;

  List<Map<String, dynamic>> _journeys = const [];
  final Set<String> _selected = {};
  Duration _duration = const Duration(days: 1);

  List<String> _focusIds = const [];
  DateTime? _focusUntil;

  int _goal = Streak.defaultGoal;
  int _window = Streak.defaultWindow;

  static const _durations = <(String, Duration)>[
    ('3 hours', Duration(hours: 3)),
    ('1 day', Duration(days: 1)),
    ('2 days', Duration(days: 2)),
    ('1 week', Duration(days: 7)),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Api.ensureUser();
    final js = await Api.listJourneys();
    _focusIds = await Prefs.activeFocus();
    _focusUntil = await Prefs.focusUntil();
    _goal = await Streak.goal();
    _window = await Streak.window();
    if (mounted) {
      setState(() {
        _journeys = [for (final j in js) Map<String, dynamic>.from(j as Map)];
        _ready = true;
      });
    }
  }

  Future<void> _startFocus() async {
    if (_selected.isEmpty) return;
    HapticFeedback.selectionClick();
    await Prefs.setFocus(_selected.toList(), _duration);
    _selected.clear();
    await _load();
  }

  Future<void> _endFocus() async {
    HapticFeedback.lightImpact();
    await Prefs.clearFocus();
    await _load();
  }

  String get _remaining {
    final left = _focusUntil!.difference(DateTime.now());
    if (left.inHours >= 24) {
      final d = (left.inHours / 24).floor();
      return '$d day${d == 1 ? '' : 's'} left';
    }
    if (left.inHours >= 1) return '${left.inHours}h left';
    return '${left.inMinutes}m left';
  }

  void _copyCode() {
    if (Api.code == null) return;
    Clipboard.setData(ClipboardData(text: Api.code!));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  Future<void> _switch() async {
    final entered = _codeInput.text.trim();
    if (entered.isEmpty) return;
    try {
      final ok = await Api.loginWithCode(entered);
      if (!mounted) return;
      if (ok) {
        _codeInput.clear();
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Switched account. Pull Home to refresh.')));
        }
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(titleSpacing: Space.lg, title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 96),
        children: [
          // --- Focus -------------------------------------------------------
          Text('Focus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Zero in on a few journeys for a set time — handy before an exam. '
            'It reverts automatically when the time’s up.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          if (_focusIds.isNotEmpty && _focusUntil != null)
            _activeFocusCard()
          else
            _focusEditor(),

          const Divider(height: Space.xxl + Space.lg),

          // --- Daily goal & streak window ---------------------------------
          Text('Daily goal & streak',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Your streak grows each day you hit the goal. The window is your '
            'cushion — bank ahead before a break, or catch up after one, up to '
            'this many days either way.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          _Stepper(
            label: 'Questions a day',
            value: _goal,
            min: 1,
            max: 50,
            onChanged: (v) async {
              await Streak.setGoal(v);
              setState(() => _goal = v);
            },
          ),
          const SizedBox(height: Space.sm),
          _Stepper(
            label: 'Window (days)',
            value: _window,
            min: 1,
            max: 30,
            onChanged: (v) async {
              await Streak.setWindow(v);
              setState(() => _window = v);
            },
          ),

          const Divider(height: Space.xxl + Space.lg),

          // --- Account -----------------------------------------------------
          Text('Your code', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Save it to get back in on any device or browser. No password needed.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          Card(
            child: ListTile(
              title: SelectableText(
                _ready ? (Api.code ?? '—') : '…',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 22, letterSpacing: 2),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy',
                onPressed: Api.code == null ? null : _copyCode,
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          Text('Switch account',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Have a code from another device? Enter it to switch to that account.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _codeInput,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Enter a code', hintText: 'XXXX-XXXX'),
            onSubmitted: (_) => _switch(),
          ),
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _switch, child: const Text('Switch')),
          ),
        ],
      ),
    );
  }

  Widget _activeFocusCard() {
    final scheme = Theme.of(context).colorScheme;
    final titles = [
      for (final j in _journeys)
        if (_focusIds.contains(j['id'])) j['title'] as String? ?? 'Journey'
    ];
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        color: _magenta.withValues(alpha: 0.10),
        border: Border.all(color: _magenta.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.center_focus_strong_outlined,
                  size: 20, color: _magenta),
              const SizedBox(width: Space.sm),
              Text('Focus active · $_remaining',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _magenta)),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            titles.isEmpty ? 'Selected journeys' : titles.join(' · '),
            style: TextStyle(color: scheme.onSurface),
          ),
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: _endFocus,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('End focus now'),
          ),
        ],
      ),
    );
  }

  Widget _focusEditor() {
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(Space.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_journeys.isEmpty) {
      return Text('Create a journey first, then you can focus on it.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Journeys',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final j in _journeys)
              _ChoiceChip(
                label: j['title'] as String? ?? 'Journey',
                selected: _selected.contains(j['id']),
                onTap: () => setState(() {
                  final id = j['id'] as String;
                  _selected.contains(id)
                      ? _selected.remove(id)
                      : _selected.add(id);
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text('For how long',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final (label, dur) in _durations)
              _ChoiceChip(
                label: label,
                selected: _duration == dur,
                onTap: () => setState(() => _duration = dur),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selected.isEmpty ? null : _startFocus,
            child: const Text('Start focus'),
          ),
        ),
      ],
    );
  }
}

/// A simple −/+ number stepper for the daily goal and window settings.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 32,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: brandSeed),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}
