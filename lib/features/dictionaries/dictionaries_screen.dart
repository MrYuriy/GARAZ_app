import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

/// The panel's lists. Everyone signed in reads them; administrators edit.
class DictionariesScreen extends ConsumerStatefulWidget {
  const DictionariesScreen({super.key});

  @override
  ConsumerState<DictionariesScreen> createState() => _DictionariesScreenState();
}

class _DictionariesScreenState extends ConsumerState<DictionariesScreen> {
  DictionaryKind _kind = DictionaryKind.truckTypes;
  bool _showInactive = false;
  List<DictionaryEntry> _items = const [];
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
      final items = await ref.read(dictionariesRepositoryProvider).list(_kind, includeInactive: _showInactive);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(DictionaryKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _items = const [];
    });
    _load();
  }

  Future<void> _edit([DictionaryEntry? entry]) async {
    final saved = await showDialog<DictionaryEntry>(
      context: context,
      builder: (_) => _EntryDialog(kind: _kind, entry: entry),
    );
    if (saved != null) await _load();
  }

  Future<void> _toggle(DictionaryEntry entry, bool active) async {
    try {
      await ref.read(dictionariesRepositoryProvider).update(_kind, entry.id, {'is_active': active});
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Słowniki'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in DictionaryKind.values)
                  ChoiceChip(label: Text(k.label), selected: k == _kind, onSelected: (_) => _select(k)),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Pokaż wyłączone'),
            value: _showInactive,
            onChanged: (v) {
              setState(() => _showInactive = v);
              _load();
            },
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? Center(
                    child: Text(
                      canEdit ? 'Lista jest pusta — dodaj pierwszą pozycję.' : 'Lista jest pusta.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      return ListTile(
                        onTap: canEdit ? () => _edit(e) : null,
                        title: Text(
                          e.name,
                          style: e.isActive
                              ? null
                              : TextStyle(color: scheme.outline, decoration: TextDecoration.lineThrough),
                        ),
                        subtitle: _subtitle(e),
                        trailing: canEdit
                            ? Switch(value: e.isActive, onChanged: (v) => _toggle(e, v))
                            : (e.isActive ? null : const Chip(label: Text('Wyłączone'))),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _subtitle(DictionaryEntry e) {
    if (e.incidentTypes == null) return null;
    final types = e.incidentTypes!.map((t) => t.label).join(', ');
    final stop = (e.defaultOutOfService ?? false) ? 'wyłącza wózek: TAK' : 'wyłącza wózek: NIE';
    return Text('$types · $stop');
  }
}

/// Add ([entry] == null) or edit one entry. Pops the saved entry.
class _EntryDialog extends ConsumerStatefulWidget {
  const _EntryDialog({required this.kind, this.entry});

  final DictionaryKind kind;
  final DictionaryEntry? entry;

  @override
  ConsumerState<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends ConsumerState<_EntryDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _order = TextEditingController(text: '${widget.entry?.sortOrder ?? 0}');
  late final Set<IncidentType> _types = {...?widget.entry?.incidentTypes};
  late bool _outOfService = widget.entry?.defaultOutOfService ?? false;
  bool _busy = false;
  String? _error;

  bool get _isIncident => widget.kind == DictionaryKind.incidentCategories;

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_isIncident && _types.isEmpty) {
      setState(() => _error = 'Wybierz co najmniej jeden typ zdarzenia.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final values = <String, dynamic>{
      'name': _name.text.trim(),
      'sort_order': int.tryParse(_order.text.trim()) ?? 0,
      if (_isIncident) 'incident_types': [for (final t in IncidentType.values) if (_types.contains(t)) t.api],
      if (_isIncident) 'default_out_of_service': _outOfService,
    };
    final repo = ref.read(dictionariesRepositoryProvider);
    try {
      final e = widget.entry;
      final saved = e == null ? await repo.create(widget.kind, values) : await repo.update(widget.kind, e.id, values);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.kind.label}: ${widget.entry == null ? 'nowa pozycja' : 'edycja'}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nazwa'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Podaj nazwę' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kolejność',
                    helperText: 'Mniejsza liczba = wyżej na liście.',
                  ),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Podaj liczbę' : null,
                ),
                if (_isIncident) ...[
                  const SizedBox(height: 16),
                  Text('Dostępna dla typów zdarzeń', style: Theme.of(context).textTheme.labelLarge),
                  for (final t in IncidentType.values)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.label),
                      subtitle: Text(t.hint),
                      value: _types.contains(t),
                      onChanged: (v) => setState(() => v! ? _types.add(t) : _types.remove(t)),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Domyślnie: wyłączony z eksploatacji'),
                    subtitle: const Text('Podpowiedź w formularzu; operator może ją zmienić.'),
                    value: _outOfService,
                    onChanged: (v) => setState(() => _outOfService = v),
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
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
      ],
    );
  }
}
