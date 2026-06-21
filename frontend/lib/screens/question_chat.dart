import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api.dart';
import '../theme.dart';
import '../util/secure_context.dart';
import '../widgets/answer_input.dart' show AnswerImage;

const Color _magenta = Color(0xFFC13BFF);

/// One chat message in a question conversation.
class _Msg {
  _Msg.tutor(this.text)
      : fromTutor = true,
        image = null;
  _Msg.student(this.text, {this.image}) : fromTutor = false;

  final bool fromTutor;
  final String text;
  final AnswerImage? image;
}

/// The per-question experience as a chat with labib. The student can type,
/// speak (dictation), or send a photo; the tutor keeps full context and decides
/// when the question is solved. The three quick replies just send a predefined
/// message. On solved, a Next button appears.
class QuestionChat extends StatefulWidget {
  const QuestionChat({
    super.key,
    required this.journeyId,
    required this.question,
    required this.onSolved,
    required this.onNext,
    required this.onSkip,
  });

  final String journeyId;
  final Map<String, dynamic> question;

  /// Called once when the tutor marks the question solved, with the score.
  final ValueChanged<double> onSolved;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<QuestionChat> createState() => _QuestionChatState();
}

class _QuestionChatState extends State<QuestionChat> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _picker = ImagePicker();

  AnswerImage? _pendingImage;
  bool _sending = false;
  // null until the question reaches a verdict, then 'correct' or 'revealed'.
  // The verdict is final; the chat stays open for follow-ups either way.
  String? _verdict;
  bool _listening = false;
  String _basePrefix = '';

  // Sentinel for the "show the answer" quick reply, which routes to the
  // deterministic reveal flow rather than the graded chat.
  static const _revealMsg = '__reveal__';
  static const _quickReplies = <(String, String)>[
    ('Help me approach this', 'Can you help me approach this — how should I start?'),
    ('I’m missing the basics',
        'I think I’m missing the basics. Can we step back to what I need first?'),
    ('I’m stuck — show the answer', _revealMsg),
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(_Msg.tutor(
        '${widget.question['prompt'] ?? ''}\n\nTalk it through with me — type, '
        'speak, or send a photo of your working.'));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _speech.stop();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: Motion.medium, curve: Motion.curve);
      }
    });
  }

  List<Map<String, dynamic>> _history() => [
        for (final m in _messages)
          {
            'role': m.fromTutor ? 'assistant' : 'user',
            'text': m.text,
            if (m.image != null) 'image': base64Encode(m.image!.bytes),
            if (m.image != null) 'image_media_type': m.image!.mediaType,
          }
      ];

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    final image = _pendingImage;
    if (trimmed.isEmpty && image == null) return;
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
    }
    setState(() {
      _messages.add(_Msg.student(trimmed, image: image));
      _pendingImage = null;
      _input.clear();
      _sending = true;
    });
    _toBottom();
    try {
      // Once there's a verdict this is a follow-up — closed=true so the backend
      // replies without re-grading or re-recording.
      final closed = _verdict != null;
      final res = await Api.chat(widget.journeyId,
          widget.question['question_id'] as String, _history(),
          closed: closed);
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg.tutor(res['reply'] as String? ?? ''));
        _sending = false;
        if (!closed && res['solved'] == true && _verdict == null) {
          _verdict = 'correct';
          HapticFeedback.mediumImpact();
          widget.onSolved((res['score'] as num?)?.toDouble() ?? 0);
        }
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg.tutor('Something went wrong — try again in a moment.'));
        _sending = false;
      });
      _toBottom();
    }
  }

  /// Explicit give-up: deterministically records the question as not-done (score
  /// 0 → the skill resurfaces soon), shows the real answer, and marks the verdict
  /// 'revealed'. The chat stays open for follow-ups.
  Future<void> _revealAnswer() async {
    if (_verdict != null || _sending) return;
    setState(() => _sending = true);
    _toBottom();
    try {
      final res = await Api.reveal(
          widget.journeyId, widget.question['question_id'] as String);
      if (!mounted) return;
      final answer = (res['answer'] as String?)?.trim();
      final explanation = (res['explanation'] as String?)?.trim();
      final parts = [
        if (answer != null && answer.isNotEmpty) 'Answer: $answer',
        if (explanation != null && explanation.isNotEmpty) explanation,
      ];
      setState(() {
        _messages.add(_Msg.tutor(parts.isEmpty
            ? 'Here’s the answer.'
            : parts.join('\n\n')));
        _sending = false;
        _verdict = 'revealed';
      });
      // Counts as engaged-with (toward the daily goal) but not correct; the
      // engine already keeps the skill due so it comes back.
      widget.onSolved(0);
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg.tutor('Couldn’t fetch the answer — try again.'));
        _sending = false;
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (kIsWeb && !isPageSecure()) {
      _toast('Voice needs a secure (HTTPS) connection — this page is on HTTP, '
          'so the browser blocks the mic. Open the app over https://.');
      return;
    }
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (e) {
          if (mounted) setState(() => _listening = false);
          _toast('Voice error: ${e.errorMsg}');
        },
      );
      if (!ok) {
        _toast('Voice isn’t available in this browser. It works best in '
            'Chrome/Edge over HTTPS, with microphone permission allowed.');
        return;
      }
      HapticFeedback.selectionClick();
      final existing = _input.text;
      _basePrefix =
          existing.isEmpty || existing.endsWith(' ') ? existing : '$existing ';
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (r) {
          _input.text = '$_basePrefix${r.recognizedWords}';
          _input.selection = TextSelection.fromPosition(
              TextPosition(offset: _input.text.length));
        },
        listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
      );
    } catch (e) {
      if (mounted) setState(() => _listening = false);
      _toast('Couldn’t start voice (${e.runtimeType}). On the web, use Chrome '
          'over HTTPS with mic permission.');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera && !isPageSecure()) {
      _toast('The camera needs a secure (HTTPS) connection — this page is on '
          'HTTP. Use the photo library instead, or open the app over https://.');
      return;
    }
    try {
      final file = await _picker.pickImage(
          source: source, maxWidth: 1600, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mt = file.mimeType ??
          (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      setState(() => _pendingImage = AnswerImage(bytes, mt));
    } catch (e) {
      _toast('Couldn’t get the photo: $e');
    }
  }

  void _chooseImageSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _messages.length) return const _TypingBubble();
              return _Bubble(msg: _messages[i]);
            },
          ),
        ),
        // The verdict closes the evaluation but NOT the conversation: a status
        // bar with "Next" appears, and the input stays so you can ask follow-ups.
        if (_verdict != null) _VerdictBar(verdict: _verdict!, onNext: widget.onNext),
        if (_verdict == null)
          _QuickReplies(
            disabled: _sending,
            onTap: (msg) => msg == _revealMsg ? _revealAnswer() : _send(msg),
            replies: _quickReplies,
          ),
        _InputBar(
          controller: _input,
          sending: _sending,
          listening: _listening,
          pendingImage: _pendingImage,
          hint: _verdict != null ? 'Ask a follow-up…' : null,
          onMic: _toggleMic,
          onPhoto: _chooseImageSource,
          onRemoveImage: () => setState(() => _pendingImage = null),
          onSend: () => _send(_input.text),
          onSkip: _verdict != null ? null : widget.onSkip,
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tutor = msg.fromTutor;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        mainAxisAlignment: tutor ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tutor) ...[
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [brandSeed, _magenta]),
              ),
              alignment: Alignment.center,
              child: const Text('l',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            const SizedBox(width: Space.sm),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74),
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.sm + 2),
              decoration: BoxDecoration(
                gradient: tutor
                    ? null
                    : const LinearGradient(colors: [brandSeed, _magenta]),
                color: tutor ? scheme.surfaceContainerHighest : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(tutor ? 4 : 16),
                  bottomRight: Radius.circular(tutor ? 16 : 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.image != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        Uint8List.fromList(msg.image!.bytes),
                        width: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (msg.text.isNotEmpty) const SizedBox(height: Space.sm),
                  ],
                  if (msg.text.isNotEmpty)
                    Text(
                      msg.text,
                      style: TextStyle(
                        color: tutor ? scheme.onSurface : Colors.white,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = ((_c.value + i * 0.2) % 1.0);
              final o = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: o,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant, shape: BoxShape.circle),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _QuickReplies extends StatelessWidget {
  const _QuickReplies(
      {required this.replies, required this.onTap, required this.disabled});
  final List<(String, String)> replies;
  final ValueChanged<String> onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: replies.length,
        separatorBuilder: (_, __) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) {
          final (label, msg) = replies[i];
          return Center(
            child: GestureDetector(
              onTap: disabled ? null : () => onTap(msg),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.md, vertical: Space.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: brandSeed.withValues(alpha: disabled ? 0.2 : 0.5)),
                  color: brandSeed.withValues(alpha: 0.06),
                ),
                child: Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: disabled ? scheme.onSurfaceVariant : brandSeed,
                    )),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.listening,
    required this.pendingImage,
    required this.onMic,
    required this.onPhoto,
    required this.onRemoveImage,
    required this.onSend,
    required this.onSkip,
    this.hint,
  });

  final TextEditingController controller;
  final bool sending;
  final bool listening;
  final AnswerImage? pendingImage;
  final VoidCallback onMic;
  final VoidCallback onPhoto;
  final VoidCallback onRemoveImage;
  final VoidCallback onSend;
  // Null once there's a verdict — the Skip control is hidden (use Next instead).
  final VoidCallback? onSkip;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingImage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm, left: Space.sm),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(Uint8List.fromList(pendingImage!.bytes),
                            height: 64, width: 64, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: onRemoveImage,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                if (onSkip != null)
                  IconButton(
                    tooltip: 'Skip question',
                    onPressed: sending ? null : onSkip,
                    icon: Icon(Icons.skip_next_outlined,
                        color: scheme.onSurfaceVariant),
                  ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: sending ? null : onPhoto,
                          icon: Icon(Icons.photo_camera_outlined,
                              color: scheme.onSurfaceVariant, size: 22),
                        ),
                        IconButton(
                          onPressed: sending ? null : onMic,
                          icon: Icon(
                            listening ? Icons.mic : Icons.mic_none,
                            color: listening ? _magenta : scheme.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: sending ? null : (_) => onSend(),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: listening
                                  ? 'Listening…'
                                  : (hint ?? 'Message labib'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                _SendButton(onTap: sending ? null : onSend, sending: sending),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap, required this.sending});
  final VoidCallback? onTap;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [brandSeed, _magenta]),
          boxShadow: [
            BoxShadow(
                color: brandSeed.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: sending
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.arrow_upward, color: Colors.white),
      ),
    );
  }
}

class _VerdictBar extends StatelessWidget {
  const _VerdictBar({required this.verdict, required this.onNext});
  final String verdict; // 'correct' | 'revealed'
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final correct = verdict == 'correct';
    final icon = correct ? Icons.check_circle : Icons.menu_book_outlined;
    final color = correct ? const Color(0xFF22C55E) : const Color(0xFFE0A000);
    final label = correct ? 'Nice — got it.' : 'Answer shown — you’ll see this again.';
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.control),
                gradient: const LinearGradient(colors: [brandSeed, _magenta]),
              ),
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Next  →',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
