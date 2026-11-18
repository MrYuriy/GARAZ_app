import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'in_use_dialog.dart';

/// Manufacturers and their models (in "Słowniki"). Administrators add, rename
/// and delete; one used by trucks is deleted only after those trucks change.
class TruckCatalogView extends ConsumerStatefulWidget {
  const TruckCatalogView({super.key, required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<TruckCatalogView> createState() => _TruckCatalogViewState();
}

class _TruckCatalogViewState extends ConsumerState<TruckCatalogView> {
  List<TruckManufacturer>? _items;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(truckCatalogRepositoryProvider).list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Ask for a name and save it with [save]; reloads on success.
  Future<void> _name(String title, String label, Future<void> Function(String) save, [String? current]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NameDialog(title: title, label: label, initial: current, save: save),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteMaker(TruckManufacturer m) async {
    final models = m.models.isEmpty ? '' : ' razem z modelami (${m.models.length})';
    if (!await _confirm('Usunąć producenta ${m.name}$models?')) return;
    if (!mounted) return;
    final repo = ref.read(truckCatalogRepositoryProvider);
    final deleted = await deleteWithTruckCheck(
      context,
      what: 'producent ${m.name}',
      delete: () => repo.deleteManufacturer(m.id),
      uses: (t) => t.manufacturer?.id == m.id,
    );
    if (deleted) _snack('Usunięto producenta ${m.name}.');
    await _load();
  }

  Future<void> _deleteModel(TruckManufacturer m, TruckModelEntry model) async {
    if (!await _confirm('Usunąć model ${m.name} ${model.name}?')) return;
    if (!mounted) return;
    final repo = ref.read(truckCatalogRepositoryProvider);
    final deleted = await deleteWithTruckCheck(
      context,
      what: 'model ${model.name}',
      delete: () => repo.deleteModel(model.id),
      uses: (t) => t.model?.id == model.id,
    );
    if (deleted) _snack('Usunięto model ${model.name}.');
    await _load();
  }

  Future<bool> _confirm(String question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    return ok ?? false;
  }

  String _uses(int n) => n == 0 ? 'nieużywany' : 'wózki: $n';

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(truckCatalogRepositoryProvider);
    final items = _items ?? const <TruckManufacturer>[];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Wózki wybierają producenta i model z tej listy.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.canEdit)
                FilledButton.tonalIcon(
                  onPressed: () => _name('Nowy producent', 'Nazwa producenta', repo.createManufacturer),
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj producenta'),
                ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        Expanded(
          child: items.isEmpty && !_loading
              ? Center(child: Text(widget.canEdit ? 'Brak producentów — dodaj pierwszego.' : 'Brak producentów.'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final m in items)
                      ExpansionTile(
                        key: PageStorageKey('maker-${m.id}'),
                        leading: const Icon(Icons.factory_outlined),
                        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Modele: ${m.models.length} · ${_uses(m.truckCount)}'),
                        trailing: widget.canEdit
                            ? Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Zmień nazwę',
                                    onPressed: () => _name(
                                      'Producent',
                                      'Nazwa producenta',
                                      (n) => repo.renameManufacturer(m.id, n),
                                      m.name,
                                    ),
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: 'Usuń producenta',
                                    onPressed: () => _deleteMaker(m),
                                    icon: Icon(Icons.delete_outline, color: scheme.error),
                                  ),
                                  const Icon(Icons.expand_more),
                                ],
                              )
                            : null,
                        childrenPadding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
                        children: [
                          for (final model in m.models)
                            ListTile(
                              dense: true,
                              title: Text(model.name),
                              subtitle: Text(_uses(model.truckCount)),
                              trailing: widget.canEdit
                                  ? Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: 'Zmień nazwę',
                                          onPressed: () => _name(
                                            'Model (${m.name})',
                                            'Nazwa modelu',
                                            (n) => repo.renameModel(model.id, n),
                                            model.name,
                                          ),
                                          icon: const Icon(Icons.edit, size: 20),
                                        ),
                                        IconButton(
                                          tooltip: 'Usuń model',
                                          onPressed: () => _deleteModel(m, model),
                                          icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          if (m.models.isEmpty) const ListTile(dense: true, title: Text('Brak modeli.')),
                          if (widget.canEdit)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _name('Nowy model (${m.name})', 'Nazwa modelu', (n) => repo.createModel(m.id, n)),
                                icon: const Icon(Icons.add),
                                label: const Text('Dodaj model'),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, required this.save, this.initial});

  final String title;
  final String label;
  final String? initial;
  final Future<void> Function(String) save;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Podaj nazwę.');
      return;
    }
    if (name == widget.initial) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final text = e.toString().startsWith('Taki rekord') ? 'Taka nazwa już jest na liście.' : e.toString();
      if (mounted) setState(() => _error = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(labelText: widget.label, errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Zapisz')),
      ],
    );
  }
}
