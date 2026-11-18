import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'permit_widgets.dart';

/// Add a permit to an operator ([permit] == null), or open one: administrators
/// edit it and its scanned document, managers only read. Pops true when
/// anything was saved.
class PermitDialog extends ConsumerStatefulWidget {
  const PermitDialog({super.key, this.permit, this.operatorId, this.operatorName})
    : assert(permit != null || operatorId != null);

  final Permit? permit;
  final int? operatorId;
  final String? operatorName;

  @override
  ConsumerState<PermitDialog> createState() => _PermitDialogState();
}

class _PermitDialogState extends ConsumerState<PermitDialog> {
  final _form = GlobalKey<FormState>();
  late Permit? _permit = widget.permit;
  late final _number = TextEditingController(text: _permit?.number);
  late final _basisName = TextEditingController(text: _permit?.basisName);
  late final _basisNumber = TextEditingController(text: _permit?.basisNumber);
  final _comment = TextEditingController();
  late int? _categoryId = _permit?.category.id;
  late final Set<int> _types = {...?_permit?.truckTypes.map((t) => t.id)};
  late DateTime? _issuedOn = _permit?.issuedOn ?? DateUtils.dateOnly(DateTime.now());
  late DateTime? _validUntil = _permit?.validUntil;
  late DateTime? _basisDate = _permit?.basisDate;
  late PermitStatus _status = _permit?.status ?? PermitStatus.active;

