import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../prefs.dart';
import '../streak.dart';
import '../theme.dart';
import 'question_chat.dart';

const Color _magenta = Color(0xFFC13BFF);

/// A study session: a sequence of questions, each worked through as a chat with
/// labib. [intensity] tunes which kinds of questions the server hands back and
/// can be switched mid-session from the pill.
class DrillScreen extends StatefulWidget {
  const DrillScreen({
    super.key,
    required this.journeyId,
    required this.title,
    this.intensity,
  });
  final String journeyId;
  final String title;
  final String? intensity;

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  List<dynamic>? _items;
  int _index = 0;
  int _correct = 0;
  int _answered = 0;
  int _skipped = 0;
  String? _error;
  String? _intensity;

  String get _intensityLabel => switch (_intensity) {
        'on_the_go' => 'On the go',
        'short_drill' => 'Short drill',
        'deep_dive' => 'Deep dive',
        _ => 'Mixed',
      };

  @override
  void initState() {
    super.initState();
    _intensity = widget.intensity;
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items =
          await Api.getSession(widget.journeyId, intensity: _intensity);
      setState(() {
        _items = items;
        _index = 0;
        _correct = 0;
        _answered = 0;
        _skipped = 0;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _changeIntensity(String value) async {
    if (value == _intensity) return;
    HapticFeedback.selectionClick();
    setState(() => _intensity = value);
    await Prefs.setIntensity(value);
    await _load();
  }

  void _onSolved(double score) {
    _answered++;
    if (score >= 0.6) _correct++;
    Streak.recordAnswered(1); // counts toward the daily goal
  }

  void _skip() {
    HapticFeedback.selectionClick();
    setState(() {
      _skipped++;
      _index++;
    });
  }

  void _next() => setState(() => _index++);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _items?.length ?? 0;
    final showStrip = _items != null && _items!.isNotEmpty && _index < total;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (showStrip)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Center(
                child: _IntensitySwitcher(
                  label: _intensityLabel,
                  current: _intensity,
                  onChanged: _changeIntensity,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: total == 0
              ? const SizedBox(height: 3)
              : LinearProgressIndicator(
                  value: (_index / total).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(brandSeed),
                ),
        ),
      ),
      body: _body(scheme, total),
    );
  }

  Widget _body(ColorScheme scheme, int total) {
    if (_error != null) {
      return _centered('Something went wrong:\n$_error',
          action: FilledButton(onPressed: _load, child: const Text('Retry')));
    }
    if (_items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items!.isEmpty) {
      return _centered('Nothing due right now 🎉\nCome back a bit later.',
          action: FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('Back')));
    }
    if (_index >= total) return _summary();

    final item = _items![_index] as Map<String, dynamic>;
    return Column(
      children: [
        // Thin context strip: which skill, and where you are.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                child: Text(item['skill_name'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ),
              Text('${_index + 1} / $total',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: QuestionChat(
            key: ValueKey('${item['question_id']}_$_index'),
            journeyId: widget.journeyId,
            question: item,
            onSolved: _onSolved,
            onNext: _next,
            onSkip: _skip,
          ),
        ),
      ],
    );
  }

  Widget _summary() {
    return _centered(
      'Session complete 🎉',
      subtitle: _answered == 0
          ? 'You skipped everything this round.'
          : 'You got $_correct of $_answered right'
              '${_skipped > 0 ? ' · skipped $_skipped' : ''}.',
      action: Wrap(spacing: Space.sm, children: [
        OutlinedButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done')),
        FilledButton(onPressed: _load, child: const Text('Another round')),
      ]),
    );
  }

  Widget _centered(String text, {String? subtitle, Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: Space.sm),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action],
          ],
        ),
      ),
    );
  }
}

/// The intensity pill — tap to switch intensity mid-session.
class _IntensitySwitcher extends StatelessWidget {
  const _IntensitySwitcher({
    required this.label,
    required this.current,
    required this.onChanged,
  });

  final String label;
  final String? current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change intensity',
      onSelected: onChanged,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control)),
      itemBuilder: (_) => [
        _item('on_the_go', '🎧  On the go'),
        _item('short_drill', '⚡  Short drill'),
        _item('deep_dive', '✍️  Deep dive'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            brandSeed.withValues(alpha: 0.22),
            _magenta.withValues(alpha: 0.14),
          ]),
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: brandSeed.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: brandSeed)),
            const Icon(Icons.expand_more, size: 14, color: brandSeed),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(String value, String text) => PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Expanded(child: Text(text)),
            if (current == value)
              const Icon(Icons.check, size: 18, color: brandSeed),
          ],
        ),
      );
}
