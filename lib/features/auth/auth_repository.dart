import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/token_store.dart';
import '../../core/i18n.dart';

/// The backend's /auth endpoints. Stores the token pair on every sign-in.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<User> login(String login, String password) async {
    try {
      final data = await _api.send((d) => d.post('/auth/login', data: {'login': login, 'password': password}));
      await _storePair(data);
    } on ApiException catch (e) {
      // The server never says which part was wrong — neither do we.
      if (e.statusCode == 401) throw ApiException(401, tr('Nieprawidłowy login lub hasło.'));
      rethrow;
    }
    return me();
  }

  Future<User> me() async {
    final data = await _api.send((d) => d.get('/auth/me'));
    return User.fromJson((data as Map).cast<String, dynamic>());
  }

  /// [current] may be null only while the account must change its password.
  Future<void> changePassword(String? current, String next) async {
    try {
      final data = await _api.send(
        (d) => d.post('/auth/change-password', data: {'current_password': ?current, 'new_password': next}),
      );
      // Every other session ends; this one gets a fresh pair.
      await _storePair(data);
    } on ApiException catch (e) {
      if (e.statusCode == 401) throw ApiException(401, tr('Obecne hasło jest nieprawidłowe.'));
      if (e.statusCode == 400) throw ApiException(400, tr('Nowe hasło musi różnić się od obecnego.'));
      rethrow;
    }
  }

  /// Ends this session. Local tokens go even if the server cannot be reached.
  Future<void> logout() async {
    final refresh = _tokens.refresh;
    if (refresh != null) {
      try {
        await _api.send((d) => d.post('/auth/logout', data: {'refresh_token': refresh}));
      } catch (_) {
        // Signing out must never be blocked by the network.
      }
    }
    await _tokens.clear();
  }

  Future<void> logoutEverywhere() async {
    await _api.send((d) => d.post('/auth/logout-all'));
    await _tokens.clear();
  }

  Future<void> _storePair(dynamic data) async {
    final map = data as Map;
    await _tokens.save(access: map['access_token'] as String, refresh: map['refresh_token'] as String);
  }
}
