import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'incident_widgets.dart';
import '../../core/i18n.dart';

/// One report: what happened, its photos, flags and history. Administrators
/// move it along and put a stopped truck back to work.
class IncidentScreen extends ConsumerStatefulWidget {
  const IncidentScreen({super.key, required this.incidentId});

  final int incidentId;

  @override
  ConsumerState<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends ConsumerState<IncidentScreen> {
  Incident? _incident;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await ref.read(incidentsRepositoryProvider).get(widget.incidentId);
      if (mounted) setState(() => _incident = i);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _change() async {
    final result = await showDialog<(IncidentStatus, String?)>(
      context: context,
      builder: (_) => _StatusDialog(current: _incident!.status),
    );
    if (result == null) return;
    final (status, comment) = result;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(incidentsRepositoryProvider)
          .update(widget.incidentId, status: status == _incident!.status ? null : status, comment: comment);
      setState(() => _incident = saved);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreTruck() async {
    final i = _incident!;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Przywrócić wózek {name} do pracy?', {'name': i.truck.name})),
        content: TextField(
          controller: comment,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Komentarz (opcjonalnie)'),
            helperText: tr('Np. „naprawa zakończona”. Trafia do dziennika wózka.'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Przywróć'))),
        ],
      ),
    );
    final text = comment.text.trim();
    comment.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(trucksRepositoryProvider).update(i.truck.id, {
        'status': TruckStatus.active.api,
        'comment': text.isEmpty ? tr('Przywrócony po zgłoszeniu nr {id}', {'id': i.id}) : text,
      });
      _snack(tr('Wózek {name} wrócił do pracy.', {'name': i.truck.name}));
      await _load();
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showPhoto(int index) {
    final i = _incident!;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: IncidentPhoto(incidentId: i.id, photoId: i.photos[index].id, thumb: false, fit: BoxFit.contain),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final i = _incident;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(i == null ? tr('Zgłoszenie') : tr('Zgłoszenie nr {id}', {'id': i.id}))),
      floatingActionButton: i != null && isAdmin
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _change,
              icon: const Icon(Icons.edit_note),
              label: Text(tr('Zmień status / komentarz')),
            )
          : null,
      body: i == null
          ? Center(
              child: _error != null
                  ? Text(_error!, style: TextStyle(color: scheme.error))
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(incidentTypeIcon(i.type), size: 32),
                        title: Text(
                          tr('{label} · {name}', {'label': i.type.label, 'name': i.category.name}),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(formatDateTime(i.occurredAt)),
                        trailing: IncidentStatusChip(status: i.status),
                      ),
                      ListTile(
                        leading: const Icon(Icons.forklift),
                        title: Text(tr('Wózek {name}', {'name': i.truck.name})),
                        subtitle: Text(
                          [
                            tr('teraz: {label}', {'label': i.truckStatus.label}),
                            if (i.mth != null) 'MTH ${formatMth(i.mth!)}',
                            i.outOfService
                                ? tr('w zgłoszeniu: wyłączony z eksploatacji — TAK')
                                : tr('w zgłoszeniu: wyłączony — NIE'),
                          ].join(' · '),
                        ),
                        trailing: isAdmin && i.truckStatus == TruckStatus.outOfService
                            ? FilledButton.tonal(
                                onPressed: _busy ? null : _restoreTruck,
                                child: Text(tr('Przywróć do pracy')),
                              )
                            : null,
                      ),
                      ListTile(
                        leading: Icon(i.operator == null ? Icons.person_outline : Icons.badge_outlined),
                        title: Text(i.driver),
                        subtitle: i.operator == null ? Text(tr('osoba spoza rejestru operatorów')) : null,
                      ),
                      if (i.description != null)
                        ListTile(leading: const Icon(Icons.notes), title: Text(i.description!)),
                    ],
                  ),
                ),
                if (i.flags.isNotEmpty)
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final f in i.flags)
                            Row(
                              children: [
                                Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    incidentFlagLabel(f),
                                    style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  tr('Zdjęcia ({photosCount})', {'photosCount': i.photos.length}),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var k = 0; k < i.photos.length; k++)
                      InkWell(
                        onTap: () => _showPhoto(k),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: IncidentPhoto(incidentId: i.id, photoId: i.photos[k].id, size: 140),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(tr('Historia'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final e in i.events.reversed)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(
                      e.fromStatus == null
                          ? (e.userName == null ? tr('Zgłoszone przez operatora') : tr('Dodane w panelu'))
                          : e.fromStatus == e.toStatus
                          ? tr('Komentarz')
                          : tr('{label} → {label2}', {'label': e.fromStatus!.label, 'label2': e.toStatus.label}),
                    ),
                    subtitle: Text([formatDateTime(e.createdAt), ?e.userName, ?e.comment].join(' · ')),
                  ),
              ],
            ),
    );
  }
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.current});

  final IncidentStatus current;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late IncidentStatus _status = widget.current;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comment = _comment.text.trim();
    final changed = _status != widget.current || comment.isNotEmpty;
    return AlertDialog(
      title: Text(tr('Status zgłoszenia')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<IncidentStatus>(
              segments: [for (final s in IncidentStatus.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(labelText: tr('Komentarz (opcjonalnie)'), alignLabelWithHint: true),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Anuluj'))),
        FilledButton(
          onPressed: changed ? () => Navigator.pop(context, (_status, comment.isEmpty ? null : comment)) : null,
          child: Text(tr('Zapisz')),
        ),
      ],
    );
  }
}
