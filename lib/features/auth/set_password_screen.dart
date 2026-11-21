import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/i18n.dart';

/// Shown right after signing in with a starting password from the
/// administrator. Nothing else opens until the user sets their own.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // No current password: the user has just signed in with the starting one.
      await ref.read(authControllerProvider.notifier).changePassword(null, _next.text);
      // The flag is now cleared and the router moves on by itself.
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.key, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(tr('Ustaw nowe hasło'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    tr('Konto {login} ma hasło startowe od administratora. Zanim przejdziesz dalej, ustaw własne.', {
                      'login': user?.login ?? '',
                    }),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _next,
                    autofocus: true,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: tr('Nowe hasło')),
                    validator: (v) => (v ?? '').isEmpty ? tr('Podaj nowe hasło') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _repeat,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(labelText: tr('Powtórz nowe hasło')),
                    validator: (v) => v != _next.text ? tr('Hasła się różnią') : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Zapisz i przejdź dalej')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).logout(),
                    child: Text(tr('Wyloguj')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
