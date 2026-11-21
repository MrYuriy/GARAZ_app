import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import '../../core/widgets/filter_bar.dart';
import 'permit_dialog.dart';
import 'permit_widgets.dart';

enum _Filter {
  all('Wszystkie'),
  expiring('Wygasające ($expiringSoonDays dni)'),
  suspended('Zawieszone'),
  expired('Wygasłe'),
  archived('Archiwum');

  const _Filter(this.label);

  final String label;
}

/// The permits register across operators, soonest to expire first.
/// New permits are added from the operator's page.
class PermitsScreen extends ConsumerStatefulWidget {
  const PermitsScreen({super.key});

  @override
  ConsumerState<PermitsScreen> createState() => _PermitsScreenState();
}

class _PermitsScreenState extends ConsumerState<PermitsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  _Filter _filter = _Filter.all;
  PageOf<Permit>? _page;
  // Chosen for printing.
  final Set<int> _selected = {};
  bool _printing = false;
  bool _loading = false;
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

  PermitStatus? get _status => switch (_filter) {
    _Filter.expiring => PermitStatus.active,
    _Filter.suspended => PermitStatus.suspended,
    _Filter.expired => PermitStatus.expired,
    _Filter.archived => PermitStatus.archived,
    _Filter.all => null,
  };

  /// The list's filters, for the Excel file.
  Map<String, dynamic> _exportQuery() => {
    if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(),
    'status': ?_status?.api,
    if (_filter == _Filter.expiring) 'expiring_within_days': expiringSoonDays,
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(permitsRepositoryProvider)
          .list(
            query: _search.text.trim(),
            status: _status,
            expiringWithinDays: _filter == _Filter.expiring ? expiringSoonDays : null,
          );
      if (mounted) {
        setState(() {
          _page = page;
          _selected.retainAll(page.items.where((p) => p.status != PermitStatus.archived).map((p) => p.id));
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

  Future<void> _open(Permit p) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => PermitDialog(permit: p),
    );
    if (changed == true) await _load();
  }

  Future<void> _printCards() async {
    setState(() => _printing = true);
    try {
      final ids = [
        for (final p in _page?.items ?? const <Permit>[])
          if (_selected.contains(p.id)) p.id,
      ];
      final pdf = await ref.read(permitsRepositoryProvider).cardsPdf(ids);
      final saved = await saveBytes(pdf, 'upowaznienia.pdf', 'application/pdf');
      _snack(saved ? 'Pobrano PDF z upoważnieniami (${ids.length}).' : 'Nie udało się zapisać pliku.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _setFilter(_Filter f) {
    setState(() => _filter = f);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _page?.items ?? const <Permit>[];
    final printable = [
      for (final p in items)
        if (p.status != PermitStatus.archived) p.id,
    ];
    final allSelected = printable.isNotEmpty && _selected.length == printable.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uprawnienia'),
        actions: [
          if (_selected.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: _printing ? null : _printCards,
              icon: const Icon(Icons.print_outlined),
              label: Text('Drukuj (${_selected.length})'),
            ),
          ExportButton(path: '/reports/permits.xlsx', query: _exportQuery),
          IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          FilterBar(
            searchController: _search,
            onSearch: _onSearch,
            searchHint: 'Szukaj: nr pozwolenia, nazwisko',
            groups: () => [
              FilterGroup(
                title: 'Pokaż',
                activeLabel: _filter == _Filter.all ? null : _filter.label,
                onClear: () => _setFilter(_Filter.all),
                options: [
                  for (final f in _Filter.values)
                    FilterOption(f.label, selected: _filter == f, onSelected: () => _setFilter(f)),
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
          if (printable.isNotEmpty)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Zaznacz wszystkie do druku (8 na arkuszu A4)'),
              value: allSelected,
              onChanged: (v) => setState(() {
                _selected.clear();
                if (v == true) _selected.addAll(printable);
              }),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? const Center(child: Text('Brak uprawnień. Nowe dodasz na stronie operatora.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = items[i];
                      final archived = p.status == PermitStatus.archived;
                      return ListTile(
                        onTap: () => _open(p),
                        leading: Checkbox(
                          value: _selected.contains(p.id),
                          onChanged: archived
                              ? null
                              : (v) => setState(() => v == true ? _selected.add(p.id) : _selected.remove(p.id)),
                        ),
                        title: Text('${p.operatorName} · ${p.number}'),
                        subtitle: Text(
                          [p.category.name, p.truckTypes.map((t) => t.name).join(', '), validityText(p)].join(' · '),
                        ),
                        trailing: PermitStatusChip(status: p.status, daysLeft: p.daysLeft),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
