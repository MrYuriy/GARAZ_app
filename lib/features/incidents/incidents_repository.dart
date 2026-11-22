import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../report/report_repository.dart';

class IncidentsRepository {
  IncidentsRepository(this._api);

  final ApiClient _api;

  /// Photos are immutable once sent, so each one is fetched once per session.
  final Map<String, Future<Uint8List>> _photos = {};

  Future<PageOf<Incident>> list({
    int page = 1,
    int limit = 100,
    String? query,
    IncidentStatus? status,
    IncidentType? type,
    bool? flagged,
    bool openOnly = false,
    int? truckId,
    int? categoryId,

    /// Local days, both included (`YYYY-MM-DD`).
    String? dateFrom,
    String? dateTo,
  }) async {
    final data = await _api.send(
      (d) => d.get(
        '/incidents',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'query': query,
          'status': ?status?.api,
          'incident_type': ?type?.api,
          'flagged': ?flagged,
          if (openOnly) 'open': true,
          'truck_id': ?truckId,
          'category_id': ?categoryId,
          'date_from': ?dateFrom,
          'date_to': ?dateTo,
        },
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), Incident.fromJson);
  }

  Future<Incident> get(int id) async {
    final data = await _api.send((d) => d.get('/incidents/$id'));
    return Incident.fromJson((data as Map).cast<String, dynamic>());
  }

  /// A status change and/or a comment, each a line in the history.
  Future<Incident> update(int id, {IncidentStatus? status, String? comment}) async {
    final data = await _api.send((d) => d.patch('/incidents/$id', data: {'status': ?status?.api, 'comment': ?comment}));
    return Incident.fromJson((data as Map).cast<String, dynamic>());
  }

  // ----- entering a report for someone else -----

  /// A truck picked from the list, with its categories and last hour meter.
  Future<ReportTruck> formTruck(int truckId) async {
    final data = await _api.send((d) => d.get('/incidents/form/trucks/$truckId'));
    return ReportTruck.fromJson((data as Map).cast<String, dynamic>());
  }

  /// The same for a scanned sticker; 404 for an unknown code.
  Future<ReportTruck> formTruckByQr(String token) async {
    final data = await _api.send((d) => d.get('/incidents/form/trucks/by-qr/$token'));
    return ReportTruck.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Who a scanned operator card belongs to; 404 for an unknown card.
  Future<EntryRef> operatorByQr(String token) async {
    final data = await _api.send((d) => d.get('/incidents/form/operators/by-qr/$token'));
    final m = (data as Map).cast<String, dynamic>();
    return EntryRef(m['id'] as int, m['full_name'] as String);
  }

  /// Files the report; re-sending the same `client_uuid` returns the first one.
  Future<Incident> create(Map<String, dynamic> report, List<ReportPhoto> photos) async {
    final data = await _api.send((d) => d.post('/incidents', data: reportForm(report, photos), options: uploadOptions));
    return Incident.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Uint8List> photo(int incidentId, int photoId, {bool thumb = false}) {
    final key = '$incidentId/$photoId/$thumb';
    return _photos[key] ??= _fetch(incidentId, photoId, thumb).catchError((Object e) {
      _photos.remove(key); // a failed load may be retried
      throw e;
    });
  }

  Future<Uint8List> _fetch(int incidentId, int photoId, bool thumb) async {
    final data = await _api.send(
      (d) => d.get(
        '/incidents/$incidentId/photos/$photoId',
        queryParameters: {'thumb': thumb},
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(data as List<int>);
  }
}
