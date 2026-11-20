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
    'truck.created' => Icons.forklift,
    'truck.updated' => Icons.build_outlined,
    'truck.qr_reissued' => Icons.qr_code_2,
    'incident.created' => Icons.report_outlined,
    'incident.updated' => Icons.assignment_turned_in_outlined,
    'truck.deleted' || 'truck_manufacturer.deleted' || 'truck_model.deleted' => Icons.delete_outline,
    'truck_manufacturer.created' || 'truck_manufacturer.updated' => Icons.factory_outlined,
    'truck_model.created' || 'truck_model.updated' => Icons.category_outlined,
    'operator.created' => Icons.person_add_alt,
    'operator.updated' => Icons.manage_accounts_outlined,
    'operator.qr_reissued' => Icons.qr_code_2,
    'permit.created' => Icons.verified_outlined,
    'permit.updated' => Icons.edit_note,
    'permit.expired' => Icons.event_busy,
    'permit.renewed' => Icons.autorenew,
    'permit.document_attached' => Icons.attach_file,
    'permit.document_removed' => Icons.delete_outline,
    _ => Icons.event_note,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dziennik zmian'),
        actions: [
          IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh)),
        ],
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
