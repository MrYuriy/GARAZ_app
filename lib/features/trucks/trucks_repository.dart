import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class TrucksRepository {
  TrucksRepository(this._api);

  final ApiClient _api;

  Future<PageOf<Truck>> list({int page = 1, int limit = 200, String? query, TruckStatus? status}) async {
    final data = await _api.send(
      (d) => d.get(
        '/trucks',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'query': query,
          'status': ?status?.api,
        },
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), Truck.fromJson);
  }

  Future<Truck> create(Map<String, dynamic> values) async {
    final data = await _api.send((d) => d.post('/trucks', data: values));
    return Truck.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends only [changes].
  Future<Truck> update(int id, Map<String, dynamic> changes) async {
    final data = await _api.send((d) => d.patch('/trucks/$id', data: changes));
    return Truck.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Truck> get(int id) async {
    final data = await _api.send((d) => d.get('/trucks/$id'));
    return Truck.fromJson((data as Map).cast<String, dynamic>());
  }

  /// For a truck added by mistake; one that left the fleet is set inactive instead.
  Future<void> delete(int id) => _api.send((d) => d.delete('/trucks/$id'));

  /// New QR token: the printed sticker stops working at once.
  Future<Truck> reissueQr(int id) async {
    final data = await _api.send((d) => d.post('/trucks/$id/qr'));
    return Truck.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Uint8List> qrPng(int id) => _bytes('/trucks/$id/qr.png');

  Future<Uint8List> labelsPdf(List<int> ids) => _bytes('/trucks/labels.pdf', {'ids': ids});

  Future<Uint8List> _bytes(String path, [Map<String, dynamic>? query]) async {
    final data = await _api.send(
      (d) => d.get(
        path,
        queryParameters: query,
        // ids=1&ids=2, the way FastAPI reads a list.
        options: Options(responseType: ResponseType.bytes, listFormat: ListFormat.multi),
      ),
    );
    return Uint8List.fromList(data as List<int>);
  }
}
