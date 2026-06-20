import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/app_motion.dart';
import '../widgets/pressable.dart';
import 'home_shell.dart';

// Landing palette — always dark, independent of the app theme, so the first
// impression is the premium look from the design mockup.
const _bg = Color(0xFF0B0B0F);
const _violet = Color(0xFF6D4AFF);
const _violet2 = Color(0xFF9B6BFF);
const _magenta = Color(0xFFC13BFF);
const _txt = Color(0xFFF4F4F7);
const _dim = Color(0xFF9A9AA8);

/// The front door: a modern welcome screen shown to first-time visitors. It
/// takes them into the app — "Get started" mints an account, or they can
/// restore one with a code.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _busy = false;

  void _goHome() {
    Navigator.pushReplacement(
      context,
      AppPageRoute(builder: (_) => const HomeShell()),
    );
  }

  Future<void> _getStarted() async {
    setState(() => _busy = true);
    try {
      await Api.ensureUser();
      if (mounted) _goHome();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't reach the server: $e")),
        );
      }
    }
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter your code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code',
            hintText: 'XXXX-XXXX',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    final code = controller.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final found = await Api.loginWithCode(code);
      if (!mounted) return;
      if (found) {
        _goHome();
      } else {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No account with that code.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Soft violet/magenta glows behind the content.
          Positioned(
            left: -90,
            top: 230,
            child: _Glow(color: _violet, size: 430, opacity: 0.45),
          ),
          Positioned(
            right: -100,
            bottom: 150,
            child: _Glow(color: _magenta, size: 320, opacity: 0.30),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [_violet, _magenta],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'labib',
                        style: TextStyle(
                          color: _txt,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _Pill(),
                  const SizedBox(height: 18),
                  const Text(
                    'Learn anything.',
                    style: TextStyle(
                      color: _txt,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      height: 1.03,
                      letterSpacing: -1.6,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [_violet2, _magenta],
                    ).createShader(rect),
                    child: const Text(
                      'Make it stick.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1.03,
                        letterSpacing: -1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(
                    width: 290,
                    child: Text(
                      'Turn any book, PDF, lecture or note into a tutor that '
                      'drills you until you actually remember it.',
                      style: TextStyle(
                        color: _dim,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _PrimaryButton(
                    label: 'Get started',
                    busy: _busy,
                    onTap: _busy ? null : _getStarted,
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Pressable(
                      onTap: _busy ? null : _enterCode,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        child: Text(
                          'I already have a code',
                          style: TextStyle(
                            color: _dim,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.opacity});
  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.72],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: _violet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _violet2.withValues(alpha: 0.3)),
      ),
      child: const Text(
        'No account · no password · just start',
        style: TextStyle(
          color: _violet2,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.busy, this.onTap});
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [_violet, _violet2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _violet.withValues(alpha: 0.55),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
      ),
    );
  }
}
