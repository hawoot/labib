import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../file_picker.dart';
import 'drill_screen.dart';

/// One journey: add material, run the crunch, watch progress, see the result.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.journey});
  final Map<String, dynamic> journey;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  String get _jid => widget.journey['id'] as String;

  List<dynamic> _documents = [];
  Map<String, dynamic>? _job; // latest ingestion job
  Map<String, dynamic>? _curriculum;
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final docs = await Api.listDocuments(_jid);
    final job = await Api.getIngest(_jid);
    Map<String, dynamic>? cur;
    if (job != null && job['status'] == 'done') {
      cur = await Api.getCurriculum(_jid);
    }
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _job = job;
      _curriculum = cur;
      _loading = false;
    });
    if (job != null && (job['status'] == 'queued' || job['status'] == 'running')) {
      _startPolling();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final job = await Api.getIngest(_jid);
      if (!mounted) return;
      setState(() => _job = job);
      if (job != null && job['status'] == 'done') {
        _poll?.cancel();
        final cur = await Api.getCurriculum(_jid);
        if (mounted) setState(() => _curriculum = cur);
      } else if (job != null && job['status'] == 'failed') {
        _poll?.cancel();
      }
    });
  }

  Future<void> _addTextDialog() async {
    final title = TextEditingController();
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add material'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: text,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                    labelText: 'Paste your text here',
                    alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && text.text.trim().isNotEmpty) {
      await Api.addText(
        _jid,
        title.text.trim().isEmpty ? 'Pasted text' : title.text.trim(),
        text.text.trim(),
      );
      await _load();
    }
  }

  Future<void> _addFiles() async {
    try {
      final picked = await pickFiles();
      if (picked.isEmpty) return;
      final messenger = ScaffoldMessenger.of(context);
      for (var i = 0; i < picked.length; i++) {
        if (mounted) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(
            duration: const Duration(minutes: 1),
            content:
                Text('Uploading ${i + 1}/${picked.length}: ${picked[i].name}'),
          ));
        }
        await Api.addFile(_jid, picked[i].name, picked[i].bytes);
      }
      await _load();
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text('Added ${picked.length} '
              'file${picked.length == 1 ? '' : 's'}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _crunch() async {
    await Api.startIngest(_jid);
    setState(() => _job = {'status': 'queued', 'phase': 'queued', 'progress': 0});
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final status = _job?['status'];
    final busy = status == 'queued' || status == 'running';
    return Scaffold(
      appBar: AppBar(title: Text(widget.journey['title'] ?? 'Journey')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              // Pad the bottom by the system nav-bar inset. Since compileSdk 36
              // the app is edge-to-edge (Android 15), so without this the last
              // content (e.g. the crunch %) renders behind the translucent nav
              // bar and is unreadable.
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: [
                  _section('Material (${_documents.length})'),
                  ..._documents.map((d) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(d['title'] ?? ''),
                          subtitle: Text(d['kind'] ?? ''),
                        ),
                      )),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : _addTextDialog,
                        icon: const Icon(Icons.notes),
                        label: const Text('Add text'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _addFiles,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Add files (PDF)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _crunchSection(busy),
                  if (_curriculum != null) ...[
                    const SizedBox(height: 24),
                    _curriculumSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _crunchSection(bool busy) {
    final status = _job?['status'];
    if (busy) {
      final progress = (_job?['progress'] ?? 0) as int;
      final phase = (_job?['phase'] ?? '') as String;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crunching… $phase',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress / 100),
          const SizedBox(height: 4),
          Text('$progress%'),
        ],
      );
    }
    if (status == 'failed') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crunch failed',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('${_job?['error'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: _documents.isEmpty ? null : _crunch,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._crunchOutcome(),
        FilledButton.icon(
          onPressed: _documents.isEmpty ? null : _crunch,
          icon: const Icon(Icons.auto_awesome),
          label:
              Text(_curriculum == null ? 'Crunch into questions' : 'Re-crunch'),
        ),
      ],
    );
  }

  /// Outcome badge for a finished crunch: nothing for a clean single-pass,
  /// an amber "chunked into N" when it fell back to chunking, and a red
  /// "N not included" (plus the notice) when material was dropped at the cap.
  List<Widget> _crunchOutcome() {
    final job = _job;
    if (job == null || (job['mode'] as String? ?? '') != 'chunked') {
      return const [];
    }
    final dropped = (job['dropped_count'] ?? 0) as int;
    final sections = (job['section_count'] ?? 0) as int;
    final notice = job['notice'] as String?;
    final scheme = Theme.of(context).colorScheme;
    final red = dropped > 0;
    final color = red ? scheme.error : const Color(0xFFE0A000);
    final label = red
        ? '$dropped section${dropped == 1 ? '' : 's'} not included'
        : 'Chunked into $sections sections';
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(red ? Icons.error_outline : Icons.call_split,
                size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      if (notice != null && notice.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(notice,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ),
      const SizedBox(height: 12),
    ];
  }

  Widget _curriculumSection() {
    final cur = _curriculum!;
    final skills = (cur['skills'] as List<dynamic>);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
            '${cur['skill_count']} skills · ${cur['question_count']} questions'),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DrillScreen(
                  journeyId: _jid,
                  title: widget.journey['title'] ?? 'Journey',
                ),
              ),
            ).then((_) => _load()),
            icon: const Icon(Icons.school),
            label: const Text('Study'),
          ),
        ),
        const SizedBox(height: 12),
        ...skills.map((s) {
          final questions = (s['questions'] as List<dynamic>);
          return Card(
            child: ExpansionTile(
              title: Text(s['name'] ?? ''),
              subtitle: Text(s['description'] ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              children: questions.map<Widget>((q) {
                return ListTile(
                  dense: true,
                  leading: _modeBadge(q['mode'] as String?),
                  title: Text(q['prompt'] ?? ''),
                  subtitle: (q['answer'] != null)
                      ? Text('Answer: ${q['answer']}')
                      : null,
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _modeBadge(String? mode) {
    final m = mode ?? '';
    final short = switch (m) {
      'on_the_go' => 'GO',
      'short_drill' => 'DRILL',
      'deep_dive' => 'DIVE',
      'discuss' => 'DISC',
      _ => '?',
    };
    return CircleAvatar(radius: 18, child: Text(short, style: const TextStyle(fontSize: 9)));
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleLarge),
      );
}
