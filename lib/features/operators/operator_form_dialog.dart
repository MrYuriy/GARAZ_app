import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/i18n.dart';

/// Add an operator ([operator] == null) or edit one. Pops the saved [Operator].
class OperatorFormDialog extends ConsumerStatefulWidget {
  const OperatorFormDialog({super.key, this.operator});

  final Operator? operator;

  @override
  ConsumerState<OperatorFormDialog> createState() => _OperatorFormDialogState();
}

class _OperatorFormDialogState extends ConsumerState<OperatorFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.operator?.fullName);
  late final _card = TextEditingController(text: widget.operator?.hysterCardNumber);
  late int? _employerId = widget.operator?.employer?.id;
  late int? _siteId = widget.operator?.site.id;
  late bool _active = widget.operator?.isActive ?? true;

  List<DictionaryEntry>? _employers;
  List<DictionaryEntry>? _sites;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.operator == null;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _name.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    final repo = ref.read(dictionariesRepositoryProvider);
    try {
      final employers = await repo.list(DictionaryKind.employers);
      final sites = await repo.list(DictionaryKind.sites);
      if (!mounted) return;
      setState(() {
        _employers = employers;
        _sites = sites;
        if (_isNew && sites.length == 1) _siteId = sites.first.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String? _nullIfBlank(String v) => v.trim().isEmpty ? null : v.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(operatorsRepositoryProvider);
    try {
      final Operator saved;
      if (_isNew) {
        saved = await repo.create({
          'full_name': _name.text.trim(),
          'employer_id': _employerId,
          'hyster_card_number': _nullIfBlank(_card.text),
          'site_id': ?_siteId,
        });
      } else {
        final o = widget.operator!;
        final changes = <String, dynamic>{
          if (_name.text.trim() != o.fullName) 'full_name': _name.text.trim(),
          if (_employerId != o.employer?.id) 'employer_id': _employerId,
          if (_nullIfBlank(_card.text) != o.hysterCardNumber) 'hyster_card_number': _nullIfBlank(_card.text),
          if (_siteId != o.site.id) 'site_id': _siteId,
          if (_active != o.isActive) 'is_active': _active,
        };
        if (changes.isEmpty) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        saved = await repo.update(o.id, changes);
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
    final o = widget.operator;
    final employers = [
      DropdownMenuItem<int?>(value: null, child: Text(tr('— brak —'))),
      for (final e in _employers ?? const <DictionaryEntry>[]) DropdownMenuItem<int?>(value: e.id, child: Text(e.name)),
      if (o?.employer != null && !(_employers ?? const []).any((e) => e.id == o!.employer!.id))
        DropdownMenuItem<int?>(
          value: o!.employer!.id,
          child: Text(tr('{name} (wyłączony)', {'name': o.employer!.name})),
        ),
    ];
    final sites = [
      for (final s in _sites ?? const <DictionaryEntry>[]) DropdownMenuItem<int>(value: s.id, child: Text(s.name)),
      if (o != null && !(_sites ?? const []).any((s) => s.id == o.site.id))
        DropdownMenuItem<int>(value: o.site.id, child: Text(tr('{name} (wyłączona)', {'name': o.site.name}))),
    ];

    return AlertDialog(
      title: Text(_isNew ? tr('Nowy operator') : o!.fullName),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_employers == null) const LinearProgressIndicator(),
                TextFormField(
                  controller: _name,
                  autofocus: _isNew,
                  decoration: InputDecoration(labelText: tr('Imię i nazwisko')),
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Podaj imię i nazwisko') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _employerId,
                  decoration: InputDecoration(
                    labelText: tr('Pracodawca'),
                    helperText: (_employers?.isEmpty ?? false)
                        ? tr('Listę pracodawców uzupełnisz w „Słownikach”.')
                        : null,
                  ),
                  items: employers,
                  onChanged: (v) => setState(() => _employerId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _card,
                  decoration: InputDecoration(labelText: tr('Nr karty Hyster Tracker (opcjonalnie)')),
                ),
                if (sites.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _siteId,
                    decoration: InputDecoration(labelText: tr('Lokalizacja')),
                    items: sites,
                    onChanged: (v) => setState(() => _siteId = v),
                    validator: (v) => v == null ? tr('Wybierz lokalizację') : null,
                  ),
                ],
                if (!_isNew) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Aktywny')),
                    subtitle: Text(tr('Wyłącz, gdy osoba już nie pracuje. Historia zostaje.')),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
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
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Anuluj'))),
        FilledButton(
          onPressed: _busy || _employers == null ? null : _save,
          child: Text(_isNew ? tr('Dodaj') : tr('Zapisz')),
        ),
      ],
    );
  }
}
