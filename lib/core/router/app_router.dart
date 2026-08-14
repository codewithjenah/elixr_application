import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/coaching/coaching_notes_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/terms_of_service_screen.dart';
import '../../features/movements/movements_screen.dart';
import '../../features/practice/live_practice_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/profile/profile_route_args.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../data/models/training_prop.dart';
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
        final location = state.matchedLocation;
        final isAuthRoute =
            location == '/login' ||
            location == '/register' ||
            location == '/forgot-password';
        final isPublicLegalRoute =
            location == '/privacy-policy' || location == '/terms-of-service';
        final isPublicRoute = isAuthRoute || isPublicLegalRoute;

        if (!isAuth && !isPublicRoute) return '/login';
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
          path: '/forgot-password',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const ForgotPasswordScreen(),
          ),
        ),
        GoRoute(
          path: '/privacy-policy',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const PrivacyPolicyScreen(),
          ),
        ),
        GoRoute(
          path: '/terms-of-service',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const TermsOfServiceScreen(),
          ),
        ),
        GoRoute(
          path: '/practice',
          pageBuilder: (context, state) {
            final movement =
                state.uri.queryParameters['movement'] ?? 'Hand Stall';
            final difficulty =
                state.uri.queryParameters['difficulty'] ?? 'Easy';
            final prop = TrainingProp.fromProtocolValue(
              state.uri.queryParameters['prop'],
            );
            // Include movement/prop in the page key so /practice?... →
            // /practice?movement=Other recreates PracticeScreen. go_router's
            // default pageKey is path-only and would reuse the old State
            // (late finals for movement/difficulty/prop never update).
            return fadeTransitionPage(
              key: ValueKey(
                'practice:$movement|$difficulty|${prop.protocolValue}',
              ),
              child: PracticeScreen(
                movement: movement,
                difficulty: difficulty,
                prop: prop,
              ),
            );
          },
        ),
        GoRoute(
          path: '/live-practice',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const LivePracticeScreen(),
          ),
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
              path: '/leaderboard',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const LeaderboardScreen(),
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
              path: '/calendar',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: CalendarScreen(
                  initialDate: state.uri.queryParameters['date'],
                ),
              ),
            ),
            GoRoute(
              path: '/coaching',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const CoachingNotesScreen(),
              ),
            ),
            GoRoute(
              path: '/progress',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const ProgressScreen(),
              ),
            ),
            GoRoute(
              path: '/achievements',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const AchievementsScreen(),
              ),
            ),
            GoRoute(
              path: '/profile/:userId',
              pageBuilder: (context, state) {
                final userId = state.pathParameters['userId'] ?? '';
                final args = state.extra is ProfileRouteArgs
                    ? state.extra! as ProfileRouteArgs
                    : null;
                return fadeTransitionPage(
                  key: state.pageKey,
                  child: UserProfileScreen(userId: userId, initialArgs: args),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
