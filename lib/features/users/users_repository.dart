import '../../core/api_client.dart';
import '../../core/models.dart';

class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<PageOf<User>> list({int page = 1, int limit = 50, String? query, Role? role, UserStatus? status}) async {
    final data = await _api.send(
      (d) => d.get(
        '/users',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'query': query,
          if (role != null) 'role': role.api,
          if (status != null) 'status': status.api,
        },
      ),
    );
    return PageOf.fromJson((data as Map).cast<String, dynamic>(), User.fromJson);
  }

  Future<User> create({
    required String login,
    required String password,
    required Role role,
    String? fullName,
    String? email,
    bool mustChangePassword = true,
  }) async {
    final data = await _api.send(
      (d) => d.post(
        '/users',
        data: {
          'login': login,
          'password': password,
          'role': role.api,
          'full_name': fullName,
          'email': email,
          'must_change_password': mustChangePassword,
        },
      ),
    );
    return User.fromJson((data as Map).cast<String, dynamic>());
  }

  /// Sends only [changes]; for `email`, null clears it.
  Future<User> update(int id, Map<String, dynamic> changes) async {
    final data = await _api.send((d) => d.patch('/users/$id', data: changes));
    return User.fromJson((data as Map).cast<String, dynamic>());
  }
}
