import '../../core/api_client.dart';
import '../../core/models.dart';

/// Truck manufacturers and their models. A delete of one in use fails with an
/// [ApiException] whose `trucksInUse` lists the trucks.
class TruckCatalogRepository {
  TruckCatalogRepository(this._api);

  final ApiClient _api;

  Future<List<TruckManufacturer>> list() async {
    final data = await _api.send((d) => d.get('/truck-manufacturers'));
    return [for (final m in data as List) TruckManufacturer.fromJson((m as Map).cast<String, dynamic>())];
  }

  Future<void> createManufacturer(String name) =>
      _api.send((d) => d.post('/truck-manufacturers', data: {'name': name}));

  Future<void> renameManufacturer(int id, String name) =>
      _api.send((d) => d.patch('/truck-manufacturers/$id', data: {'name': name}));

  Future<void> deleteManufacturer(int id) => _api.send((d) => d.delete('/truck-manufacturers/$id'));

  Future<void> createModel(int manufacturerId, String name) =>
      _api.send((d) => d.post('/truck-models', data: {'manufacturer_id': manufacturerId, 'name': name}));

  Future<void> renameModel(int id, String name) => _api.send((d) => d.patch('/truck-models/$id', data: {'name': name}));

  Future<void> deleteModel(int id) => _api.send((d) => d.delete('/truck-models/$id'));
}
