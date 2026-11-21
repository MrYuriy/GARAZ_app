import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'permit_widgets.dart';
import '../../core/i18n.dart';

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
  late final _udt = TextEditingController(text: _permit?.udtNumber);
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
    for (final c in [_number, _basisName, _basisNumber, _udt, _comment]) {
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
      setState(() => _error = tr('Zaznacz co najmniej jeden rodzaj wózka.'));
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
          // Blank: the server gives the next number of the year.
          'number': _nullIfBlank(_number.text),
          'category_id': _categoryId,
          'udt_number': _nullIfBlank(_udt.text),
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
          if (_nullIfBlank(_udt.text) != p.udtNumber) 'udt_number': _nullIfBlank(_udt.text),
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

  // ----- renewal and the printed card -----

  Future<void> _renew() async {
    final p = _permit!;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RenewDialog(permit: p),
    );
    if (values == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final renewed = await ref.read(permitsRepositoryProvider).renew(p.id, values);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Wydano {number}. Poprzednie ({number2}) trafiło do archiwum.', {
              'number': renewed.number,
              'number2': p.number,
            }),
          ),
        ),
      );
      setState(() {
        _permit = renewed;
        _changed = true;
      });
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final p = _permit!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pdf = await ref.read(permitsRepositoryProvider).cardsPdf([p.id]);
      final opened = await openBytes(pdf, 'application/pdf');
      final saved =
          opened || await saveBytes(pdf, 'upowaznienie-${p.number.replaceAll('/', '-')}.pdf', 'application/pdf');
      if (!saved && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Nie udało się otworzyć ani zapisać pliku.'))));
      }
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
    }, tr('Dołączono skan dokumentu.'));
  }

  Future<void> _removeDocument() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Usunąć skan dokumentu?')),
        content: Text(tr('Plik zostanie usunięty. Dane dokumentu (nazwa, numer, data) zostają.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Usuń'))),
        ],
      ),
    );
    if (ok != true) return;
    await _documentAction(
      () => ref.read(permitsRepositoryProvider).removeDocument(_permit!.id),
      tr('Usunięto skan dokumentu.'),
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
    final p = _permit;
    final archived = p?.status == PermitStatus.archived;
    final readOnly = !isAdmin || archived;
    final operatorName = p?.operatorName ?? widget.operatorName;
    final statusChanged = p != null && _status != p.status;

    final categories = [
      for (final c in _categories ?? const <DictionaryEntry>[]) DropdownMenuItem(value: c.id, child: Text(c.name)),
      if (p != null && !(_categories ?? const []).any((c) => c.id == p.category.id))
        DropdownMenuItem(value: p.category.id, child: Text(tr('{name} (wyłączona)', {'name': p.category.name}))),
    ];
    final typeChoices = <EntryRef>[
      for (final t in _truckTypes ?? const <DictionaryEntry>[]) EntryRef(t.id, t.name),
      for (final t in p?.truckTypes ?? const <EntryRef>[])
        if (!(_truckTypes ?? const []).any((e) => e.id == t.id))
          EntryRef(t.id, tr('{name} (wyłączony)', {'name': t.name})),
    ];

    return AlertDialog(
      title: Text(_isNew ? tr('Nowe uprawnienie') : tr('Uprawnienie {number}', {'number': p!.number})),
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
                if (archived)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      tr('Zarchiwizowane — zastąpione przez odnowione uprawnienie z nowym numerem. Tylko do odczytu.'),
                    ),
                  ),
                if (_categories != null && _categories!.isEmpty && _isNew)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(tr('Najpierw dodaj kategorie uprawnień w zakładce „Słowniki”.')),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _number,
                  readOnly: readOnly,
                  decoration: InputDecoration(
                    labelText: tr('Nr uprawnienia'),
                    helperText: _isNew
                        ? tr(
                            'Zostaw puste — system nada kolejny numer roku (np. 001/{year}). Wpisz tylko przy przenoszeniu starego uprawnienia.',
                            {'year': DateTime.now().year},
                          )
                        : null,
                    helperMaxLines: 3,
                  ),
                  validator: (v) => !_isNew && (v ?? '').trim().isEmpty ? tr('Podaj numer') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  decoration: InputDecoration(labelText: tr('Kategoria')),
                  items: categories,
                  onChanged: readOnly ? null : (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? tr('Wybierz kategorię') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _udt,
                  readOnly: readOnly,
                  decoration: InputDecoration(
                    labelText: tr('Nr uprawnień UDT'),
                    helperText: tr('Wymagany, jeśli uprawnienie opiera się na UDT — na karcie zaznaczy „UDT”.'),
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('Rodzaje wózków'), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                if (typeChoices.isEmpty && _truckTypes != null)
                  Text(tr('Brak typów wózków — dodaj je w zakładce „Słowniki”.')),
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
                        label: tr('Data wydania'),
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
                        label: tr('Ważne do'),
                        value: _validUntil,
                        onPick: readOnly
                            ? null
                            : () async {
                                final d = await _pick(_validUntil ?? _issuedOn);
                                if (d != null) setState(() => _validUntil = d);
                              },
                        required: true,
                        validator: (_) => _validUntil != null && _issuedOn != null && _validUntil!.isBefore(_issuedOn!)
                            ? tr('Przed datą wydania')
                            : null,
                      ),
                    ),
                  ],
                ),
                if (p != null && !readOnly) ...[
                  const SizedBox(height: 12),
                  if (p.status == PermitStatus.expired)
                    Text(
                      tr('Wygasłe — status nadaje system. Przesuń datę „Ważne do”, aby uprawnienie znów było aktywne.'),
                    )
                  else
                    DropdownButtonFormField<PermitStatus>(
                      initialValue: _status,
                      decoration: InputDecoration(labelText: tr('Status')),
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
                      decoration: InputDecoration(
                        labelText: tr('Komentarz do zmiany statusu (opcjonalnie)'),
                        helperText: tr('Np. „zawieszone do ponownego szkolenia”. Trafia do dziennika.'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Text(tr('Dokument-podstawa'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _basisName,
                  readOnly: readOnly,
                  decoration: InputDecoration(labelText: tr('Nazwa (np. zaświadczenie UDT)')),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _basisNumber,
                        readOnly: readOnly,
                        decoration: InputDecoration(labelText: tr('Numer')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: tr('Data'),
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
                      tr('Skan dokumentu dołączysz po zapisaniu uprawnienia.'),
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
        if (p != null && !archived)
          TextButton.icon(
            onPressed: _busy ? null : _print,
            icon: const Icon(Icons.print_outlined),
            label: Text(tr('Drukuj')),
          ),
        if (p != null && !readOnly)
          TextButton.icon(
            onPressed: _busy ? null : _renew,
            icon: const Icon(Icons.autorenew),
            label: Text(tr('Odnów')),
          ),
        if (readOnly)
          FilledButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Zamknij')))
        else ...[
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
            child: Text(_isNew ? tr('Anuluj') : tr('Zamknij')),
          ),
          FilledButton(
            onPressed: _busy || _categories == null ? null : _save,
            child: Text(_isNew ? tr('Dodaj') : tr('Zapisz')),
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
              ? Text(tr('Brak skanu dokumentu.'))
              : Text(
                  tr('{filename} ({ceil} KB)', {'filename': doc.filename, 'ceil': (doc.size / 1024).ceil()}),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (doc != null) TextButton(onPressed: _busy ? null : _openDocument, child: Text(tr('Otwórz'))),
        if (!readOnly)
          TextButton(onPressed: _busy ? null : _attach, child: Text(doc == null ? tr('Dołącz skan') : tr('Zmień'))),
        if (!readOnly && doc != null)
          IconButton(
            tooltip: tr('Usuń skan'),
            onPressed: _busy ? null : _removeDocument,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
  }
}

/// Renewal: new dates; category, truck types, UDT and the basis document carry over
/// (change them afterwards on the new permit). Pops the request body, or null.
class _RenewDialog extends StatefulWidget {
  const _RenewDialog({required this.permit});

  final Permit permit;

  @override
  State<_RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends State<_RenewDialog> {
  final _form = GlobalKey<FormState>();
  late DateTime _issuedOn = DateUtils.dateOnly(DateTime.now());
  // As long as the old one was valid, counted from today.
  late DateTime _validUntil = DateTime(
    _issuedOn.year + (widget.permit.validUntil.year - widget.permit.issuedOn.year).clamp(1, 10),
    _issuedOn.month,
    _issuedOn.day,
  );

  Future<DateTime?> _pick(DateTime current) =>
      showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2100));

  @override
  Widget build(BuildContext context) {
    final p = widget.permit;
    return AlertDialog(
      title: Text(tr('Odnów {number}', {'number': p.number})),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Powstanie nowe uprawnienie z kolejnym numerem roku. Kategoria, wózki, UDT i dokument-podstawa zostaną przeniesione. Obecne ({number}) trafi do archiwum bez zmian.',
                  {'number': p.number},
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: tr('Data wydania'),
                      value: _issuedOn,
                      required: true,
                      onPick: () async {
                        final d = await _pick(_issuedOn);
                        if (d != null) setState(() => _issuedOn = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: tr('Ważne do'),
                      value: _validUntil,
                      required: true,
                      onPick: () async {
                        final d = await _pick(_validUntil);
                        if (d != null) setState(() => _validUntil = d);
                      },
                      validator: (_) => _validUntil.isBefore(_issuedOn) ? tr('Przed datą wydania') : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Anuluj'))),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {'issued_on': formatDay(_issuedOn), 'valid_until': formatDay(_validUntil)});
          },
          child: Text(tr('Odnów')),
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
            ? IconButton(tooltip: tr('Wyczyść'), onPressed: onClear, icon: const Icon(Icons.clear))
            : const Icon(Icons.calendar_today_outlined),
      ),
      validator: (v) {
        if (required && value == null) return tr('Wybierz datę');
        return validator?.call(v);
      },
    );
  }
}
