import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/router/app_router.dart';
import 'package:elixr_application/services/join_link_service.dart';
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
  test('activity center routes remain in their owning shell trees', () {
    final auth = phase3TeacherAuth();
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(auth, tutorials, joinLinks);
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    addTearDown(tutorials.dispose);
    addTearDown(joinLinks.dispose);

    final shellRoutes = router.configuration.routes
        .whereType<ShellRoute>()
        .toList(growable: false);
    final traineeShell = shellRoutes.singleWhere(
      (shell) => shell.routes
          .whereType<GoRoute>()
          .any((route) => route.path == AppRoutePaths.dashboard),
    );
    final teacherShell = shellRoutes.singleWhere(
      (shell) => shell.routes
          .whereType<GoRoute>()
          .any((route) => route.path == AppRoutePaths.teacherDashboard),
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
      isNot(contains(AppRoutePaths.activityCenter)),
    );
  });

  test('classwork deep link matches one group-detail page route', () {
    final auth = phase3TeacherAuth();
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(auth, tutorials, joinLinks);
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
