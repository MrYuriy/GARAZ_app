import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// Add a truck ([truck] == null) or edit one. Pops the saved [Truck].
class TruckFormDialog extends ConsumerStatefulWidget {
  const TruckFormDialog({super.key, this.truck});

  final Truck? truck;

  @override
  ConsumerState<TruckFormDialog> createState() => _TruckFormDialogState();
}

class _TruckFormDialogState extends ConsumerState<TruckFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.truck?.number);
  late final _manufacturer = TextEditingController(text: widget.truck?.manufacturer);
  late final _model = TextEditingController(text: widget.truck?.model);
  final _comment = TextEditingController();
  late int? _typeId = widget.truck?.truckType.id;
  late int? _siteId = widget.truck?.site.id;
  late TruckStatus _status = widget.truck?.status ?? TruckStatus.active;

  List<DictionaryEntry>? _types;
  List<DictionaryEntry>? _sites;
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
    for (final c in [_number, _manufacturer, _model, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    final repo = ref.read(dictionariesRepositoryProvider);
    try {
      final types = await repo.list(DictionaryKind.truckTypes);
      final sites = await repo.list(DictionaryKind.sites);
      if (!mounted) return;
      setState(() {
        _types = types;
        _sites = sites;
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
      items.add(DropdownMenuItem(value: current.id, child: Text('${current.name} (wyłączony)')));
    }
    return items;
  }

  String? _nullIfBlank(String v) => v.trim().isEmpty ? null : v.trim();

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
          'manufacturer': _nullIfBlank(_manufacturer.text),
          'model': _nullIfBlank(_model.text),
          'truck_type_id': _typeId,
          'site_id': ?_siteId,
        });
      } else {
        final t = widget.truck!;
        final changes = <String, dynamic>{
          if (_number.text.trim() != t.number) 'number': _number.text.trim(),
          if (_nullIfBlank(_manufacturer.text) != t.manufacturer) 'manufacturer': _nullIfBlank(_manufacturer.text),
          if (_nullIfBlank(_model.text) != t.model) 'model': _nullIfBlank(_model.text),
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
      title: Text(_isNew ? 'Nowy wózek' : 'Wózek ${t!.number}'),
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
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Najpierw dodaj typy wózków w zakładce „Słowniki”.'),
                  ),
                TextFormField(
                  controller: _number,
                  autofocus: _isNew,
                  decoration: const InputDecoration(labelText: 'Numer wózka', helperText: 'Np. numer floty na wózku.'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Podaj numer' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _typeId,
                  decoration: const InputDecoration(labelText: 'Typ wózka'),
                  items: _options(_types, t?.truckType),
                  onChanged: (v) => setState(() => _typeId = v),
                  validator: (v) => v == null ? 'Wybierz typ' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _manufacturer,
                        decoration: const InputDecoration(labelText: 'Producent'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Model'),
                      ),
                    ),
                  ],
                ),
                // One site: nothing to choose, the server fills it in.
                if ((_sites?.length ?? 0) > 1 || (t != null && (_sites?.length ?? 0) != 1)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(labelText: 'Lokalizacja'),
                    items: _options(_sites, t?.site),
                    onChanged: (v) => setState(() => _siteId = v),
                    validator: (v) => v == null ? 'Wybierz lokalizację' : null,
                  ),
                ],
                if (!_isNew) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TruckStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [for (final s in TruckStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                    onChanged: (s) => setState(() => _status = s!),
                  ),
                  if (statusChanged) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _comment,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Komentarz do zmiany statusu (opcjonalnie)',
                        helperText: 'Np. „naprawa zakończona”. Trafia do dziennika.',
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
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Anuluj')),
        FilledButton(
          onPressed: _busy || _types == null || noTypes ? null : _save,
          child: Text(_isNew ? 'Dodaj' : 'Zapisz'),
        ),
      ],
    );
  }
}
