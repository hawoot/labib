import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';

const Color _magenta = Color(0xFFC13BFF);

/// A study session: one question at a time, answer -> AI feedback -> next.
/// [intensity] ('on_the_go' / 'deep_dive') is chosen in the launcher and tunes
/// which kinds of questions the server hands back.
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
  int _skipped = 0;
  final _answer = TextEditingController();
  Map<String, dynamic>? _result; // grading of the current question
  bool _submitting = false;
  String? _error;

  String get _intensityLabel => switch (widget.intensity) {
        'on_the_go' => 'On the go',
        'deep_dive' => 'Deep dive',
        _ => 'Mixed',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items =
          await Api.getSession(widget.journeyId, intensity: widget.intensity);
      setState(() {
        _items = items;
        _index = 0;
        _correct = 0;
        _skipped = 0;
        _result = null;
        _answer.clear();
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _submit() async {
    final item = _items![_index] as Map<String, dynamic>;
    if (_answer.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final res = await Api.submitAttempt(
          widget.journeyId, item['question_id'], _answer.text.trim());
      HapticFeedback.lightImpact();
      setState(() {
        _result = res;
        if (res['correct'] == true) _correct++;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Skip this one — no penalty. (It stays due, so it'll come back around.)
  void _skip() {
    HapticFeedback.selectionClick();
    setState(() {
      _skipped++;
      _index++;
      _result = null;
      _answer.clear();
    });
  }

  void _next() {
    setState(() {
      _index++;
      _result = null;
      _answer.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _items == null || _items!.isEmpty
              ? const SizedBox(height: 3)
              : LinearProgressIndicator(
                  value: (_index / _items!.length).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(brandSeed),
                ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Back')));
    }
    if (_index >= _items!.length) {
      return _summary();
    }
    return _question();
  }

  Widget _question() {
    final item = _items![_index] as Map<String, dynamic>;
    final result = _result;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Row(
          children: [
            _IntensityPill(label: _intensityLabel),
            const SizedBox(width: Space.sm),
            Expanded(
                child: Text(item['skill_name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ))),
            Text('${_index + 1}/${_items!.length}',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(item['prompt'] ?? '',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(height: 1.3)),
        const SizedBox(height: Space.xl),
        TextField(
          controller: _answer,
          enabled: result == null,
          autofocus: result == null,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Your answer'),
        ),
        const SizedBox(height: Space.lg),
        if (result == null)
          Row(
            children: [
              OutlinedButton(
                onPressed: _submitting ? null : _skip,
                child: const Text('Skip'),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Check answer'),
                ),
              ),
            ],
          )
        else
          _feedback(result),
      ],
    );
  }

  Widget _feedback(Map<String, dynamic> r) {
    final palette = StatusPalette(Theme.of(context).brightness);
    final graded = r['graded'] != false; // older servers omit it -> treat as graded
    final correct = r['correct'] == true;
    final (color, icon, label) = !graded
        ? (palette.neutral, Icons.bookmark_added_outlined, 'Saved')
        : correct
            ? (palette.success, Icons.check_circle, 'Correct')
            : (palette.warning, Icons.cancel, 'Not quite');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: Space.sm),
                Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: Space.sm),
              Text(r['feedback'] ?? ''),
              if (r['answer'] != null) ...[
                const SizedBox(height: Space.md),
                Text('Reference answer',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text('${r['answer']}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: _next,
          icon: const Icon(Icons.arrow_forward),
          label: Text(_index + 1 >= _items!.length ? 'Finish' : 'Next'),
        ),
      ],
    );
  }

  Widget _summary() {
    final answered = _items!.length - _skipped;
    return _centered(
      'Session complete 🎉',
      subtitle: answered == 0
          ? 'You skipped everything this round.'
          : 'You got $_correct of $answered right'
              '${_skipped > 0 ? ' · skipped $_skipped' : ''}.',
      action: Wrap(spacing: Space.sm, children: [
        OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
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

class _IntensityPill extends StatelessWidget {
  const _IntensityPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          brandSeed.withValues(alpha: 0.22),
          _magenta.withValues(alpha: 0.14),
        ]),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: brandSeed.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: brandSeed,
          )),
    );
  }
}
