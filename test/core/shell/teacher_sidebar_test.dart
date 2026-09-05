import 'package:elixr_application/core/constants/app_constants.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/shell/teacher_sidebar.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_sidebar_chrome.dart';
import 'package:elixr_application/core/widgets/message_unread_badge.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/teacher/activity_center/teacher_activity_controller.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/message_unread_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/teacher/teacher_phase3_test_support.dart';

void main() {
  test('teacher sidebar groups include the Calendar destination', () {
    List<String> routesIn(TeacherSidebarGroup group) {
      return teacherSidebarItems
          .where((item) => item.group == group)
          .map((item) => item.route)
          .toList();
    }

    expect(teacherSidebarItems, hasLength(11));
    expect(routesIn(TeacherSidebarGroup.classroom), [
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.teacherCalendar,
      AppRoutePaths.teacherGroups,
      AppRoutePaths.teacherFaculties,
      AppRoutePaths.teacherStudents,
      AppRoutePaths.teacherMovements,
      AppRoutePaths.teacherToReview,
    ]);
    expect(routesIn(TeacherSidebarGroup.insights), [
      AppRoutePaths.teacherLeaderboard,
      AppRoutePaths.teacherAnalytics,
      AppRoutePaths.teacherActivityCenter,
      AppRoutePaths.teacherMessages,
    ]);
    final notifications = teacherSidebarItems.singleWhere(
      (item) => item.label == 'Notifications',
    );
    expect(notifications.route, AppRoutePaths.teacherActivityCenter);
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
        '${AppRoutePaths.teacherGroups}/group-1',
        AppRoutePaths.teacherGroups,
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

    expect(
      find.image(const AssetImage(AppConstants.appLogoAsset)),
      findsOneWidget,
    );
    expect(find.text(AppConstants.appName), findsAtLeastNWidgets(1));
    expect(find.text('Teacher'), findsWidgets);
    expect(find.text('CLASSROOM'), findsOneWidget);
    expect(find.text('INSIGHTS'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('EXP'), findsNothing);
    expect(find.textContaining('Lv.'), findsNothing);
  });

  testWidgets(
    'Classrooms badge follows pending joins without affecting other badges',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final auth = phase3TeacherAuth();
      final activity = _SidebarActivityController(
        pendingJoinCountValue: 2,
        pendingReviewCountValue: 3,
        unreadCountValue: 4,
      );
      final messages = _MessageUnreadService()..value = 5;
      addTearDown(auth.dispose);
      addTearDown(activity.dispose);
      addTearDown(messages.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            ChangeNotifierProvider<TeacherActivityController>.value(
              value: activity,
            ),
            ChangeNotifierProvider<MessageUnreadService>.value(value: messages),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: Row(
              children: [
                TeacherSidebar(
                  currentRoute: AppRoutePaths.teacherDashboard,
                  isCollapsed: false,
                  onToggleCollapse: () {},
                  onLogout: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      Finder badgeFor(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(ElixSidebarNavTile),
        ),
        matching: find.byType(MessageUnreadBadge),
      );

      expect(badgeFor('Classrooms'), findsOneWidget);
      expect(badgeFor('To Review'), findsOneWidget);
      expect(badgeFor('Notifications'), findsOneWidget);
      expect(badgeFor('Messages'), findsOneWidget);

      activity.pendingJoinCountValue = 0;
      activity.notifyListeners();
      await tester.pump();

      expect(badgeFor('Classrooms'), findsNothing);
      expect(badgeFor('To Review'), findsOneWidget);
      expect(badgeFor('Notifications'), findsOneWidget);
      expect(badgeFor('Messages'), findsOneWidget);
    },
  );
}

class _SidebarActivityController extends TeacherActivityController {
  _SidebarActivityController({
    required this.pendingJoinCountValue,
    required this.pendingReviewCountValue,
    required this.unreadCountValue,
  }) : super(
         groupRepository: InMemoryGroupRepository(),
         assignmentRepository: InMemoryClassroomAssignmentRepository(),
         chatRepository: InMemoryChatRepository(),
         readStore: InMemoryActivityReadStore(),
       );

  int pendingJoinCountValue;
  final int pendingReviewCountValue;
  final int unreadCountValue;

  @override
  int get pendingJoinCount => pendingJoinCountValue;

  @override
  int get pendingReviewCount => pendingReviewCountValue;

  @override
  int get unreadCount => unreadCountValue;
}

class _MessageUnreadService extends MessageUnreadService {
  _MessageUnreadService() : super(repository: InMemoryChatRepository());

  int _value = 0;

  set value(int value) {
    _value = value;
    notifyListeners();
  }

  @override
  int get unreadCount => _value;
}
