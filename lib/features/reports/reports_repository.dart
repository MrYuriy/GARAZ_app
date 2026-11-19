import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

/// "Wygasające uprawnienia": active permits ending within [days] (by [until]).
class ExpiringPermits {
  const ExpiringPermits(this.days, this.until, this.items);

  final int days;
  final DateTime until;
  final List<Permit> items;
}

/// Incidents of one truck or one category in a period.
class IncidentCounts {
  const IncidentCounts({
    required this.id,
    required this.name,
    required this.byType,
    required this.total,
    required this.outOfService,
    required this.lastAt,
    this.truckType,
    this.truckStatus,
  });

  final int id;

  /// The truck's number or the category's name.
  final String name;
  final Map<IncidentType, int> byType;
  final int total;

  /// How many of them stopped the truck.
  final int outOfService;
  final DateTime lastAt;

  /// Trucks only.
  final String? truckType;
  final TruckStatus? truckStatus;

  factory IncidentCounts.fromJson(Map<String, dynamic> j) {
    final truck = (j['truck'] as Map?)?.cast<String, dynamic>();
    final category = (j['category'] as Map?)?.cast<String, dynamic>();
    final byType = (j['by_type'] as Map).cast<String, dynamic>();
    return IncidentCounts(
      id: (truck ?? category)!['id'] as int,
      name: (truck?['number'] ?? category?['name']) as String,
      byType: {for (final t in IncidentType.values) t: (byType[t.api] as int?) ?? 0},
      total: j['total'] as int,
      outOfService: j['out_of_service'] as int,
      lastAt: DateTime.parse(j['last_at'] as String).toLocal(),
      truckType: truck?['truck_type'] as String?,
      truckStatus: truck == null ? null : TruckStatus.fromApi(truck['status'] as String),
    );
  }
}

/// A file the server made, under the name it gave.
typedef ExportedFile = ({Uint8List bytes, String filename});

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

class ReportsRepository {
  ReportsRepository(this._api);

  final ApiClient _api;

  Future<ExpiringPermits> expiringPermits({int? days}) async {
    final data = await _api.send((d) => d.get('/reports/expiring-permits', queryParameters: {'days': ?days}));
    final j = (data as Map).cast<String, dynamic>();
    return ExpiringPermits(j['days'] as int, DateTime.parse(j['until'] as String), [
      for (final p in j['items'] as List) Permit.fromJson((p as Map).cast<String, dynamic>()),
    ]);
  }

  Future<List<IncidentCounts>> incidentsByTruck(DateTime? from, DateTime? to) =>
      _counts('/reports/incidents-by-truck', from, to);

  Future<List<IncidentCounts>> incidentsByCategory(DateTime? from, DateTime? to) =>
      _counts('/reports/incidents-by-category', from, to);

  Future<List<IncidentCounts>> _counts(String path, DateTime? from, DateTime? to) async {
    final data = await _api.send((d) => d.get(path, queryParameters: period(from, to)));
    return [for (final r in (data as Map)['rows'] as List) IncidentCounts.fromJson((r as Map).cast<String, dynamic>())];
  }

  /// A period as the reports take it: local days, both included.
  static Map<String, dynamic> period(DateTime? from, DateTime? to) => {
    if (from != null) 'date_from': _day(from),
    if (to != null) 'date_to': _day(to),
  };

  /// An Excel file from `/reports/<name>.xlsx`; [query] carries the list's filters.
  Future<ExportedFile> xlsx(String path, [Map<String, dynamic>? query]) async {
    String? disposition;
    final data = await _api.send((d) async {
      final resp = await d.get(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes, listFormat: ListFormat.multi),
      );
      disposition = resp.headers.value('content-disposition');
      return resp;
    });
    return (bytes: Uint8List.fromList(data as List<int>), filename: _filename(disposition) ?? 'raport.xlsx');
  }

  /// `attachment; filename*=UTF-8''zdarzenia-2026-11-19.xlsx` -> the name.
  static String? _filename(String? disposition) {
    final match = RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(disposition ?? '');
    return match == null ? null : Uri.decodeComponent(match.group(1)!);
  }
}
