import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class OperatorsRepository {
  OperatorsRepository(this._api);

  final ApiClient _api;

  Future<PageOf<Operator>> list({int page = 1, int limit = 200, String? query, bool? isActive}) async {
    final data = await _api.send(
      (d) => d.get(
        '/operators',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'query': query,
          'is_active': ?isActive,
        },
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), Operator.fromJson);
  }

  Future<Operator> get(int id) async {
    final data = await _api.send((d) => d.get('/operators/$id'));
    return Operator.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Operator> create(Map<String, dynamic> values) async {
    final data = await _api.send((d) => d.post('/operators', data: values));
    return Operator.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends only [changes].
  Future<Operator> update(int id, Map<String, dynamic> changes) async {
    final data = await _api.send((d) => d.patch('/operators/$id', data: changes));
    return Operator.fromJson((data as Map).cast<String, dynamic>());
  }

  /// New QR token: the printed card stops working at once.
  Future<Operator> reissueQr(int id) async {
    final data = await _api.send((d) => d.post('/operators/$id/qr'));
    return Operator.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Uint8List> qrPng(int id) => _bytes('/operators/$id/qr.png');

  Future<Uint8List> cardsPdf(List<int> ids) => _bytes('/operators/cards.pdf', {'ids': ids});

  Future<Uint8List> _bytes(String path, [Map<String, dynamic>? query]) async {
    final data = await _api.send(
      (d) => d.get(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes, listFormat: ListFormat.multi),
      ),
    );
    return Uint8List.fromList(data as List<int>);
  }
}
