import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import 'truck_form_dialog.dart';
import 'truck_qr_dialog.dart';

/// The fleet register. Everyone signed in reads it and prints QR labels;
/// administrators add and edit trucks.
class TrucksScreen extends ConsumerStatefulWidget {
  const TrucksScreen({super.key});

  @override
  ConsumerState<TrucksScreen> createState() => _TrucksScreenState();
}

class _TrucksScreenState extends ConsumerState<TrucksScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  TruckStatus? _status;
  PageOf<Truck>? _page;
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
      final page = await ref.read(trucksRepositoryProvider).list(query: _search.text.trim(), status: _status);
      if (mounted) {
        setState(() {
          _page = page;
          // Keep only what is still on screen selected.
          _selected.retainAll(page.items.map((t) => t.id));
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

  Future<void> _openForm([Truck? truck]) async {
    final saved = await showDialog<Truck>(
      context: context,
      builder: (_) => TruckFormDialog(truck: truck),
    );
    if (identical(saved, TruckFormDialog.deleted)) {
      _snack('Usunięto wózek ${truck!.number}');
      await _load();
    } else if (saved != null) {
      _snack(truck == null ? 'Dodano wózek ${saved.number}' : 'Zapisano wózek ${saved.number}');
      await _load();
    }
  }

  Future<void> _openQr(Truck truck) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => TruckQrDialog(truck: truck),
    );
    if (changed == true) await _load();
  }

  Future<void> _printLabels() async {
    setState(() => _printing = true);
    try {
      final items = _page?.items ?? const <Truck>[];
      final ids = items.where((t) => _selected.contains(t.id)).map((t) => t.id).toList();
      final pdf = await ref.read(trucksRepositoryProvider).labelsPdf(ids);
      final saved = await saveBytes(pdf, 'etykiety-wozkow.pdf', 'application/pdf');
      _snack(saved ? 'Pobrano PDF z etykietami (${ids.length}).' : 'Nie udało się zapisać pliku.');
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final items = _page?.items ?? const <Truck>[];
    final allSelected = items.isNotEmpty && _selected.length == items.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wózki'),
        actions: [
          if (_selected.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: _printing ? null : _printLabels,
              icon: const Icon(Icons.print_outlined),
              label: Text('Etykiety QR (${_selected.length})'),
            ),
          ExportButton(
            path: '/reports/trucks.xlsx',
            query: () => {if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(), 'status': ?_status?.api},
          ),
          IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj wózek'),
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
                  width: 300,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Szukaj: numer, producent, model',
                    ),
                  ),
                ),
                DropdownButton<TruckStatus?>(
                  value: _status,
                  hint: const Text('Wszystkie statusy'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Wszystkie statusy')),
                    for (final s in TruckStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (s) {
                    setState(() => _status = s);
                    _load();
                  },
                ),
                if (_page != null) Text('Razem: ${_page!.total}'),
              ],
            ),
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
              title: const Text('Zaznacz wszystkie (do druku etykiet)'),
              value: allSelected,
              onChanged: (v) => setState(() {
                _selected.clear();
                if (v == true) _selected.addAll(items.map((t) => t.id));
              }),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? Center(child: Text(isAdmin ? 'Brak wózków — dodaj pierwszy.' : 'Brak wózków.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _TruckTile(
                      truck: items[i],
                      selected: _selected.contains(items[i].id),
                      onSelect: (v) => setState(() => v ? _selected.add(items[i].id) : _selected.remove(items[i].id)),
                      onTap: isAdmin ? () => _openForm(items[i]) : null,
                      onQr: () => _openQr(items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TruckTile extends StatelessWidget {
  const _TruckTile({
    required this.truck,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onQr,
  });

  final Truck truck;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback? onTap;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (truck.status) {
      TruckStatus.active => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TruckStatus.outOfService => (scheme.errorContainer, scheme.onErrorContainer),
      TruckStatus.inactive => (scheme.surfaceContainerHighest, scheme.outline),
    };
    return ListTile(
      onTap: onTap,
      leading: Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
      title: Text(truck.number, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [truck.truckType.name, if (truck.makeAndModel.isNotEmpty) truck.makeAndModel, truck.site.name].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(truck.status.label, style: TextStyle(color: fg)),
            backgroundColor: bg,
            side: BorderSide.none,
          ),
          IconButton(tooltip: 'Kod QR', onPressed: onQr, icon: const Icon(Icons.qr_code_2)),
        ],
      ),
    );
  }
}
