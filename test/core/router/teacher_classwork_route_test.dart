import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/router/app_router.dart';
import 'package:elixr_application/services/join_link_service.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/teacher/teacher_phase3_test_support.dart';

Iterable<GoRoute> _goRoutes(Iterable<RouteMatchBase> matches) sync* {
  for (final match in matches) {
    if (match is RouteMatch) {
      yield match.route;
    } else if (match is ShellRouteMatch) {
      yield* _goRoutes(match.matches);
    }
  }
}

void main() {
  test('Class Challenge play route is registered exactly once', () {
    final auth = phase3TeacherAuth();
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(
      auth,
      tutorials,
      joinLinks,
      TraineeProgressionService.ready(),
    );
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    addTearDown(tutorials.dispose);
    addTearDown(joinLinks.dispose);

    final playPath =
        '${AppRoutePaths.classChallengePlayPrefix}/:groupId/:challengeId';
    final configured = router.configuration.routes.whereType<GoRoute>().where(
      (route) => route.path == playPath,
    );
    final location = AppRoutePaths.classChallengePlay('group-1', 'challenge-1');
    final matches = router.configuration.findMatch(Uri.parse(location));

    expect(configured, hasLength(1));
    expect(matches.isError, isFalse);
    expect(matches.pathParameters, {
      'groupId': 'group-1',
      'challengeId': 'challenge-1',
    });
  });

  test('activity center routes remain in their owning shell trees', () {
    final auth = phase3TeacherAuth();
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(
      auth,
      tutorials,
      joinLinks,
      TraineeProgressionService.ready(),
    );
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    addTearDown(tutorials.dispose);
    addTearDown(joinLinks.dispose);

    final shellRoutes = router.configuration.routes
        .whereType<ShellRoute>()
        .toList(growable: false);
    final traineeShell = shellRoutes.singleWhere(
      (shell) => shell.routes.whereType<GoRoute>().any(
        (route) => route.path == AppRoutePaths.dashboard,
      ),
    );
    final teacherShell = shellRoutes.singleWhere(
      (shell) => shell.routes.whereType<GoRoute>().any(
        (route) => route.path == AppRoutePaths.teacherDashboard,
      ),
    );

    expect(
      traineeShell.routes.whereType<GoRoute>().map((route) => route.path),
      contains(AppRoutePaths.activityCenter),
    );
    expect(
      teacherShell.routes.whereType<GoRoute>().map((route) => route.path),
      contains(AppRoutePaths.teacherActivityCenter),
    );
    expect(
      teacherShell.routes.whereType<GoRoute>().map((route) => route.path),
      contains(AppRoutePaths.teacherCalendar),
    );
    expect(
      teacherShell.routes.whereType<GoRoute>().map((route) => route.path),
      contains(AppRoutePaths.teacherGrades),
    );
    expect(
      teacherShell.routes.whereType<GoRoute>().map((route) => route.path),
      isNot(contains(AppRoutePaths.activityCenter)),
    );
  });

  test(
    'personal custom practice is a full training route outside AppShell',
    () {
      final auth = phase3TeacherAuth();
      final tutorials = TutorialProgressService();
      final joinLinks = JoinLinkService();
      final router = AppRouter.create(
        auth,
        tutorials,
        joinLinks,
        TraineeProgressionService.ready(),
      );
      addTearDown(router.dispose);
      addTearDown(auth.dispose);
      addTearDown(tutorials.dispose);
      addTearDown(joinLinks.dispose);

      final canonical = router.configuration.findMatch(
        Uri.parse(AppRoutePaths.movementsMyMovementPractice('move-1')),
      );
      expect(canonical.isError, isFalse);
      expect(canonical.pathParameters, {'movementId': 'move-1'});
      // Like official `/practice`, no shell (sidebar) wraps the page.
      expect(canonical.matches.whereType<ShellRouteMatch>(), isEmpty);
      expect(
        router.configuration.routes.whereType<GoRoute>().where(
          (route) => route.path == AppRoutePaths.customMovementPracticePattern,
        ),
        hasLength(1),
      );
      final traineeShell = router.configuration.routes
          .whereType<ShellRoute>()
          .singleWhere(
            (shell) => shell.routes.whereType<GoRoute>().any(
              (route) => route.path == AppRoutePaths.dashboard,
            ),
          );
      expect(
        traineeShell.routes.whereType<GoRoute>().map((route) => route.path),
        isNot(contains(AppRoutePaths.customMovementPracticePattern)),
      );

      // The legacy deep link resolves to a redirect-only route, not a second
      // practice screen.
      final legacy = router.configuration.findMatch(
        Uri.parse(AppRoutePaths.myMovementPractice('move-1')),
      );
      final legacyRoute = _goRoutes(legacy.matches).last;
      expect(legacyRoute.redirect, isNotNull);
      expect(legacyRoute.pageBuilder, isNull);
      expect(legacyRoute.builder, isNull);
    },
  );

  test('classwork deep link matches one group-detail page route', () {
    final auth = phase3TeacherAuth();
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(
      auth,
      tutorials,
      joinLinks,
      TraineeProgressionService.ready(),
    );
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    addTearDown(tutorials.dispose);
    addTearDown(joinLinks.dispose);

    final location = AppRoutePaths.teacherGroupClasswork(
      'group-1',
      'assignment-1',
      traineeId: 'trainee-1',
    );
    final matches = router.configuration.findMatch(Uri.parse(location));
    final paths = _goRoutes(
      matches.matches,
    ).map((route) => route.path).toList(growable: false);

    expect(matches.isError, isFalse);
    expect(paths, ['/teacher/groups/:groupId/classwork/:assignmentId']);
    expect(matches.pathParameters['groupId'], 'group-1');
    expect(matches.pathParameters['assignmentId'], 'assignment-1');
  });
}
