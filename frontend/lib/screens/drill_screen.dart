import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets/answer_input.dart';

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
  AnswerImage? _image; // optional photo answer for the current question
  Map<String, dynamic>? _result; // grading of the current question
  bool _submitting = false;
  String? _error;

  String? _assistText; // hint / basics guidance shown under the question
  bool _assisting = false;

  /// Current intensity — starts from the launcher choice but can be switched
  /// mid-session via the pill; the new value persists as the default.
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

  /// Switch intensity from inside the session: persist it as the new default
  /// and pull a fresh set of questions at that intensity.
  Future<void> _changeIntensity(String value) async {
    if (value == _intensity) return;
    HapticFeedback.selectionClick();
    setState(() => _intensity = value);
    await Prefs.setIntensity(value);
    await _load();
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
          await Api.getSession(widget.journeyId, intensity: _intensity);
      setState(() {
        _items = items;
        _index = 0;
        _correct = 0;
        _skipped = 0;
        _result = null;
        _answer.clear();
        _image = null;
        _assistText = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _submit() async {
    final item = _items![_index] as Map<String, dynamic>;
    if (_answer.text.trim().isEmpty && _image == null) return;
    setState(() => _submitting = true);
    try {
      final res = await Api.submitAttempt(
        widget.journeyId,
        item['question_id'],
        _answer.text.trim(),
        imageBase64: _image == null ? null : base64Encode(_image!.bytes),
        imageMediaType: _image?.mediaType ?? 'image/jpeg',
      );
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
      _image = null;
      _assistText = null;
    });
  }

  void _next() {
    setState(() {
      _index++;
      _result = null;
      _answer.clear();
      _image = null;
      _assistText = null;
    });
  }

  /// "Help me approach this" / "I'm missing the basics" — best-effort guidance.
  Future<void> _assist(String kind) async {
    final item = _items![_index] as Map<String, dynamic>;
    setState(() => _assisting = true);
    try {
      final text = await Api.assist(
          widget.journeyId, item['question_id'] as String, kind);
      if (mounted) setState(() => _assistText = text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Couldn’t get help: $e')));
      }
    } finally {
      if (mounted) setState(() => _assisting = false);
    }
  }

  /// "I'm stuck — show the answer." Marked as not done (a miss).
  Future<void> _reveal() async {
    final item = _items![_index] as Map<String, dynamic>;
    setState(() => _submitting = true);
    try {
      final r =
          await Api.reveal(widget.journeyId, item['question_id'] as String);
      HapticFeedback.lightImpact();
      setState(() {
        _result = {
          'graded': true,
          'correct': false,
          'feedback': 'Marked as not done — review the answer below.',
          'answer': r['answer'],
          'explanation': r['explanation'],
          'revealed': true,
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            _IntensitySwitcher(
              label: _intensityLabel,
              current: _intensity,
              onChanged: _changeIntensity,
            ),
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
        AnswerInput(
          controller: _answer,
          enabled: result == null && !_submitting,
          image: _image,
          onImageChanged: (img) => setState(() => _image = img),
        ),
        if (result == null && _assistText != null) ...[
          const SizedBox(height: Space.lg),
          _AssistCard(text: _assistText!),
        ],
        const SizedBox(height: Space.lg),
        if (result == null) ...[
          _HelpRow(busy: _assisting || _submitting, onAssist: _assist, onReveal: _reveal),
          const SizedBox(height: Space.md),
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
          ),
        ] else
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

/// The three in-question help options.
class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.busy,
    required this.onAssist,
    required this.onReveal,
  });

  final bool busy;
  final ValueChanged<String> onAssist;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HelpButton(
          icon: Icons.lightbulb_outline,
          title: 'Help me approach this',
          subtitle: 'I’ve got the basics but not this problem',
          onTap: busy ? null : () => onAssist('hint'),
        ),
        const SizedBox(height: Space.sm),
        _HelpButton(
          icon: Icons.replay,
          title: 'I’m missing the basics',
          subtitle: 'Step back and explain what I need first',
          onTap: busy ? null : () => onAssist('basics'),
        ),
        const SizedBox(height: Space.sm),
        _HelpButton(
          icon: Icons.visibility_outlined,
          title: 'I’m stuck — show the answer',
          subtitle: 'Marked as not done',
          onTap: busy ? null : onReveal,
        ),
      ],
    );
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

/// Inline guidance returned by "approach help" / "missing the basics".
class _AssistCard extends StatelessWidget {
  const _AssistCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        color: brandSeed.withValues(alpha: 0.08),
        border: Border.all(color: brandSeed.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb, size: 18, color: brandSeed),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(text,
                style: TextStyle(color: scheme.onSurface, height: 1.4)),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
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
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brandSeed,
                )),
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
