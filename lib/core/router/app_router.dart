import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/training_prop.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/assigned_movements/assigned_movements_screen.dart';
import '../../features/assigned_movements/assigned_practice_screen.dart';
import '../../features/assigned_movements/assignment_detail_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/complete_google_profile_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/teacher_register_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/terms_of_service_screen.dart';
import '../../features/learning/learning_center_screen.dart';
import '../../features/learning/movement_lesson.dart';
import '../../features/movements/movements_screen.dart';
import '../../features/practice/live_practice_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../features/profile/profile_route_args.dart';
import '../../features/profile/user_profile_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/teacher/dashboard/teacher_dashboard_screen.dart';
import '../../features/teacher/faculties/teacher_faculties_screen.dart';
import '../../features/teacher/groups/teacher_group_detail_screen.dart';
import '../../features/teacher/groups/teacher_groups_screen.dart';
import '../../features/teacher/leaderboard/teacher_leaderboard_screen.dart';
import '../../features/teacher/movements/teacher_movements_screen.dart';
import '../../features/teacher/students/teacher_student_detail_screen.dart';
import '../../features/teacher/students/teacher_students_screen.dart';
import '../../features/settings/settings_section.dart';
import '../../features/teacher/teacher_settings_screen.dart';
import '../../features/teacher_access/join_teacher_screen.dart';
import '../../features/teacher_access/trainee_class_detail_screen.dart';
import '../../features/training/training_screen.dart';
import '../../features/training/training_view.dart';
import '../../services/auth_service.dart';
import '../../services/join_link_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../shell/teacher_shell.dart';
import '../widgets/app_shell.dart';
import 'app_redirect.dart';
import 'app_route_paths.dart';
import 'page_transitions.dart';

