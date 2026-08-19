import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/coaching/coaching_notes_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/training/training_screen.dart';
import '../../features/training/training_view.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/terms_of_service_screen.dart';
import '../../features/movements/movements_screen.dart';
import '../../features/learning/learning_center_screen.dart';
import '../../features/learning/movement_lesson.dart';
import '../../features/practice/live_practice_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/profile/profile_route_args.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../data/models/training_prop.dart';
import '../../services/auth_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../../services/join_link_service.dart';
import '../../features/teacher_access/join_teacher_screen.dart';
import '../widgets/app_shell.dart';
import 'page_transitions.dart';

class AppRouter {
  static GoRouter create(
    AuthService authService,
    TutorialProgressService tutorialProgress,
    JoinLinkService joinLinks,
  ) {
    return GoRouter(
      initialLocation: '/login',
      refreshListenable: Listenable.merge([
        authService,
        tutorialProgress,
        joinLinks,
      ]),
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
        if (isAuth && joinLinks.hasPendingCode && location != '/join-coach') {
          return '/join-coach';
        }
        if (isAuth && isAuthRoute) return '/dashboard';
        if (isAuth &&
            location == '/practice' &&
            tutorialProgress.isInitialized) {
          final movement =
              state.uri.queryParameters['movement'] ?? 'Hand Stall';
          if (!tutorialProgress.hasCompletedLesson(movement)) {
            final difficulty =
                state.uri.queryParameters['difficulty'] ?? 'Easy';
            final prop = TrainingProp.fromProtocolValue(
              state.uri.queryParameters['prop'],
            );
            return '/learn/movement/${Uri.encodeComponent(movement)}'
                '?difficulty=$difficulty&prop=${prop.protocolValue}';
          }
        }
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
          path: '/join-coach',
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const JoinTeacherScreen(),
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
              path: '/learn',
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const LearningCenterScreen(),
              ),
            ),
            GoRoute(
              path: '/learn/movement/:movementName',
              pageBuilder: (context, state) {
                final movement = state.pathParameters['movementName'] ?? '';
                final difficulty =
                    state.uri.queryParameters['difficulty'] ?? 'Easy';
                final prop = TrainingProp.fromProtocolValue(
                  state.uri.queryParameters['prop'],
                );
                return fadeTransitionPage(
                  key: state.pageKey,
                  child: MovementLessonScreen(
                    movement: movement,
                    difficulty: difficulty,
                    prop: prop,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/training',
              pageBuilder: (context, state) {
                final view = TrainingView.fromQuery(
                  state.uri.queryParameters[TrainingView.viewQueryParameter],
                );
                return fadeTransitionPage(
                  key: state.pageKey,
                  child: TrainingScreen(
                    view: view,
                    date: state
                        .uri
                        .queryParameters[TrainingView.dateQueryParameter],
                  ),
                );
              },
            ),
            GoRoute(
              path: '/history',
              redirect: (context, state) => trainingLocationFromHistory(
                date:
                    state.uri.queryParameters[TrainingView.dateQueryParameter],
              ),
            ),
            GoRoute(
              path: '/calendar',
              redirect: (context, state) => trainingLocationFromCalendar(
                date:
                    state.uri.queryParameters[TrainingView.dateQueryParameter],
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
