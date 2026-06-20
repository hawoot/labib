import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme.dart';

const Color _magenta = Color(0xFFC13BFF);

/// A captured photo answer: raw bytes + media type, ready to send to the API.
class AnswerImage {
  const AnswerImage(this.bytes, this.mediaType);
  final List<int> bytes;
  final String mediaType;
}

/// The answer area for a drill question. Three input methods are ALWAYS
/// available, side by side, regardless of question intensity:
///   • type   — the text field
///   • speak  — mic button (speech-to-text appends into the field)
///   • photo  — camera button (snap/pick a picture of worked-out work)
///
/// The text lives in [controller] (owned by the parent). A chosen photo is
/// reported via [onImageChanged] and shown here as a removable thumbnail.
class AnswerInput extends StatefulWidget {
  const AnswerInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.image,
    required this.onImageChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final AnswerImage? image;
  final ValueChanged<AnswerImage?> onImageChanged;

  @override
  State<AnswerInput> createState() => _AnswerInputState();
}

class _AnswerInputState extends State<AnswerInput> {
  final SpeechToText _speech = SpeechToText();
  final ImagePicker _picker = ImagePicker();
  bool _speechReady = false;
  bool _listening = false;

  /// Text already in the field when listening starts, so live transcription
  /// appends instead of overwriting.
  String _basePrefix = '';

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone isn’t available here.')),
        );
      }
      return;
    }
    HapticFeedback.selectionClick();
    final existing = widget.controller.text;
    _basePrefix = existing.isEmpty || existing.endsWith(' ') ? existing : '$existing ';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        widget.controller.text = '$_basePrefix${r.recognizedWords}';
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
      },
      listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mt = file.mimeType ??
          (file.name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      widget.onImageChanged(AnswerImage(bytes, mt));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Couldn’t get the photo: $e')));
      }
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

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Your answer',
            hintText: _listening ? 'Listening…' : 'Type, speak, or snap a photo',
          ),
        ),
        if (widget.image != null) ...[
          const SizedBox(height: Space.sm),
          _Thumbnail(
            image: widget.image!,
            onRemove: () => widget.onImageChanged(null),
          ),
        ],
        const SizedBox(height: Space.sm),
        Row(
          children: [
            _InputButton(
              icon: _listening ? Icons.stop_circle_outlined : Icons.mic_none,
              label: _listening ? 'Listening' : 'Speak',
              active: _listening,
              onTap: widget.enabled ? _toggleMic : null,
            ),
            const SizedBox(width: Space.sm),
            _InputButton(
              icon: Icons.photo_camera_outlined,
              label: 'Photo',
              active: false,
              onTap: widget.enabled ? _chooseImageSource : null,
            ),
            const Spacer(),
            if (_listening)
              Text('Tap to stop',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _InputButton extends StatelessWidget {
  const _InputButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding:
            const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.chip),
          color: active
              ? _magenta.withValues(alpha: 0.16)
              : scheme.surfaceContainerHighest,
          border: Border.all(
            color: active
                ? _magenta
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: disabled
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : active
                        ? _magenta
                        : scheme.onSurface),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: disabled
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                      : active
                          ? _magenta
                          : scheme.onSurface,
                )),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image, required this.onRemove});
  final AnswerImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control),
          child: Image.memory(
            Uint8List.fromList(image.bytes),
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
