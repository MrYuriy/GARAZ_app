import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

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
