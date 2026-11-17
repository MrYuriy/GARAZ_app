import '../../core/api_client.dart';
import '../../core/models.dart';

class DictionariesRepository {
  DictionariesRepository(this._api);

  final ApiClient _api;

  Future<List<DictionaryEntry>> list(DictionaryKind kind, {bool includeInactive = false}) async {
    final data = await _api.send(
      (d) => d.get('/dictionaries/${kind.api}', queryParameters: {'include_inactive': includeInactive}),
    );
    return (data as List).map((e) => DictionaryEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<DictionaryEntry> create(DictionaryKind kind, Map<String, dynamic> values) async {
    final data = await _api.send((d) => d.post('/dictionaries/${kind.api}', data: values));
    return DictionaryEntry.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends only [changes].
  Future<DictionaryEntry> update(DictionaryKind kind, int id, Map<String, dynamic> changes) async {
    final data = await _api.send((d) => d.patch('/dictionaries/${kind.api}/$id', data: changes));
    return DictionaryEntry.fromJson((data as Map).cast<String, dynamic>());
  }
}
