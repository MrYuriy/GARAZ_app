import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/i18n.dart';

/// Add a truck ([truck] == null) or edit one. Pops the saved [Truck], or
/// [TruckFormDialog.deleted] when the administrator deleted it.
class TruckFormDialog extends ConsumerStatefulWidget {
  const TruckFormDialog({super.key, this.truck});

  final Truck? truck;

  /// What the dialog pops after a delete (a truck that no longer exists).
  static final deleted = Truck(
    id: -1,
    number: '',
    manufacturer: null,
    model: null,
    status: TruckStatus.inactive,
    site: EntryRef(-1, ''),
    truckType: EntryRef(-1, ''),
    qrUrl: '',
    qrIssuedAt: DateTime.utc(1970),
  );

  @override
  ConsumerState<TruckFormDialog> createState() => _TruckFormDialogState();
}

class _TruckFormDialogState extends ConsumerState<TruckFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.truck?.number);
  late int? _makerId = widget.truck?.manufacturer?.id;
  late int? _modelId = widget.truck?.model?.id;
  final _comment = TextEditingController();
  late int? _typeId = widget.truck?.truckType.id;
  late int? _siteId = widget.truck?.site.id;
  late TruckStatus _status = widget.truck?.status ?? TruckStatus.active;

  List<DictionaryEntry>? _types;
  List<DictionaryEntry>? _sites;
  List<TruckManufacturer>? _makers;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.truck == null;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    for (final c in [_number, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    final repo = ref.read(dictionariesRepositoryProvider);
    try {
      final types = await repo.list(DictionaryKind.truckTypes);
      final sites = await repo.list(DictionaryKind.sites);
      final makers = await ref.read(truckCatalogRepositoryProvider).list();
      if (!mounted) return;
      setState(() {
        _types = types;
        _sites = sites;
        _makers = makers;
        // A single site needs no choice.
        if (_isNew && sites.length == 1) _siteId = sites.first.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// The active entries, plus the truck's current one even if it was switched off since.
  List<DropdownMenuItem<int>> _options(List<DictionaryEntry>? entries, EntryRef? current) {
    final items = [
      for (final e in entries ?? const <DictionaryEntry>[]) DropdownMenuItem(value: e.id, child: Text(e.name)),
    ];
    if (current != null && !items.any((i) => i.value == current.id)) {
      items.add(DropdownMenuItem(value: current.id, child: Text(tr('{name} (wyłączony)', {'name': current.name}))));
    }
    return items;
  }

  List<TruckModelEntry> get _modelsOfMaker =>
      _makers?.where((m) => m.id == _makerId).firstOrNull?.models ?? const <TruckModelEntry>[];

  Future<void> _delete() async {
    final t = widget.truck!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Usunąć wózek {number}?', {'number': t.number})),
        content: Text(
          tr(
            'Usuń tylko wózek dodany przez pomyłkę. Wózek wycofany z floty oznacz statusem „Nieaktywny” — zostanie jego historia.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Usuń wózek')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(trucksRepositoryProvider).delete(t.id);
      if (mounted) Navigator.of(context).pop(TruckFormDialog.deleted);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(trucksRepositoryProvider);
    try {
      final Truck saved;
      if (_isNew) {
        saved = await repo.create({
          'number': _number.text.trim(),
          'manufacturer_id': ?_makerId,
          'model_id': ?_modelId,
          'truck_type_id': _typeId,
          'site_id': ?_siteId,
        });
      } else {
        final t = widget.truck!;
        final changes = <String, dynamic>{
          if (_number.text.trim() != t.number) 'number': _number.text.trim(),
          if (_makerId != t.manufacturer?.id) 'manufacturer_id': _makerId,
          if (_makerId != t.manufacturer?.id || _modelId != t.model?.id) 'model_id': _modelId,
          if (_typeId != t.truckType.id) 'truck_type_id': _typeId,
          if (_siteId != t.site.id) 'site_id': _siteId,
          if (_status != t.status) 'status': _status.api,
          if (_status != t.status && _comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
        };
        if (changes.isEmpty) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        saved = await repo.update(t.id, changes);
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
    final t = widget.truck;
    final noTypes = _types != null && _types!.isEmpty && t == null;
    final statusChanged = t != null && _status != t.status;

    return AlertDialog(
      title: Text(_isNew ? tr('Nowy wózek') : tr('Wózek {number}', {'number': t!.number})),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_types == null) const LinearProgressIndicator(),
                if (noTypes)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(tr('Najpierw dodaj typy wózków w zakładce „Słowniki”.')),
                  ),
                TextFormField(
                  controller: _number,
                  autofocus: _isNew,
                  decoration: InputDecoration(
                    labelText: tr('Numer wózka'),
                    helperText: tr('Np. numer floty na wózku.'),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Podaj numer') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _typeId,
                  decoration: InputDecoration(labelText: tr('Typ wózka')),
                  items: _options(_types, t?.truckType),
                  onChanged: (v) => setState(() => _typeId = v),
                  validator: (v) => v == null ? tr('Wybierz typ') : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey('maker-${_makers?.length}'),
                        initialValue: _makerId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Producent')),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (final m in _makers ?? const <TruckManufacturer>[])
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: (v) => setState(() {
                          if (v != _makerId) _modelId = null;
                          _makerId = v;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        // Rebuilt when the manufacturer changes, so the choice resets.
                        key: ValueKey('model-$_makerId-${_makers?.length}'),
                        initialValue: _modelId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Model')),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (final m in _modelsOfMaker) DropdownMenuItem(value: m.id, child: Text(m.name)),
                        ],
                        onChanged: _makerId == null ? null : (v) => setState(() => _modelId = v),
                      ),
                    ),
                  ],
                ),
                if (_makers != null && _makers!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('Producentów i modele dodasz w „Słowniki” → „Producenci i modele”.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                // One site: nothing to choose, the server fills it in.
                if ((_sites?.length ?? 0) > 1 || (t != null && (_sites?.length ?? 0) != 1)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _siteId,
                    decoration: InputDecoration(labelText: tr('Lokalizacja')),
                    items: _options(_sites, t?.site),
                    onChanged: (v) => setState(() => _siteId = v),
                    validator: (v) => v == null ? tr('Wybierz lokalizację') : null,
                  ),
                ],
                if (!_isNew) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TruckStatus>(
                    initialValue: _status,
                    decoration: InputDecoration(labelText: tr('Status')),
                    items: [for (final s in TruckStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                    onChanged: (s) => setState(() => _status = s!),
                  ),
                  if (statusChanged) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _comment,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr('Komentarz do zmiany statusu (opcjonalnie)'),
                        helperText: tr('Np. „naprawa zakończona”. Trafia do dziennika.'),
                      ),
                    ),
                  ],
                ],
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
        if (!_isNew)
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            label: Text(tr('Usuń'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Anuluj'))),
        FilledButton(
          onPressed: _busy || _types == null || _makers == null || noTypes ? null : _save,
          child: Text(_isNew ? tr('Dodaj') : tr('Zapisz')),
        ),
      ],
    );
  }
}
