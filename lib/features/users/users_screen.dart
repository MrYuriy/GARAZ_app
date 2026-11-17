import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'user_form_dialog.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Role? _role;
  PageOf<User>? _page;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(usersRepositoryProvider).list(query: _search.text.trim(), role: _role);
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _openForm([User? user]) async {
    final me = ref.read(authControllerProvider).user!;
    final saved = await showDialog<User>(
      context: context,
      builder: (_) => UserFormDialog(actor: me, user: user),
    );
    if (saved != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(user == null ? 'Utworzono konto ${saved.login}' : 'Zapisano ${saved.login}')),
        );
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).user!;
    final canCreate = me.role.manageable.isNotEmpty;
    final items = _page?.items ?? const <User>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Użytkownicy panelu'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Dodaj'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Szukaj: login, imię, email',
                    ),
                  ),
                ),
                DropdownButton<Role?>(
                  value: _role,
                  hint: const Text('Wszystkie role'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Wszystkie role')),
                    for (final r in Role.values) DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  onChanged: (r) {
                    setState(() => _role = r);
                    _load();
                  },
                ),
                if (_page != null) Text('Razem: ${_page!.total}'),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? const Center(child: Text('Brak kont.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _UserTile(
                      user: items[i],
                      editable: items[i].id != me.id && me.role.manageable.contains(items[i].role),
                      onTap: () => _openForm(items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.editable, required this.onTap});

  final User user;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = user.status == UserStatus.disabled;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: editable,
      onTap: editable ? onTap : null,
      leading: CircleAvatar(
        backgroundColor: disabled ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Text(user.displayName.characters.first.toUpperCase()),
      ),
      title: Text(user.displayName, style: disabled ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
      subtitle: Text(
        [
          user.login,
          user.role.label,
          if (user.mustChangePassword) 'musi zmienić hasło',
          if (user.email != null) user.email!,
          'ost. logowanie: ${formatDateTime(user.lastLoginAt)}',
        ].join(' · '),
      ),
      trailing: disabled ? Chip(label: Text(user.status.label)) : (editable ? const Icon(Icons.edit_outlined) : null),
    );
  }
}
