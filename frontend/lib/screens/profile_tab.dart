import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';

/// Profile: your account code (so you can get back in on any device) and the
/// option to switch to another account by code. Deliberately small — this is
/// not where day-to-day choices live; those happen in the moment, on Home.
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _codeInput = TextEditingController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Make sure we have an account (and therefore a code) to show.
    Api.ensureUser().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _codeInput.dispose();
    super.dispose();
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
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Switched account. Pull Home to refresh.')),
        );
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
          Text('Your code',
              style: Theme.of(context).textTheme.titleMedium),
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
          const Divider(height: Space.xxl + Space.lg),
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
              labelText: 'Enter a code',
              hintText: 'XXXX-XXXX',
            ),
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
}
