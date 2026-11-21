import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import '../../core/widgets/qr_code_dialog.dart';
import '../permits/permit_dialog.dart';
import '../permits/permit_widgets.dart';
import 'operator_form_dialog.dart';
import '../../core/i18n.dart';

/// One operator: their details, QR card and permits.
class OperatorScreen extends ConsumerStatefulWidget {
  const OperatorScreen({super.key, required this.operatorId});

  final int operatorId;

  @override
  ConsumerState<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends ConsumerState<OperatorScreen> {
  Operator? _operator;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await ref.read(operatorsRepositoryProvider).get(widget.operatorId);
      if (mounted) setState(() => _operator = o);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit() async {
    final saved = await showDialog<Operator>(
      context: context,
      builder: (_) => OperatorFormDialog(operator: _operator),
    );
    if (saved != null) setState(() => _operator = saved);
  }

  Future<void> _qr(bool isAdmin) async {
    final o = _operator!;
    final repo = ref.read(operatorsRepositoryProvider);
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => QrCodeDialog(
        title: o.fullName,
        filename: 'qr-${o.fullName}.png',
        issuedAt: o.qrIssuedAt,
        loadPng: () => repo.qrPng(o.id),
        reissueWarning: tr('Obecna karta przestanie działać od razu. Trzeba będzie wydrukować nową.'),
        onReissue: isAdmin
            ? () async {
                final fresh = await repo.reissueQr(o.id);
                return (fresh.qrIssuedAt, null);
              }
            : null,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openPermit(int permitId) async {
    try {
      final permit = await ref.read(permitsRepositoryProvider).get(permitId);
      if (!mounted) return;
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => PermitDialog(permit: permit),
      );
      if (changed == true) await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _addPermit() async {
    final o = _operator!;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => PermitDialog(operatorId: o.id, operatorName: o.fullName),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final o = _operator;
    return Scaffold(
      appBar: AppBar(
        title: Text(o?.fullName ?? tr('Operator')),
        actions: [
          if (o != null)
            IconButton(tooltip: tr('Kod QR'), onPressed: () => _qr(isAdmin), icon: const Icon(Icons.qr_code_2)),
          if (o != null)
            ExportButton(path: '/reports/operators/${o.id}/history.xlsx', tooltip: tr('Historia operatora (Excel)')),
          if (o != null && isAdmin) IconButton(tooltip: tr('Edytuj'), onPressed: _edit, icon: const Icon(Icons.edit)),
        ],
      ),
      floatingActionButton: o != null && isAdmin
          ? FloatingActionButton.extended(
              onPressed: _addPermit,
              icon: const Icon(Icons.add),
              label: Text(tr('Dodaj uprawnienie')),
            )
          : null,
      body: o == null
          ? Center(
              child: _error != null
                  ? Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(o.employer?.name ?? '—'),
                        subtitle: Text(tr('Pracodawca')),
                        trailing: PermitStatusChip(status: o.permitStatus),
                      ),
                      ListTile(
                        leading: const Icon(Icons.credit_card),
                        title: Text(o.hysterCardNumber ?? '—'),
                        subtitle: Text(tr('Nr karty Hyster Tracker')),
                      ),
                      ListTile(
                        leading: Icon(o.isActive ? Icons.check_circle_outline : Icons.block),
                        title: Text(o.isActive ? tr('Aktywny') : tr('Nieaktywny')),
                        subtitle: Text(
                          tr('{name} · kod QR wydany {qrIssuedAt}', {
                            'name': o.site.name,
                            'qrIssuedAt': formatDateTime(o.qrIssuedAt),
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(tr('Uprawnienia'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (o.permits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(isAdmin ? tr('Brak uprawnień — dodaj pierwsze.') : tr('Brak uprawnień.')),
                  ),
                for (final p in o.permits)
                  Card(
                    child: ListTile(
                      onTap: () => _openPermit(p.id),
                      title: Text(tr('{number} · {name}', {'number': p.number, 'name': p.category.name})),
                      subtitle: Text('${validityText(p)}\n${p.truckTypes.map((t) => t.name).join(', ')}'),
                      isThreeLine: true,
                      trailing: PermitStatusChip(status: p.status, daysLeft: p.daysLeft),
                    ),
                  ),
              ],
            ),
    );
  }
}
