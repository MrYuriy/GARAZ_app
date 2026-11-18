import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

/// An API answer the caller should show, with a Polish message for the user.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;

  /// What the server said, for logs and fields it reports by name.
  final Object? detail;

  @override
  String toString() => message;
}

enum RefreshOutcome {
  /// New tokens obtained and stored.
  refreshed,

  /// The server rejected the refresh token — the session is genuinely over.
  invalid,

  /// No network / server hiccup: the tokens are still good, keep the session.
  networkError,
}

/// Central HTTP client (pattern from langup_mobile).
///
/// Every request carries the Bearer access token, and a 401 triggers one
/// refresh + retry. Refresh tokens ROTATE on the server and each is good once,
/// so concurrent 401s must never each fire their own refresh: all of them
/// await one shared refresh call (single-flight).
class ApiClient {
  ApiClient(this.tokens) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
        // Callers read 4xx bodies themselves, so those do not throw — except
        // 401, which must reach onError, where the token is refreshed.
        validateStatus: (s) => s != null && s < 500 && s != 401,
      ),
    );
    // A bare Dio used only to refresh, so the refresh call can never recurse
    // back into the 401 handler.
    _refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final access = tokens.access;
          if (access != null && access.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $access';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final response = error.response;
          final canRetry = error.requestOptions.extra['__retried'] != true;

          if (response?.statusCode == 401 &&
              canRetry &&
              tokens.hasSession &&
              !_isAuthEndpoint(error.requestOptions.path)) {
            final outcome = await _refreshOnce();
            if (outcome == RefreshOutcome.refreshed) {
              try {
                final opts = error.requestOptions;
                opts.extra['__retried'] = true;
                opts.headers['Authorization'] = 'Bearer ${tokens.access}';
                return handler.resolve(await dio.fetch(opts));
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
            // Only sign out when the server actually rejected the refresh.
            if (outcome == RefreshOutcome.invalid) {
              await tokens.clear();
              onSessionExpired?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final TokenStore tokens;
  late final Dio dio;
  late final Dio _refreshDio;

  /// Wired by the auth controller to route back to the login screen.
  void Function()? onSessionExpired;

  Future<RefreshOutcome>? _refreshing;

  Future<RefreshOutcome> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<RefreshOutcome> _doRefresh() async {
    final token = tokens.refresh;
    if (token == null || token.isEmpty) return RefreshOutcome.invalid;
    try {
      final resp = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': token},
        options: Options(validateStatus: (s) => s != null),
      );
      final code = resp.statusCode ?? 0;
      if (code == 200 && resp.data is Map) {
        final data = resp.data as Map;
        await tokens.save(access: data['access_token'] as String, refresh: data['refresh_token'] as String);
        return RefreshOutcome.refreshed;
      }
      // 4xx: the refresh token is no good. 5xx: a server problem — keep it.
      if (code >= 400 && code < 500) return RefreshOutcome.invalid;
      return RefreshOutcome.networkError;
    } on DioException {
      return RefreshOutcome.networkError;
    }
  }

  static bool _isAuthEndpoint(String path) => const ['/auth/login', '/auth/refresh'].any(path.contains);

  /// Run a request and return its JSON body, or throw an [ApiException]
  /// with a message fit to show.
  Future<dynamic> send(Future<Response<dynamic>> Function(Dio dio) request) async {
    final Response<dynamic> resp;
    try {
      resp = await request(dio);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) throw ApiException(401, 'Sesja wygasła — zaloguj się ponownie.');
      if (status != null && status >= 500) {
        throw ApiException(status, 'Błąd serwera ($status). Spróbuj ponownie za chwilę.');
      }
      throw ApiException(0, 'Brak połączenia z serwerem.');
    }
    final code = resp.statusCode ?? 0;
    if (code >= 200 && code < 300) return resp.data;
    final detail = resp.data is Map ? (resp.data as Map)['detail'] : null;
    throw ApiException(code, messageFor(code, detail), detail: detail);
  }

  /// Polish text for a failed answer.
  static String messageFor(int code, Object? detail) {
    switch (code) {
      case 403:
        return 'Brak uprawnień do tej operacji.';
      case 404:
        return 'Nie znaleziono.';
      case 409:
        return 'Taki rekord już istnieje (np. login jest zajęty).';
      case 422:
        return 'Niepoprawne dane: ${_validationText(detail)}';
      case 429:
        return 'Zbyt wiele prób. Spróbuj ponownie za kilka minut.';
      default:
        return detail is String ? detail : 'Nie udało się ($code).';
    }
  }

  /// FastAPI's 422 detail is a list of {loc, msg}; show field: message.
  static String _validationText(Object? detail) {
    if (detail is List) {
      return detail
          .map((e) {
            if (e is Map) {
              final loc = (e['loc'] as List?)?.last;
              final msg = (e['msg'] ?? '').toString().replaceFirst('Value error, ', '');
              return loc != null ? '$loc — $msg' : msg;
            }
            return e.toString();
          })
          .join('; ');
    }
    return detail?.toString() ?? '';
  }
}
