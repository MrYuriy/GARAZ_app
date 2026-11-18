import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final done = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hasło zmienione. Inne urządzenia zostały wylogowane.')));
    }
  }

  Future<void> _logoutEverywhere(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wylogować ze wszystkich urządzeń?'),
        content: const Text('Wszystkie sesje tego konta, także ta, zostaną zakończone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyloguj wszędzie')),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logoutEverywhere();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Moje konto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.displayName),
                  subtitle: const Text('Imię i nazwisko'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(user.login),
                  subtitle: const Text('Login'),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(user.email ?? '—'),
                  subtitle: const Text('Email do powiadomień'),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(user.role.label),
                  subtitle: const Text('Rola'),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(formatDateTime(user.lastLoginAt)),
                  subtitle: const Text('Ostatnie logowanie'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Zmień hasło'),
                  onTap: () => _changePassword(context),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Wyloguj'),
                  onTap: () => ref.read(authControllerProvider.notifier).logout(),
                ),
                ListTile(
                  leading: const Icon(Icons.devices_other),
                  title: const Text('Wyloguj ze wszystkich urządzeń'),
                  onTap: () => _logoutEverywhere(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('API: ${AppConfig.apiBaseUrl}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(_current.text, _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Zmiana hasła'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Obecne hasło'),
                validator: (v) => (v ?? '').isEmpty ? 'Podaj obecne hasło' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nowe hasło'),
                validator: (v) => (v ?? '').isEmpty ? 'Podaj nowe hasło' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeat,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Powtórz nowe hasło'),
                validator: (v) => v != _next.text ? 'Hasła się różnią' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zmień')),
      ],
    );
  }
}
