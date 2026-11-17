import 'package:flutter/foundation.dart';

/// Runtime configuration.
///
/// Override the API base at build/run time:
///   flutter build web --dart-define=API_BASE_URL=/api
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000/api
class AppConfig {
  AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Base URL of the backend API (everything lives under `/api`).
  ///
  /// A web build served by the backend itself uses the relative `/api`, so it
  /// talks to whatever host is serving it. Without a define:
  ///  - Android emulator: 10.0.2.2 is the host machine's localhost;
  ///  - web/desktop dev: plain localhost.
  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://localhost:8000/api';
  }
}
