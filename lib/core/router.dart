import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/audit/audit_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/dictionaries/dictionaries_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/trucks/trucks_screen.dart';
import '../features/users/users_screen.dart';
import 'providers.dart';

/// Re-runs the router's redirect whenever the session changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

/// Screens only administrators may open; everyone else is sent to /account.
const _adminOnly = ['/users', '/audit'];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/set-password', builder: (_, _) => const SetPasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/account', builder: (_, _) => const ProfileScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/users', builder: (_, _) => const UsersScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/audit', builder: (_, _) => const AuditScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/dictionaries', builder: (_, _) => const DictionariesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/trucks', builder: (_, _) => const TrucksScreen())],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          // A starting password from the administrator opens nothing else.
          if (auth.user?.mustChangePassword ?? false) return loc == '/set-password' ? null : '/set-password';
          final isAdmin = auth.user?.role.isAdmin ?? false;
          if (loc == '/splash' || loc == '/login' || loc == '/set-password') return isAdmin ? '/users' : '/account';
          if (!isAdmin && _adminOnly.any(loc.startsWith)) return '/account';
          return null;
      }
    },
  );
});
