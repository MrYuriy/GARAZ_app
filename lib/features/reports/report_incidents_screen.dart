import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../incidents/incident_widgets.dart';

/// The reports behind one row of "Zdarzenia wg wózków / wg kategorii": one
/// truck's or one category's incidents in the report's period, every status,
/// newest first. Each opens the report itself.
///
/// Everything comes from the address (`/reports/incidents?truck=…&from=…`),
/// so a reload of the web page shows the same list.
class ReportIncidentsScreen extends ConsumerStatefulWidget {
  const ReportIncidentsScreen({super.key, this.truckId, this.categoryId, required this.name, this.from, this.to});

  final int? truckId;
  final int? categoryId;

  /// The truck's number or the category's name, as the report showed it.
  final String name;

  /// Local days, `YYYY-MM-DD`; null ends are open.
  final String? from;
  final String? to;

  /// The address of this list for a report row.
  static String location({int? truckId, int? categoryId, required String name, String? from, String? to}) => Uri(
    path: '/reports/incidents',
    queryParameters: {
      'truck': ?truckId?.toString(),
      'category': ?categoryId?.toString(),
      'name': name,
      'from': ?from,
      'to': ?to,
    },
  ).toString();

  @override
  ConsumerState<ReportIncidentsScreen> createState() => _ReportIncidentsScreenState();
}

class _ReportIncidentsScreenState extends ConsumerState<ReportIncidentsScreen> {
  PageOf<Incident>? _page;
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
      final page = await ref
          .read(incidentsRepositoryProvider)
          .list(
            limit: 200,
            truckId: widget.truckId,
            categoryId: widget.categoryId,
            dateFrom: widget.from,
            dateTo: widget.to,
          );
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(int id) async {
    await context.push('/reports/incidents/$id');
    if (mounted) await _load();
  }

  String get _period {
    final from = widget.from, to = widget.to;
    if (from == null && to == null) return tr('Od początku do dziś');
    return tr('{from} – {now}', {'from': from ?? '…', 'now': to ?? formatDay(DateTime.now())});
  }

  @override
  Widget build(BuildContext context) {
    final items = _page?.items ?? const <Incident>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.truckId != null ? tr('Wózek {number}', {'number': widget.name}) : widget.name),
        actions: [
          IconButton(tooltip: tr('Odśwież'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text(_period, style: theme.textTheme.bodyMedium)),
                if (_page != null)
                  Text(tr('Razem: {total}', {'total': _page!.total}), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (_page != null && items.isNotEmpty) _Summary(items: items),
          const Divider(height: 1),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? Center(child: Text(tr('Brak zdarzeń w tym okresie.')))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => IncidentTile(incident: items[i], onTap: () => _open(items[i].id)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// How many of the listed reports are still open, and how many of each kind.
class _Summary extends StatelessWidget {
  const _Summary({required this.items});

  final List<Incident> items;

  @override
  Widget build(BuildContext context) {
    int count(bool Function(Incident) test) => items.where(test).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final s in IncidentStatus.values)
            if (count((i) => i.status == s) > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IncidentStatusChip(status: s),
                  Text(' ${count((i) => i.status == s)}'),
                ],
              ),
          for (final t in IncidentType.values)
            if (count((i) => i.type == t) > 0)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(incidentTypeIcon(t), size: 16),
                label: Text('${t.label}: ${count((i) => i.type == t)}'),
              ),
        ],
      ),
    );
  }
}
