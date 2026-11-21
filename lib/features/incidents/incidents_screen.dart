import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import '../../core/widgets/filter_bar.dart';
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

  void _setType(IncidentType? t) {
    setState(() => _type = t);
    _load();
  }

  void _setStatus({IncidentStatus? status, bool open = false}) {
    setState(() {
      _status = status;
      _openOnly = open;
    });
    _load();
  }

  /// The list's filters, for the Excel file.
  Map<String, dynamic> _exportQuery() => {
    if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(),
    'status': ?_status?.api,
    'incident_type': ?_type?.api,
    if (_flaggedOnly) 'flagged': true,
    if (_openOnly && _status == null) 'open': true,
  };

  Future<void> _open(int id) async {
    await context.push('/incidents/$id');
    await _load();
  }

  Future<void> _add() async {
    final id = await context.push<int>('/incidents/new');
    if (id == null || !mounted) return;
    await _load();
    if (mounted) await _open(id);
  }

  @override
  Widget build(BuildContext context) {
    final items = _page?.items ?? const <Incident>[];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj zgłoszenie'),
      ),
      appBar: AppBar(
        title: const Text('Zdarzenia'),
        actions: [
          ExportButton(path: '/reports/incidents.xlsx', query: _exportQuery),
          IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          FilterBar(
            searchController: _search,
            onSearch: _onSearch,
            searchHint: 'Szukaj: nr wózka, operator',
            groups: () => [
              FilterGroup(
                title: 'Status',
                activeLabel: _status?.label ?? (_openOnly ? null : 'Wszystkie'),
                onClear: () => _setStatus(open: true),
                options: [
                  FilterOption(
                    'Otwarte',
                    selected: _openOnly && _status == null,
                    onSelected: () => _setStatus(open: true),
                  ),
                  for (final s in IncidentStatus.values)
                    FilterOption(
                      s.label,
                      selected: _status == s,
                      onSelected: () => _setStatus(status: s),
                    ),
                  FilterOption('Wszystkie', selected: !_openOnly && _status == null, onSelected: _setStatus),
                ],
              ),
              FilterGroup(
                title: 'Rodzaj',
                activeLabel: _type?.label,
                onClear: () => _setType(null),
                options: [
                  for (final t in [null, ...IncidentType.values])
                    FilterOption(t?.label ?? 'Każdy rodzaj', selected: _type == t, onSelected: () => _setType(t)),
                ],
              ),
              FilterGroup.toggle(
                title: 'Z uwagami',
                value: _flaggedOnly,
                activeLabel: _flaggedOnly ? 'Z uwagami' : null,
                onChanged: (v) {
                  setState(() => _flaggedOnly = v);
                  _load();
                },
              ),
            ],
            total: _page?.total,
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
                      'Brak zgłoszeń. Operatorzy zgłaszają zdarzenia, skanując kod QR na wózku; '
                      'zgłoszenie za kogoś dodasz przyciskiem „Dodaj zgłoszenie”.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88), // clear of the add button
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _IncidentTile(incident: items[i], onTap: () => _open(items[i].id)),
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
                i.driver,
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
