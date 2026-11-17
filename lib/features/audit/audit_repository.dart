import '../../core/api_client.dart';
import '../../core/models.dart';

class AuditRepository {
  AuditRepository(this._api);

  final ApiClient _api;

  Future<PageOf<AuditEntry>> list({int page = 1, int limit = 50, String? action}) async {
    final data = await _api.send(
      (d) => d.get(
        '/audit-logs',
        queryParameters: {'page': page, 'limit': limit, 'action': ?action},
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), AuditEntry.fromJson);
  }
}
