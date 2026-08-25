import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/shell/teacher_sidebar.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/teacher/teacher_phase3_test_support.dart';

void main() {
  test('teacher sidebar groups keep the seven destinations', () {
    List<String> routesIn(TeacherSidebarGroup group) {
      return teacherSidebarItems
          .where((item) => item.group == group)
          .map((item) => item.route)
          .toList();
    }

    expect(teacherSidebarItems, hasLength(7));
    expect(routesIn(TeacherSidebarGroup.classroom), [
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.teacherGroups,
      AppRoutePaths.teacherFaculties,
      AppRoutePaths.teacherStudents,
    ]);
    expect(routesIn(TeacherSidebarGroup.insights), [
      AppRoutePaths.teacherLeaderboard,
      AppRoutePaths.teacherMovements,
      AppRoutePaths.teacherMessages,
    ]);
    expect(
      teacherSidebarItems.map((item) => item.route),
      isNot(contains(AppRoutePaths.teacherSettings)),
    );
  });

  test('isTeacherSidebarRouteActive matches destination and nested paths', () {
    expect(
      isTeacherSidebarRouteActive(
        AppRoutePaths.teacherDashboard,
        AppRoutePaths.teacherDashboard,
      ),
      isTrue,
    );
    expect(
      isTeacherSidebarRouteActive(
        '${AppRoutePaths.teacherStudents}/abc',
        AppRoutePaths.teacherStudents,
      ),
      isTrue,
    );
    expect(
      isTeacherSidebarRouteActive(
        AppRoutePaths.teacherDashboard,
        AppRoutePaths.teacherGroups,
      ),
      isFalse,
    );
  });

  testWidgets('teacher sidebar uses Trainee chrome without XP copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherDashboard,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherDashboard,
          builder: (context, state) => const SizedBox.shrink(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
          builder: (context, child) {
            return Row(
              children: [
                TeacherSidebar(
                  currentRoute: AppRoutePaths.teacherDashboard,
                  isCollapsed: false,
                  onToggleCollapse: () {},
                  onLogout: () {},
                ),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('E'), findsOneWidget);
    expect(find.text('Teacher'), findsWidgets);
    expect(find.text('CLASSROOM'), findsOneWidget);
    expect(find.text('INSIGHTS'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('EXP'), findsNothing);
    expect(find.textContaining('Lv.'), findsNothing);
  });
}
