import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/token_store.dart';
import 'auth_repository.dart';

enum AuthStatus {
  /// Startup: stored tokens not checked yet. The router shows a splash.
  unknown,
  unauthenticated,
  authenticated,
}

class AuthState {
  const AuthState(this.status, [this.user]);

  final AuthStatus status;
  final User? user;
}

/// Owns the session lifecycle and drives the router's redirects.
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo, this._api, this._tokens) : super(const AuthState(AuthStatus.unknown)) {
    // A refresh the server rejected drops us straight to the login screen.
    _api.onSessionExpired = () => state = const AuthState(AuthStatus.unauthenticated);
  }

  final AuthRepository _repo;
  final ApiClient _api;
  final TokenStore _tokens;

  /// Restore a stored session on launch without forcing a new sign-in.
  Future<void> bootstrap() async {
    await _tokens.load();
    if (!_tokens.hasSession) {
      state = const AuthState(AuthStatus.unauthenticated);
      return;
    }
    try {
      state = AuthState(AuthStatus.authenticated, await _repo.me());
    } catch (_) {
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String login, String password) async {
    state = AuthState(AuthStatus.authenticated, await _repo.login(login, password));
  }

  Future<void> refreshUser() async {
    try {
      state = AuthState(AuthStatus.authenticated, await _repo.me());
    } catch (_) {
      // A hard 401 already routes to login via onSessionExpired.
    }
  }

  /// Re-reads the user afterwards, so a cleared must-change flag lets the
  /// router move on from the new-password screen.
  Future<void> changePassword(String? current, String next) async {
    await _repo.changePassword(current, next);
    await refreshUser();
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(AuthStatus.unauthenticated);
  }

  Future<void> logoutEverywhere() async {
    try {
      await _repo.logoutEverywhere();
    } finally {
      await _tokens.clear();
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }
}
