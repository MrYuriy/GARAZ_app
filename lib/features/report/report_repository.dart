import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import 'outbox.dart';

/// A category as the report form offers it.
class ReportCategory {
  const ReportCategory({required this.id, required this.name, required this.types, required this.defaultOutOfService});

  final int id;
  final String name;
  final Set<IncidentType> types;
  final bool defaultOutOfService;

  factory ReportCategory.fromJson(Map<String, dynamic> j) => ReportCategory(
    id: j['id'] as int,
    name: j['name'] as String,
    types: {for (final t in j['incident_types'] as List) IncidentType.fromApi(t as String)},
    defaultOutOfService: j['default_out_of_service'] as bool? ?? false,
  );
}

/// The truck behind a scanned sticker (or picked in the panel, then with [id]).
class ReportTruck {
  const ReportTruck({
    this.id,
    required this.number,
    required this.truckType,
    required this.make,
    required this.status,
    required this.lastMth,
    required this.categories,
    this.offline = false,
  });

  final int? id;
  final String number;
  final String truckType;
  final String? make;
  final TruckStatus status;
  final double? lastMth;
  final List<ReportCategory> categories;

  /// Read from this phone's copy: there is no signal now.
  final bool offline;

  factory ReportTruck.fromJson(Map<String, dynamic> j, {bool offline = false}) => ReportTruck(
    offline: offline,
    id: j['id'] as int?,
    number: j['number'] as String,
    truckType: j['truck_type'] as String,
    make: j['make'] as String?,
    status: TruckStatus.fromApi(j['status'] as String),
    lastMth: (j['last_mth'] as num?)?.toDouble(),
    categories: [for (final c in j['categories'] as List) ReportCategory.fromJson((c as Map).cast<String, dynamic>())],
  );
}

class ReportPhoto {
  const ReportPhoto(this.bytes, this.name);

  final Uint8List bytes;
  final String name;
}

/// The report and its photos as one multipart body: `data` is JSON, each
/// photo goes under the same plain "photos" key, the way FastAPI reads a list.
FormData reportForm(Map<String, dynamic> report, List<ReportPhoto> photos) => FormData()
  ..fields.add(MapEntry('data', jsonEncode(report)))
  ..files.addAll([for (final p in photos) MapEntry('photos', MultipartFile.fromBytes(p.bytes, filename: p.name))]);

/// Photos take a while over a weak connection.
final uploadOptions = Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 3));

/// The sign-in-free calls an operator's phone makes.
class ReportRepository {
  ReportRepository(this._api);

  final ApiClient _api;

  Future<ReportTruck> truck(String token) async {
    try {
      final data = (await _api.send((d) => d.get('/public/trucks/$token')) as Map).cast<String, dynamic>();
      await TruckCache.save(token, data);
      return ReportTruck.fromJson(data);
    } on ApiException catch (e) {
      final cached = isRetryable(e) ? await TruckCache.read(token) : null;
      if (cached == null) rethrow;
      return ReportTruck.fromJson(cached, offline: true);
    }
  }

  /// "Jan K." for the scanned card, or an [ApiException] (404) for an unknown one.
  Future<String> checkOperator(String truckToken, String operatorToken) async {
    final data = await _api.send(
      (d) => d.post('/public/operators/check', data: {'truck_token': truckToken, 'operator_token': operatorToken}),
    );
    return (data as Map)['display_name'] as String;
  }

  /// Sends the report; returns its id and whether the truck is now stopped.
  /// Re-sending with the same `client_uuid` is safe: the server files it once.
  Future<({int id, bool truckOutOfService})> submit(Map<String, dynamic> report, List<ReportPhoto> photos) async {
    final data = await _api.send(
      (d) => d.post('/public/incidents', data: reportForm(report, photos), options: uploadOptions),
    );
    final m = (data as Map).cast<String, dynamic>();
    return (id: m['id'] as int, truckOutOfService: m['truck_out_of_service'] as bool);
  }
}
