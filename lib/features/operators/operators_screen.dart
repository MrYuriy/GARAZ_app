import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import '../../core/widgets/filter_bar.dart';
import '../permits/permit_widgets.dart';
import 'operator_form_dialog.dart';
import '../../core/i18n.dart';

/// The operators register. Everyone signed in reads it and prints QR cards;
/// administrators add and edit. A row opens the operator with their permits.
class OperatorsScreen extends ConsumerStatefulWidget {
  const OperatorsScreen({super.key});

  @override
  ConsumerState<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends ConsumerState<OperatorsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _onlyActive = true;
  PageOf<Operator>? _page;
  final Set<int> _selected = {};
  bool _loading = false;
  bool _printing = false;
  String? _error;

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
      final page = await ref
          .read(operatorsRepositoryProvider)
          .list(query: _search.text.trim(), isActive: _onlyActive ? true : null);
      if (mounted) {
        setState(() {
          _page = page;
          _selected.retainAll(page.items.map((o) => o.id));
        });
      }
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

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final saved = await showDialog<Operator>(context: context, builder: (_) => const OperatorFormDialog());
    if (saved == null || !mounted) return;
    _snack(tr('Dodano operatora {fullName}. Teraz dodaj mu uprawnienie.', {'fullName': saved.fullName}));
    await context.push('/operators/${saved.id}');
    await _load();
  }

  Future<void> _open(Operator o) async {
    await context.push('/operators/${o.id}');
    await _load();
  }

  Future<void> _printCards() async {
    setState(() => _printing = true);
    try {
      final ids = [
        for (final o in _page?.items ?? const <Operator>[])
          if (_selected.contains(o.id)) o.id,
      ];
      final pdf = await ref.read(operatorsRepositoryProvider).cardsPdf(ids);
      final saved = await saveBytes(pdf, 'karty-operatorow.pdf', 'application/pdf');
      _snack(
        saved
            ? tr('Pobrano PDF z kartami ({idsCount}).', {'idsCount': ids.length})
            : tr('Nie udało się zapisać pliku.'),
      );
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final items = _page?.items ?? const <Operator>[];
    final allSelected = items.isNotEmpty && _selected.length == items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Operatorzy')),
        actions: [
          if (_selected.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: _printing ? null : _printCards,
              icon: const Icon(Icons.print_outlined),
              label: Text(tr('Karty QR ({selectedCount})', {'selectedCount': _selected.length})),
            ),
          ExportButton(
            path: '/reports/operators.xlsx',
            query: () => {
              if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(),
              if (_onlyActive) 'is_active': true,
            },
          ),
          IconButton(tooltip: tr('Odśwież'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt),
              label: Text(tr('Dodaj operatora')),
            )
          : null,
      body: Column(
        children: [
          FilterBar(
            searchController: _search,
            onSearch: _onSearch,
            searchHint: tr('Szukaj: nazwisko, nr karty Hyster'),
            groups: () => [
              FilterGroup.toggle(
                title: tr('Tylko aktywni'),
                value: _onlyActive,
                activeLabel: _onlyActive ? null : tr('Także nieaktywni'),
                onChanged: (v) {
                  setState(() => _onlyActive = v);
                  _load();
                },
              ),
            ],
            total: _page?.total,
          ),
          if (_loading || _printing) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (items.isNotEmpty)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr('Zaznacz wszystkich (do druku kart QR)')),
              value: allSelected,
              onChanged: (v) => setState(() {
                _selected.clear();
                if (v == true) _selected.addAll(items.map((o) => o.id));
              }),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? Center(child: Text(isAdmin ? tr('Brak operatorów — dodaj pierwszego.') : tr('Brak operatorów.')))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final o = items[i];
                      return _OperatorTile(
                        operator: o,
                        selected: _selected.contains(o.id),
                        onSelect: (v) => setState(() => v ? _selected.add(o.id) : _selected.remove(o.id)),
                        onTap: () => _open(o),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OperatorTile extends StatelessWidget {
  const _OperatorTile({required this.operator, required this.selected, required this.onSelect, required this.onTap});

  final Operator operator;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = operator;
    // The permit that decides the status: the first one with the best status.
    final current = o.permits.where((p) => p.status == o.permitStatus).firstOrNull;
    final details = [
      ?o.employer?.name,
      if (o.hysterCardNumber != null) tr('Hyster {hysterCardNumber}', {'hysterCardNumber': o.hysterCardNumber}),
      if (current != null) validityText(current),
      if (!o.isActive) 'nieaktywny',
    ];
    return ListTile(
      onTap: onTap,
      leading: Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
      title: Text(
        o.fullName,
        style: TextStyle(fontWeight: FontWeight.w600, color: o.isActive ? null : Theme.of(context).colorScheme.outline),
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: PermitStatusChip(status: o.permitStatus, daysLeft: current?.daysLeft),
    );
  }
}
