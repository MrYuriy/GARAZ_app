import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/export_button.dart';
import '../permits/permit_widgets.dart';
import 'reports_repository.dart';
import '../../core/i18n.dart';

enum _Report {
  expiring('Wygasające uprawnienia', '/reports/expiring-permits.xlsx'),
  byTruck('Zdarzenia wg wózków', '/reports/incidents-by-truck.xlsx'),
  byCategory('Zdarzenia wg kategorii', '/reports/incidents-by-category.xlsx');

  const _Report(this._label, this.xlsx);

  final String _label;

  String get label => tr(_label);
  final String xlsx;
}

/// A period of local days; null ends are open.
enum _Period {
  last30('Ostatnie 30 dni'),
  month('Ten miesiąc'),
  year('Ten rok'),
  all('Cały okres'),
  custom('Wybierz daty…');

  const _Period(this._label);

  final String _label;

  String get label => tr(_label);
}

/// Raporty: expiring permits and incident counts, each also as an Excel file.
/// The registers themselves are exported from their own tabs.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Report _report = _Report.expiring;
  int _days = expiringSoonDays;
  _Period _period = _Period.last30;
  DateTimeRange? _custom;

  ExpiringPermits? _expiring;
  List<IncidentCounts>? _counts;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.last30 => (today.subtract(const Duration(days: 29)), today),
      _Period.month => (DateTime(now.year, now.month), today),
      _Period.year => (DateTime(now.year), today),
      _Period.all => (null, null),
      _Period.custom => (_custom?.start, _custom?.end),
    };
  }

  Map<String, dynamic> _query() => switch (_report) {
    _Report.expiring => {'days': _days},
    _ => ReportsRepository.period(_range.$1, _range.$2),
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(reportsRepositoryProvider);
      final (from, to) = _range;
      switch (_report) {
        case _Report.expiring:
          final result = await repo.expiringPermits(days: _days);
          if (mounted) setState(() => _expiring = result);
        case _Report.byTruck:
          final result = await repo.incidentsByTruck(from, to);
          if (mounted) setState(() => _counts = result);
        case _Report.byCategory:
          final result = await repo.incidentsByCategory(from, to);
          if (mounted) setState(() => _counts = result);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(_Report report) {
    setState(() {
      _report = report;
      _counts = null;
    });
    _load();
  }

  Future<void> _pickPeriod(_Period period) async {
    if (period == _Period.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _custom,
      );
      if (picked == null) return;
      _custom = picked;
    }
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Raporty')),
        actions: [
          ExportButton(path: _report.xlsx, query: _query, tooltip: tr('Raport do Excel')),
          IconButton(tooltip: tr('Odśwież'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _Report.values)
                  ChoiceChip(label: Text(r.label), selected: _report == r, onSelected: (_) => _pick(r)),
              ],
            ),
          ),
          const Divider(height: 24),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: _filters()),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(child: _report == _Report.expiring ? _expiringList() : _countsList()),
        ],
      ),
    );
  }

  Widget _filters() {
    if (_report == _Report.expiring) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(tr('Kończą się w ciągu:')),
          for (final d in const [7, 14, 30, 60, 90])
            ChoiceChip(
              label: Text(tr('{d} dni', {'d': d})),
              selected: _days == d,
              onSelected: (_) {
                setState(() => _days = d);
                _load();
              },
            ),
          if (_expiring != null) Text(tr('Razem: {itemsCount}', {'itemsCount': _expiring!.items.length})),
        ],
      );
    }
    final (from, to) = _range;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in _Period.values)
          ChoiceChip(label: Text(p.label), selected: _period == p, onSelected: (_) => _pickPeriod(p)),
        Text(
          from == null
              ? tr('Od początku do dziś')
              : tr('{from} – {now}', {'from': formatDay(from), 'now': formatDay(to ?? DateTime.now())}),
        ),
      ],
    );
  }

  Widget _expiringList() {
    final items = _expiring?.items ?? const <Permit>[];
    if (items.isEmpty && !_loading) {
      return Center(child: Text(tr('Żadne aktywne uprawnienie nie kończy się w ciągu {days} dni.', {'days': _days})));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = items[i];
        return ListTile(
          title: Text(tr('{operatorName} · {number}', {'operatorName': p.operatorName, 'number': p.number})),
          subtitle: Text(
            [p.category.name, if (p.operatorEmployer != null) p.operatorEmployer!, validityText(p)].join(' · '),
          ),
          trailing: PermitStatusChip(status: p.status, daysLeft: p.daysLeft),
        );
      },
    );
  }

  Widget _countsList() {
    final rows = _counts ?? const <IncidentCounts>[];
    if (rows.isEmpty && !_loading) return Center(child: Text(tr('Brak zdarzeń w tym okresie.')));
    final scheme = Theme.of(context).colorScheme;
    final total = rows.fold(0, (sum, r) => sum + r.total);
    return ListView.separated(
      itemCount: rows.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == rows.length) {
          return ListTile(
            title: Text(tr('Razem'), style: TextStyle(fontWeight: FontWeight.w700)),
            trailing: Text('$total', style: Theme.of(context).textTheme.titleLarge),
          );
        }
        final r = rows[i];
        return ListTile(
          title: Text([r.name, ?r.truckType].join(' · '), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              for (final t in IncidentType.values) tr('{label}: {t}', {'label': t.label, 't': r.byType[t]}),
              if (r.outOfService > 0) tr('wyłączony z eksploatacji: {outOfService}', {'outOfService': r.outOfService}),
              tr('ostatnie {lastAt}', {'lastAt': formatDateTime(r.lastAt)}),
              if (r.truckStatus != null && r.truckStatus != TruckStatus.active)
                tr('teraz: {label}', {'label': r.truckStatus!.label}),
            ].join(' · '),
          ),
          trailing: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text('${r.total}'),
          ),
        );
      },
    );
  }
}