  List<DictionaryEntry>? _categories;
  List<DictionaryEntry>? _truckTypes;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  bool get _isNew => _permit == null;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    for (final c in [_number, _basisName, _basisNumber, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    final repo = ref.read(dictionariesRepositoryProvider);
    try {
      final categories = await repo.list(DictionaryKind.permitCategories);
      final types = await repo.list(DictionaryKind.truckTypes);
      if (mounted) {
        setState(() {
          _categories = categories;
          _truckTypes = types;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String? _nullIfBlank(String v) => v.trim().isEmpty ? null : v.trim();
  String? _day(DateTime? d) => d == null ? null : formatDay(d);

  Future<DateTime?> _pick(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_types.isEmpty) {
      setState(() => _error = 'Zaznacz co najmniej jeden rodzaj wózka.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(permitsRepositoryProvider);
    final typeIds = [
      for (final t in _truckTypes ?? const <DictionaryEntry>[])
        if (_types.contains(t.id)) t.id,
      // Ones the permit had that were switched off since.
      for (final t in _permit?.truckTypes ?? const <EntryRef>[])
        if (_types.contains(t.id) && !(_truckTypes ?? const []).any((e) => e.id == t.id)) t.id,
    ];
    try {
      if (_isNew) {
        await repo.create({
          'operator_id': widget.operatorId,
          'number': _number.text.trim(),
          'category_id': _categoryId,
          'truck_type_ids': typeIds,
          'issued_on': _day(_issuedOn),
          'valid_until': _day(_validUntil),
          'basis_name': _nullIfBlank(_basisName.text),
          'basis_number': _nullIfBlank(_basisNumber.text),
          'basis_date': _day(_basisDate),
        });
      } else {
        final p = _permit!;
        final oldTypes = {...p.truckTypes.map((t) => t.id)};
        final statusChanged = _status != p.status;
        final changes = <String, dynamic>{
          if (_number.text.trim() != p.number) 'number': _number.text.trim(),
          if (_categoryId != p.category.id) 'category_id': _categoryId,
          if (oldTypes.length != _types.length || !oldTypes.containsAll(_types)) 'truck_type_ids': typeIds,
          if (_day(_issuedOn) != _day(p.issuedOn)) 'issued_on': _day(_issuedOn),
          if (_day(_validUntil) != _day(p.validUntil)) 'valid_until': _day(_validUntil),
          if (_nullIfBlank(_basisName.text) != p.basisName) 'basis_name': _nullIfBlank(_basisName.text),
          if (_nullIfBlank(_basisNumber.text) != p.basisNumber) 'basis_number': _nullIfBlank(_basisNumber.text),
          if (_day(_basisDate) != _day(p.basisDate)) 'basis_date': _day(_basisDate),
          if (statusChanged) 'status': _status.api,
          if (statusChanged && _comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
        };
        if (changes.isNotEmpty) await repo.update(p.id, changes);
        if (changes.isNotEmpty) _changed = true;
      }
      if (mounted) Navigator.of(context).pop(_isNew || _changed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----- the scanned document -----

  Future<void> _attach() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return;
    await _documentAction(() async {
      final bytes = await file.readAsBytes();
      return ref.read(permitsRepositoryProvider).attachDocument(_permit!.id, bytes, file.name);
    }, 'Dołączono skan dokumentu.');
  }

  Future<void> _removeDocument() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć skan dokumentu?'),
        content: const Text('Plik zostanie usunięty. Dane dokumentu (nazwa, numer, data) zostają.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    await _documentAction(
      () => ref.read(permitsRepositoryProvider).removeDocument(_permit!.id),
      'Usunięto skan dokumentu.',
    );
  }

  Future<void> _documentAction(Future<Permit> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final permit = await action();
      if (!mounted) return;
      setState(() {
        _permit = permit;
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocument() async {
    final doc = _permit!.document!;
    try {
      final bytes = await ref.read(permitsRepositoryProvider).document(_permit!.id);
      final opened = await openBytes(bytes, doc.contentType);
      if (!opened) await saveBytes(bytes, doc.filename, doc.contentType);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ----- layout -----

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final readOnly = !isAdmin;
    final p = _permit;
    final operatorName = p?.operatorName ?? widget.operatorName;
    final statusChanged = p != null && _status != p.status;

    final categories = [
      for (final c in _categories ?? const <DictionaryEntry>[]) DropdownMenuItem(value: c.id, child: Text(c.name)),
      if (p != null && !(_categories ?? const []).any((c) => c.id == p.category.id))
        DropdownMenuItem(value: p.category.id, child: Text('${p.category.name} (wyłączona)')),
    ];
    final typeChoices = <EntryRef>[
      for (final t in _truckTypes ?? const <DictionaryEntry>[]) EntryRef(t.id, t.name),
      for (final t in p?.truckTypes ?? const <EntryRef>[])
        if (!(_truckTypes ?? const []).any((e) => e.id == t.id)) EntryRef(t.id, '${t.name} (wyłączony)'),
    ];

    return AlertDialog(
      title: Text(_isNew ? 'Nowe uprawnienie' : 'Uprawnienie ${p!.number}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_categories == null) const LinearProgressIndicator(),
                if (operatorName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      [operatorName, ?p?.operatorEmployer].join(' · '),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                if (p != null)
                  Row(
                    children: [
                      PermitStatusChip(status: p.status, daysLeft: p.daysLeft),
                      const SizedBox(width: 8),
                      Flexible(child: Text(validityText(p))),
                    ],
                  ),
                if (_categories != null && _categories!.isEmpty && _isNew)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Najpierw dodaj kategorie uprawnień w zakładce „Słowniki”.'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _number,
                  readOnly: readOnly,
                  autofocus: _isNew,
                  decoration: const InputDecoration(labelText: 'Nr pozwolenia', helperText: 'Np. 001/2026.'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Podaj numer' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Kategoria'),
                  items: categories,
                  onChanged: readOnly ? null : (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? 'Wybierz kategorię' : null,
                ),
                const SizedBox(height: 12),
                Text('Rodzaje wózków', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                if (typeChoices.isEmpty && _truckTypes != null)
                  const Text('Brak typów wózków — dodaj je w zakładce „Słowniki”.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in typeChoices)
                      FilterChip(
                        label: Text(t.name),
                        selected: _types.contains(t.id),
                        onSelected: readOnly
                            ? null
                            : (on) => setState(() => on ? _types.add(t.id) : _types.remove(t.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Data wydania',
                        value: _issuedOn,
                        onPick: readOnly
                            ? null
                            : () async {
                                final d = await _pick(_issuedOn);
                                if (d != null) setState(() => _issuedOn = d);
                              },
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Ważne do',
                        value: _validUntil,
                        onPick: readOnly
                            ? null
                            : () async {
                                final d = await _pick(_validUntil ?? _issuedOn);
                                if (d != null) setState(() => _validUntil = d);
                              },
                        required: true,
                        validator: (_) => _validUntil != null && _issuedOn != null && _validUntil!.isBefore(_issuedOn!)
                            ? 'Przed datą wydania'
                            : null,
                      ),
                    ),
                  ],
                ),
                if (p != null && !readOnly) ...[
                  const SizedBox(height: 12),
                  if (p.status == PermitStatus.expired)
                    const Text(
                      'Wygasłe — status nadaje system. Przesuń datę „Ważne do”, aby uprawnienie znów było aktywne.',
                    )
                  else
                    DropdownButtonFormField<PermitStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final s in [PermitStatus.active, PermitStatus.suspended])
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) => setState(() => _status = s!),
                    ),
                  if (statusChanged) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _comment,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Komentarz do zmiany statusu (opcjonalnie)',
                        helperText: 'Np. „zawieszone do ponownego szkolenia”. Trafia do dziennika.',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Text('Dokument-podstawa', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _basisName,
                  readOnly: readOnly,
                  decoration: const InputDecoration(labelText: 'Nazwa (np. zaświadczenie UDT)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _basisNumber,
                        readOnly: readOnly,
                        decoration: const InputDecoration(labelText: 'Numer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Data',
                        value: _basisDate,
                        onPick: readOnly
                            ? null
                            : () async {
                                final d = await _pick(_basisDate);
                                if (d != null) setState(() => _basisDate = d);
                              },
                        onClear: readOnly || _basisDate == null ? null : () => setState(() => _basisDate = null),
                      ),
                    ),
                  ],
                ),
                if (p != null) ...[const SizedBox(height: 12), _documentRow(p, readOnly)],
                if (_isNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Skan dokumentu dołączysz po zapisaniu uprawnienia.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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
        if (readOnly)
          FilledButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Zamknij'))
        else ...[
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
            child: Text(_isNew ? 'Anuluj' : 'Zamknij'),
          ),
          FilledButton(
            onPressed: _busy || _categories == null ? null : _save,
            child: Text(_isNew ? 'Dodaj' : 'Zapisz'),
          ),
        ],
      ],
    );
  }

  Widget _documentRow(Permit p, bool readOnly) {
    final doc = p.document;
    return Row(
      children: [
        Icon(doc == null ? Icons.description_outlined : Icons.attach_file),
        const SizedBox(width: 8),
        Expanded(
          child: doc == null
              ? const Text('Brak skanu dokumentu.')
              : Text('${doc.filename} (${(doc.size / 1024).ceil()} KB)', overflow: TextOverflow.ellipsis),
        ),
        if (doc != null) TextButton(onPressed: _busy ? null : _openDocument, child: const Text('Otwórz')),
        if (!readOnly)
          TextButton(onPressed: _busy ? null : _attach, child: Text(doc == null ? 'Dołącz skan' : 'Zmień')),
        if (!readOnly && doc != null)
          IconButton(
            tooltip: 'Usuń skan',
            onPressed: _busy ? null : _removeDocument,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
  }
}

/// A date shown as text; tapping it opens the calendar.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.required = false,
    this.validator,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final bool required;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(value),
      initialValue: value == null ? '' : formatDay(value),
      readOnly: true,
      onTap: onPick,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: onClear != null
            ? IconButton(tooltip: 'Wyczyść', onPressed: onClear, icon: const Icon(Icons.clear))
            : const Icon(Icons.calendar_today_outlined),
      ),
      validator: (v) {
        if (required && value == null) return 'Wybierz datę';
        return validator?.call(v);
      },
    );
  }
}
