import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/filter_bar.dart';
import 'user_form_dialog.dart';
import '../../core/i18n.dart';

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
          SnackBar(
            content: Text(
              user == null
                  ? tr('Utworzono konto {login}', {'login': saved.login})
                  : tr('Zapisano {login}', {'login': saved.login}),
            ),
          ),
        );
      }
      await _load();
    }
  }

  void _setRole(Role? r) {
    setState(() => _role = r);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).user!;
    final canCreate = me.role.manageable.isNotEmpty;
    final items = _page?.items ?? const <User>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Użytkownicy panelu')),
        actions: [
          IconButton(tooltip: tr('Odśwież'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add_alt),
              label: Text(tr('Dodaj')),
            )
          : null,
      body: Column(
        children: [
          FilterBar(
            searchController: _search,
            onSearch: _onSearch,
            searchHint: tr('Szukaj: login, imię, email'),
            groups: () => [
              FilterGroup(
                title: tr('Rola'),
                activeLabel: _role?.label,
                onClear: () => _setRole(null),
                options: [
                  for (final r in [null, ...Role.values])
                    FilterOption(r?.label ?? tr('Wszystkie role'), selected: _role == r, onSelected: () => _setRole(r)),
                ],
              ),
            ],
            total: _page?.total,
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? Center(child: Text(tr('Brak kont.')))
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
          if (user.mustChangePassword) tr('musi zmienić hasło'),
          if (user.email != null) user.email!,
          tr('ost. logowanie: {lastLoginAt}', {'lastLoginAt': formatDateTime(user.lastLoginAt)}),
        ].join(' · '),
      ),
      trailing: disabled ? Chip(label: Text(user.status.label)) : (editable ? const Icon(Icons.edit_outlined) : null),
    );
  }
}
