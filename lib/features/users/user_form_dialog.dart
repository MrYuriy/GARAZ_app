import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// Create an account ([user] == null) or edit one. Pops the saved [User].
class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, required this.actor, this.user});

  final User actor;
  final User? user;

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _login = TextEditingController(text: widget.user?.login);
  late final _fullName = TextEditingController(text: widget.user?.fullName);
  late final _email = TextEditingController(text: widget.user?.email);
  final _password = TextEditingController();
  late Role _role = widget.user?.role ?? widget.actor.role.manageable.last;
  late UserStatus _status = widget.user?.status ?? UserStatus.active;
  // New accounts get a starting password the user replaces on first sign-in.
  late bool _mustChange = widget.user?.mustChangePassword ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    for (final c in [_login, _fullName, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nullIfBlank(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(usersRepositoryProvider);
    try {
      final User saved;
      if (_isNew) {
        saved = await repo.create(
          login: _login.text.trim(),
          password: _password.text,
          role: _role,
          fullName: _nullIfBlank(_fullName.text),
          email: _nullIfBlank(_email.text),
          mustChangePassword: _mustChange,
        );
      } else {
        final u = widget.user!;
        final changes = <String, dynamic>{
          if (_login.text.trim().toLowerCase() != u.login) 'login': _login.text.trim(),
          if (_nullIfBlank(_fullName.text) != u.fullName) 'full_name': _nullIfBlank(_fullName.text),
          if (_nullIfBlank(_email.text) != u.email) 'email': _nullIfBlank(_email.text),
          if (_role != u.role) 'role': _role.api,
          if (_status != u.status) 'status': _status.api,
          if (_password.text.isNotEmpty) 'password': _password.text,
          if (_mustChange != u.mustChangePassword) 'must_change_password': _mustChange,
        };
        if (changes.isEmpty) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        saved = await repo.update(u.id, changes);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.actor.role.manageable;
    return AlertDialog(
      title: Text(_isNew ? 'Nowe konto' : 'Konto ${widget.user!.login}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _login,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Login (np. z WMS)'),
                  validator: (v) {
                    final s = (v ?? '').trim().toLowerCase();
                    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,63}$').hasMatch(s)) {
                      return '2–64 znaki: litery, cyfry, . _ -';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Imię i nazwisko'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (opcjonalnie)',
                    helperText: 'Tylko do powiadomień — logowanie jest loginem.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Role>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rola'),
                  items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r.label))],
                  onChanged: (r) => setState(() => _role = r!),
                ),
                if (!_isNew) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      helperText: 'Wyłączenie wylogowuje ze wszystkich urządzeń.',
                    ),
                    items: [for (final s in UserStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                    onChanged: (s) => setState(() => _status = s!),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: _isNew ? 'Hasło startowe' : 'Nowe hasło (zostaw puste, aby nie zmieniać)',
                  ),
                  // A reset password is a starting one too: ask for a change by default.
                  onChanged: (v) {
                    if (!_isNew && v.isNotEmpty && !_mustChange) setState(() => _mustChange = true);
                  },
                  validator: (v) => (_isNew && (v ?? '').isEmpty) ? 'Podaj hasło' : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _mustChange,
                  onChanged: (v) => setState(() => _mustChange = v ?? false),
                  title: const Text('Wymagaj zmiany hasła przy następnym logowaniu'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? 'Utwórz' : 'Zapisz')),
      ],
    );
  }
}
