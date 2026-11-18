import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'truck_form_dialog.dart';

/// Deletes an entry; when trucks still use it, lists them so each can be
/// changed or deleted first, then offers the delete again.
/// Returns true when the entry was deleted.
Future<bool> deleteWithTruckCheck(
  BuildContext context, {
  required String what,
  required Future<void> Function() delete,
  required bool Function(Truck) uses,
}) async {
  try {
    await delete();
    return true;
  } on ApiException catch (e) {
    final trucks = e.trucksInUse;
    if (!context.mounted) return false;
    if (trucks == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _InUseDialog(what: what, trucks: trucks, delete: delete, uses: uses),
    );
    return deleted ?? false;
  }
}

class _InUseDialog extends ConsumerStatefulWidget {
  const _InUseDialog({required this.what, required this.trucks, required this.delete, required this.uses});

  final String what;
  final List<EntryRef> trucks;
  final Future<void> Function() delete;

  /// Whether a truck, as saved, still points at the entry.
  final bool Function(Truck) uses;

  @override
  ConsumerState<_InUseDialog> createState() => _InUseDialogState();
}

class _InUseDialogState extends ConsumerState<_InUseDialog> {
  late final List<EntryRef> _trucks = [...widget.trucks];
  bool _busy = false;
  String? _error;

  Future<void> _change(EntryRef t) async {
    try {
      final truck = await ref.read(trucksRepositoryProvider).get(t.id);
      if (!mounted) return;
      final saved = await showDialog<Truck>(
        context: context,
        builder: (_) => TruckFormDialog(truck: truck),
      );
      if (saved != null && !widget.uses(saved)) setState(() => _trucks.removeWhere((x) => x.id == t.id));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _deleteTruck(EntryRef t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć wózek ${t.name}?'),
        content: const Text(
          'Wózek zniknie z rejestru. Jeśli tylko wycofano go z floty, lepiej ustaw status „Nieaktywny” '
          '(zmień mu model zamiast usuwać).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń wózek'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(trucksRepositoryProvider).delete(t.id);
      setState(() => _trucks.removeWhere((x) => x.id == t.id));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Delete the entry again; a refusal (another truck took it meanwhile) refreshes the list.
  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.delete();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      final trucks = e.trucksInUse;
      setState(() {
        if (trucks != null) {
          _trucks
            ..clear()
            ..addAll(trucks);
        }
        _error = trucks == null ? e.message : 'Nadal używane przez wózki poniżej.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final free = _trucks.isEmpty;
    return AlertDialog(
      title: Text('Nie można usunąć: ${widget.what}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              free
                  ? 'Żaden wózek już tego nie używa — można usunąć.'
                  : 'Używają tego wózki (${_trucks.length}). Najpierw zmień im producenta/model albo usuń wózki.',
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in _trucks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.forklift),
                      title: Text(t.name),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: _busy ? null : () => _change(t),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Zmień'),
                          ),
                          IconButton(
                            tooltip: 'Usuń wózek',
                            onPressed: _busy ? null : () => _deleteTruck(t),
                            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Zamknij')),
        FilledButton(onPressed: _busy || !free ? null : _retry, child: Text('Usuń: ${widget.what}')),
      ],
    );
  }
}
