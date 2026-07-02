import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/movements/movements_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../services/auth_service.dart';
import '../widgets/app_shell.dart';
import 'page_transitions.dart';

class AppRouter {
  static GoRouter create(AuthService authService) {
    return GoRouter(
      initialLocation: '/login',
      refreshListenable: authService,
      redirect: (context, state) {
        if (authService.isLoading) return null;

        final isAuth = authService.isAuthenticated;
        final isAuthRoute =
            state.matchedLocation == '/login' ||
            state.matchedLocation == '/register';

        if (!isAuth && !isAuthRoute) return '/login';
        if (isAuth && isAuthRoute) return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: '/register',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const RegisterScreen(),
          ),
        ),
        GoRoute(
          path: '/practice',
          pageBuilder: (context, state) {
            final movement =
                state.uri.queryParameters['movement'] ?? 'Hand Stall';
            final difficulty =
                state.uri.queryParameters['difficulty'] ?? 'Easy';
            return fadeTransitionPage(
              key: state.pageKey,
              child: PracticeScreen(
                movement: movement,
                difficulty: difficulty,
              ),
            );
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const DashboardScreen(),
              ),
            ),
            GoRoute(
              path: '/movements',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const MovementsScreen(),
              ),
            ),
            GoRoute(
              path: '/history',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const HistoryScreen(),
              ),
            ),
            GoRoute(
              path: '/progress',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const ProgressScreen(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
