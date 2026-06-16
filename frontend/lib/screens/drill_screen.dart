import 'package:flutter/material.dart';

import '../api.dart';

/// A study session: one question at a time, answer -> AI feedback -> next.
class DrillScreen extends StatefulWidget {
  const DrillScreen({super.key, required this.journeyId, required this.title});
  final String journeyId;
  final String title;

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  List<dynamic>? _items;
  int _index = 0;
  int _correct = 0;
  final _answer = TextEditingController();
  Map<String, dynamic>? _result; // grading of the current question
  bool _submitting = false;
  String? _error;

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
      final items = await Api.getSession(widget.journeyId);
      setState(() {
        _items = items;
        _index = 0;
        _correct = 0;
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
      appBar: AppBar(title: Text('Study · ${widget.title}')),
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
      return _centered(
        'Session complete!\nYou got $_correct of ${_items!.length} right.',
        action: Wrap(spacing: 8, children: [
          OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
          FilledButton(
              onPressed: _load, child: const Text('Another session')),
        ]),
      );
    }
    return _question();
  }

  Widget _question() {
    final item = _items![_index] as Map<String, dynamic>;
    final result = _result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _modeBadge(item['mode'] as String?),
            const SizedBox(width: 8),
            Expanded(
                child: Text(item['skill_name'] ?? '',
                    style: Theme.of(context).textTheme.labelLarge)),
            Text('${_index + 1}/${_items!.length}'),
          ],
        ),
        const SizedBox(height: 12),
        Text(item['prompt'] ?? '',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _answer,
          enabled: result == null,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Your answer',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (result == null)
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Check answer'),
          )
        else
          _feedback(result),
      ],
    );
  }

  Widget _feedback(Map<String, dynamic> r) {
    final correct = r['correct'] == true;
    final color = correct ? Colors.green : Colors.deepOrange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: color.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(correct ? Icons.check_circle : Icons.cancel,
                      color: color),
                  const SizedBox(width: 8),
                  Text(correct ? 'Correct' : 'Not quite',
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Text(r['feedback'] ?? ''),
                if (r['answer'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Reference answer',
                      style: Theme.of(context).textTheme.labelSmall),
                  Text('${r['answer']}'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _next,
          icon: const Icon(Icons.arrow_forward),
          label: Text(_index + 1 >= _items!.length ? 'Finish' : 'Next'),
        ),
      ],
    );
  }

  Widget _modeBadge(String? mode) {
    final label = switch (mode) {
      'on_the_go' => 'On the go',
      'short_drill' => 'Short drill',
      'deep_dive' => 'Deep dive',
      'discuss' => 'Discuss',
      _ => mode ?? '',
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _centered(String text, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}
