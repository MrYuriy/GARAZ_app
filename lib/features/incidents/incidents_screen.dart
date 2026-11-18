import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'incident_widgets.dart';

/// Reports from the operators' phones, newest first.
class IncidentsScreen extends ConsumerStatefulWidget {
  const IncidentsScreen({super.key});

  @override
  ConsumerState<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends ConsumerState<IncidentsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  /// Null: every status. Open ones (Nowe + W trakcie) are the default view.
  IncidentStatus? _status;
  bool _openOnly = true;
  IncidentType? _type;
  bool _flaggedOnly = false;
  PageOf<Incident>? _page;
  bool _loading = false;
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
      final repo = ref.read(incidentsRepositoryProvider);
      final page = await repo.list(
        query: _search.text.trim(),
        status: _status,
        type: _type,
        flagged: _flaggedOnly ? true : null,
        openOnly: _openOnly && _status == null,
      );
      if (mounted) setState(() => _page = page);
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

  void _setStatus({IncidentStatus? status, bool open = false}) {
    setState(() {
      _status = status;
      _openOnly = open;
    });
    _load();
  }

  Future<void> _open(Incident i) async {
    await context.push('/incidents/${i.id}');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _page?.items ?? const <Incident>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zdarzenia'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Szukaj: nr wózka, operator',
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Otwarte'),
                  selected: _openOnly && _status == null,
                  onSelected: (_) => _setStatus(open: true),
                ),
                for (final s in IncidentStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => _setStatus(status: s),
                  ),
                ChoiceChip(
                  label: const Text('Wszystkie'),
                  selected: !_openOnly && _status == null,
                  onSelected: (_) => _setStatus(),
                ),
                DropdownButton<IncidentType?>(
                  value: _type,
                  hint: const Text('Każdy rodzaj'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Każdy rodzaj')),
                    for (final t in IncidentType.values) DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (t) {
                    setState(() => _type = t);
                    _load();
                  },
                ),
                FilterChip(
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  label: const Text('Z uwagami'),
                  selected: _flaggedOnly,
                  onSelected: (v) {
                    setState(() => _flaggedOnly = v);
                    _load();
                  },
                ),
                if (_page != null) Text('Razem: ${_page!.total}'),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? const Center(
                    child: Text(
                      'Brak zgłoszeń. Operatorzy zgłaszają zdarzenia, skanując kod QR na wózku.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _IncidentTile(incident: items[i], onTap: () => _open(items[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({required this.incident, required this.onTap});

  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: i.photos.isEmpty
            ? SizedBox(width: 56, height: 56, child: Icon(incidentTypeIcon(i.type)))
            : IncidentPhoto(incidentId: i.id, photoId: i.photos.first.id, size: 56),
      ),
      title: Row(
        children: [
          Text('${i.truck.name} · ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Icon(incidentTypeIcon(i.type), size: 18),
          const SizedBox(width: 4),
          Flexible(child: Text('${i.type.label} · ${i.category.name}', overflow: TextOverflow.ellipsis)),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: [
                i.operator.name,
                formatDateTime(i.occurredAt),
                if (i.mth != null) 'MTH ${formatMth(i.mth!)}',
                if (i.outOfService) 'wyłączony z eksploatacji',
              ].join(' · '),
            ),
            for (final f in i.flags) ...[
              const TextSpan(text: '  '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.warning_amber, size: 16, color: scheme.error),
              ),
              TextSpan(
                text: ' ${incidentFlagLabel(f)}',
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
      trailing: IncidentStatusChip(status: i.status),
    );
  }
}
