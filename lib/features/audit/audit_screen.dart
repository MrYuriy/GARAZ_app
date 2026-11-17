import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  static const _limit = 50;
  final List<AuditEntry> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _items.clear();
    _page = 0;
    await _more();
  }

  Future<void> _more() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(auditRepositoryProvider).list(page: _page + 1, limit: _limit);
      if (mounted) {
        setState(() {
          _items.addAll(page.items);
          _page = page.page;
          _total = page.total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String action) => switch (action) {
        'auth.login' => Icons.login,
        'auth.logout_all' => Icons.logout,
        'auth.password_changed' => Icons.key,
        'auth.token_reuse' => Icons.gpp_maybe_outlined,
        'user.created' => Icons.person_add_alt,
        'user.updated' => Icons.manage_accounts_outlined,
        'dictionary.created' => Icons.playlist_add,
        'dictionary.updated' => Icons.edit_note,
        _ => Icons.event_note,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dziennik zmian'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length + (_items.length < _total ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: OutlinedButton(onPressed: _loading ? null : _more, child: const Text('Pokaż więcej')),
                    ),
                  );
                }
                final e = _items[i];
                return ListTile(
                  leading: Icon(_icon(e.action)),
                  title: Text(e.label),
                  subtitle: Text(
                    [
                      formatDateTime(e.createdAt),
                      if (e.userId != null) 'kto: #${e.userId}',
                      if (e.resourceType != null) '${e.resourceType} #${e.resourceId}',
                      if (e.payload != null && e.payload!.isNotEmpty) e.payload.toString(),
                      if (e.ipAddress != null) 'IP ${e.ipAddress}',
                    ].join(' · '),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
