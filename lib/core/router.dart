import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/audit/audit_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/set_password_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/dictionaries/dictionaries_screen.dart';
import '../features/incidents/incident_screen.dart';
import '../features/incidents/incidents_screen.dart';
import '../features/incidents/new_incident_screen.dart';
import '../features/operators/operator_screen.dart';
import '../features/operators/operators_screen.dart';
import '../features/permits/permits_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/report/report_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/trucks/trucks_screen.dart';
import '../features/users/users_screen.dart';
import 'providers.dart';

/// Re-runs the router's redirect whenever the session changes, and when the
/// start screen's animation has played through.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(splashShownProvider, (_, _) => notifyListeners());
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
      // A truck's sticker: the operator's report form, open to anyone holding the code.
      GoRoute(
        path: '/t/:token',
        builder: (_, state) => ReportScreen(truckToken: state.pathParameters['token']!),
      ),
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/operators',
                builder: (_, _) => const OperatorsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => OperatorScreen(operatorId: int.parse(state.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/permits', builder: (_, _) => const PermitsScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/incidents',
                builder: (_, _) => const IncidentsScreen(),
                routes: [
                  // Before ':id', which would take "new" for a number.
                  GoRoute(path: 'new', builder: (_, _) => const NewIncidentScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => IncidentScreen(incidentId: int.parse(state.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen())],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      // Operators have no accounts: the report form never waits for or needs a session.
      if (loc.startsWith('/t/')) return null;
      // The start screen stays until its animation has played through once.
      if (loc == '/splash' && !ref.read(splashShownProvider)) return null;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return loc == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          // A starting password from the administrator opens nothing else.
          if (auth.user?.mustChangePassword ?? false) return loc == '/set-password' ? null : '/set-password';
          final isAdmin = auth.user?.role.isAdmin ?? false;
          if (loc == '/splash' || loc == '/login' || loc == '/set-password') return '/incidents';
          if (!isAdmin && _adminOnly.any(loc.startsWith)) return '/incidents';
          return null;
      }
    },
  );
});