class AppRouter {
  static GoRouter create(
    AuthService authService,
    TutorialProgressService tutorialProgress,
    JoinLinkService joinLinks,
  ) {
    return GoRouter(
      initialLocation: AppRoutePaths.login,
      refreshListenable: Listenable.merge([
        authService,
        tutorialProgress,
        joinLinks,
      ]),
      redirect: (context, state) {
        final location = state.matchedLocation;
        return resolveAppRedirect(
          AppRedirectState(
            isLoading: authService.isLoading,
            isAuthenticated: authService.isAuthenticated,
            user: authService.currentUser,
            needsEmailVerification: authService.needsEmailVerification,
            location: location,
            hasPendingJoinCode: joinLinks.hasPendingCode,
            tutorialInitialized: tutorialProgress.isInitialized,
            practiceMovement:
                state.uri.queryParameters['movement'] ?? 'Hand Stall',
            practiceDifficulty:
                state.uri.queryParameters['difficulty'] ?? 'Easy',
            practiceProp: TrainingProp.fromProtocolValue(
              state.uri.queryParameters['prop'],
            ).protocolValue,
            hasCompletedLesson: tutorialProgress.hasCompletedLesson,
            hasPendingGoogleProfile: authService.hasPendingGoogleProfile,
          ),
        );
      },
      routes: [
        GoRoute(
          path: AppRoutePaths.login,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.register,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const RegisterScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.registerTeacher,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const TeacherRegisterScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.completeGoogleProfile,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const CompleteGoogleProfileScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.forgotPassword,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const ForgotPasswordScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.verifyEmail,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const VerifyEmailScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.privacyPolicy,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const PrivacyPolicyScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.termsOfService,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const TermsOfServiceScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.joinCoach,
          redirect: (context, state) => AppRoutePaths.teacherAccess,
        ),
        GoRoute(
          path: AppRoutePaths.practice,
          pageBuilder: (context, state) {
            final movement =
                state.uri.queryParameters['movement'] ?? 'Hand Stall';
            final difficulty =
                state.uri.queryParameters['difficulty'] ?? 'Easy';
            final prop = TrainingProp.fromProtocolValue(
              state.uri.queryParameters['prop'],
            );
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
          path: AppRoutePaths.livePractice,
          pageBuilder: (context, state) => fadeTransitionPage(
            key: state.pageKey,
            child: const LivePracticeScreen(),
          ),
        ),
        GoRoute(
          path: '${AppRoutePaths.assignedPracticePrefix}/:assignmentId',
          pageBuilder: (context, state) {
            final assignmentId = state.pathParameters['assignmentId'] ?? '';
            return fadeTransitionPage(
              key: state.pageKey,
              child: AssignedPracticeScreen(assignmentId: assignmentId),
            );
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutePaths.dashboard,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const DashboardScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.teacherAccess,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherAccessScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':groupId',
                  pageBuilder: (context, state) {
                    final groupId = state.pathParameters['groupId'] ?? '';
                    return fadeTransitionPage(
                      key: state.pageKey,
                      child: TraineeClassDetailScreen(groupId: groupId),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: AppRoutePaths.leaderboard,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const LeaderboardScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.movements,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const MovementsScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.assignedMovements,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const AssignedMovementsScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':assignmentId',
                  pageBuilder: (context, state) {
                    final assignmentId =
                        state.pathParameters['assignmentId'] ?? '';
                    return fadeTransitionPage(
                      key: state.pageKey,
                      child: AssignmentDetailScreen(assignmentId: assignmentId),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: AppRoutePaths.learn,
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
                final assignmentId = state.uri.queryParameters['assignmentId']
                    ?.trim();
                return fadeTransitionPage(
                  key: state.pageKey,
                  child: MovementLessonScreen(
                    movement: movement,
                    difficulty: difficulty,
                    prop: prop,
                    assignmentId: (assignmentId == null || assignmentId.isEmpty)
                        ? null
                        : assignmentId,
                  ),
                );
              },
            ),
            GoRoute(
              path: AppRoutePaths.training,
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
              path: AppRoutePaths.history,
              redirect: (context, state) => trainingLocationFromHistory(
                date:
                    state.uri.queryParameters[TrainingView.dateQueryParameter],
              ),
            ),
            GoRoute(
              path: AppRoutePaths.calendar,
              redirect: (context, state) => trainingLocationFromCalendar(
                date:
                    state.uri.queryParameters[TrainingView.dateQueryParameter],
              ),
            ),
            GoRoute(
              path: AppRoutePaths.coaching,
              redirect: (context, state) => AppRoutePaths.messages,
            ),
            GoRoute(
              path: AppRoutePaths.messages,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: _messagesScreen(state),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.progress,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const ProgressScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.achievements,
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
        ShellRoute(
          builder: (context, state, child) => TeacherShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutePaths.teacherDashboard,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherDashboardScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.teacherGroups,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherGroupsScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':groupId',
                  pageBuilder: (context, state) {
                    final groupId = state.pathParameters['groupId'] ?? '';
                    return fadeTransitionPage(
                      key: state.pageKey,
                      child: TeacherGroupDetailScreen(groupId: groupId),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: AppRoutePaths.teacherFaculties,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherFacultiesScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.teacherStudents,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherStudentsScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':traineeId',
                  pageBuilder: (context, state) {
                    final traineeId = state.pathParameters['traineeId'] ?? '';
                    return fadeTransitionPage(
                      key: state.pageKey,
                      child: TeacherStudentDetailScreen(
                        traineeId: traineeId,
                        preferredGroupId: state.uri.queryParameters['groupId'],
                      ),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: AppRoutePaths.teacherLeaderboard,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherLeaderboardScreen(),
              ),
            ),
            GoRoute(
              path: '${AppRoutePaths.teacherProfilePrefix}/:userId',
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
            GoRoute(
              path: AppRoutePaths.teacherMovements,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: const TeacherMovementsScreen(),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.teacherMessages,
              pageBuilder: (context, state) => fadeTransitionPage(
                key: state.pageKey,
                child: _messagesScreen(state),
              ),
            ),
            GoRoute(
              path: AppRoutePaths.teacherSettings,
              pageBuilder: (context, state) {
                final section = tryParseSettingsSection(
                  state.uri.queryParameters[AppRoutePaths
                      .teacherSettingsSectionQuery],
                );
                return fadeTransitionPage(
                  key: state.pageKey,
                  child: TeacherSettingsScreen(initialSection: section),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  static MessagesScreen _messagesScreen(GoRouterState state) {
    final query = state.uri.queryParameters;
    return MessagesScreen(
      initialUserId: query['userId'],
      initialDisplayName: query['name'],
      initialRole: query['role'],
      initialAvatarUrl: query['avatar'],
    );
  }
}
