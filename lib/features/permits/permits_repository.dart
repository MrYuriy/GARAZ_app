import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

class PermitsRepository {
  PermitsRepository(this._api);

  final ApiClient _api;

  Future<PageOf<Permit>> list({
    int page = 1,
    int limit = 200,
    String? query,
    PermitStatus? status,
    int? operatorId,
    int? expiringWithinDays,
  }) async {
    final data = await _api.send(
      (d) => d.get(
        '/permits',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'query': query,
          'status': ?status?.api,
          'operator_id': ?operatorId,
          'expiring_within_days': ?expiringWithinDays,
        },
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), Permit.fromJson);
  }

  Future<Permit> get(int id) async {
    final data = await _api.send((d) => d.get('/permits/$id'));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Permit> create(Map<String, dynamic> values) async {
    final data = await _api.send((d) => d.post('/permits', data: values));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends only [changes].
  Future<Permit> update(int id, Map<String, dynamic> changes) async {
    final data = await _api.send((d) => d.patch('/permits/$id', data: changes));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  /// A new permit with the next number; the old one is archived.
  Future<Permit> renew(int id, Map<String, dynamic> values) async {
    final data = await _api.send((d) => d.post('/permits/$id/renew', data: values));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  /// The permits on form PL-FORM-QHSE-009, eight to an A4 sheet.
  Future<Uint8List> cardsPdf(List<int> ids) async {
    final data = await _api.send(
      (d) => d.get(
        '/permits/cards.pdf',
        queryParameters: {'ids': ids},
        options: Options(responseType: ResponseType.bytes, listFormat: ListFormat.multi),
      ),
    );
    return Uint8List.fromList(data as List<int>);
  }

  Future<Permit> attachDocument(int id, Uint8List bytes, String filename) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    final data = await _api.send((d) => d.put('/permits/$id/document', data: form));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Permit> removeDocument(int id) async {
    final data = await _api.send((d) => d.delete('/permits/$id/document'));
    return Permit.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<Uint8List> document(int id) async {
    final data = await _api.send(
      (d) => d.get('/permits/$id/document', options: Options(responseType: ResponseType.bytes)),
    );
    return Uint8List.fromList(data as List<int>);
  }
}
