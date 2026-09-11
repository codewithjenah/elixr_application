import 'package:elixr_application/core/constants/app_constants.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/shell/teacher_sidebar.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_sidebar_chrome.dart';
import 'package:elixr_application/core/widgets/message_unread_badge.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
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
  test('teacher sidebar follows the daily Teacher workflow', () {
    expect(teacherSidebarItems, hasLength(10));
    expect(teacherSidebarItems.map((item) => item.label), [
      'Dashboard',
      'Classrooms',
      'Activity Library',
      'Review Work',
      'Grades',
      'Students',
      'Calendar',
      'Progress',
      'Analytics',
      'Messages',
    ]);
    expect(teacherSidebarItems.map((item) => item.route), [
      AppRoutePaths.teacherDashboard,
      AppRoutePaths.teacherGroups,
      AppRoutePaths.teacherMovements,
      AppRoutePaths.teacherToReview,
      AppRoutePaths.teacherGrades,
      AppRoutePaths.teacherStudents,
      AppRoutePaths.teacherCalendar,
      AppRoutePaths.teacherProgress,
      AppRoutePaths.teacherAnalytics,
      AppRoutePaths.teacherMessages,
    ]);
    expect(teacherSidebarUtilityItems, hasLength(2));
    expect(teacherSidebarUtilityItems.map((item) => item.label), [
      'Notifications',
      'Teacher Access',
    ]);
    final notifications = teacherSidebarUtilityItems.singleWhere(
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
        AppRoutePaths.teacherGrades,
        AppRoutePaths.teacherGrades,
      ),
      isTrue,
    );
    expect(
      isTeacherSidebarRouteActive(
        '${AppRoutePaths.teacherGrades}/classroom-1',
        AppRoutePaths.teacherGrades,
      ),
      isTrue,
    );
    expect(
      isTeacherSidebarRouteActive(
        AppRoutePaths.teacherGradesForGroup('group-1'),
        AppRoutePaths.teacherGrades,
      ),
      isTrue,
    );
    expect(
      isTeacherSidebarRouteActive(
        AppRoutePaths.teacherGrades,
        AppRoutePaths.teacherStudents,
      ),
      isFalse,
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

  test('Progress stays active for the retained Leaderboard deep link', () {
    final progress = teacherSidebarItems.singleWhere(
      (item) => item.label == 'Progress',
    );
    final analytics = teacherSidebarItems.singleWhere(
      (item) => item.label == 'Analytics',
    );

    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherProgress, progress),
      isTrue,
    );
    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherLeaderboard, progress),
      isTrue,
    );
    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherAnalytics, progress),
      isFalse,
    );
    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherAnalytics, analytics),
      isTrue,
    );
    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherProgress, analytics),
      isFalse,
    );
    expect(
      isTeacherSidebarItemActive(AppRoutePaths.teacherLeaderboard, analytics),
      isFalse,
    );
  });

  testWidgets('Grades is selected on the grades destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: const Row(
            children: [
              TeacherSidebar(
                currentRoute: AppRoutePaths.teacherGrades,
                isCollapsed: false,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    ElixSidebarNavTile tileFor(String label) => tester
        .widgetList<ElixSidebarNavTile>(find.byType(ElixSidebarNavTile))
        .firstWhere((tile) => tile.label == label);

    expect(find.text('Grades'), findsOneWidget);
    expect(tileFor('Grades').isActive, isTrue);
    expect(tileFor('Review Work').isActive, isFalse);
    expect(tileFor('Students').isActive, isFalse);
  });

  testWidgets('Analytics is selected on the analytics route', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: const Row(
            children: [
              TeacherSidebar(
                currentRoute: AppRoutePaths.teacherAnalytics,
                isCollapsed: false,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    ElixSidebarNavTile tileFor(String label) => tester
        .widgetList<ElixSidebarNavTile>(find.byType(ElixSidebarNavTile))
        .firstWhere((tile) => tile.label == label);

    expect(find.text('Analytics'), findsOneWidget);
    expect(tileFor('Analytics').isActive, isTrue);
    expect(tileFor('Progress').isActive, isFalse);
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
    expect(find.text('Teacher Workspace'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(find.text('UTILITIES'), findsOneWidget);
    expect(find.byType(ElixSidebarPane), findsOneWidget);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('EXP'), findsNothing);
    expect(find.textContaining('Lv.'), findsNothing);
  });

  testWidgets('teacher sidebar renders the canonical profile frame', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth(profileBorderId: 'starter_glow');
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider<AuthService>.value(value: auth)],
        child: FluentApp(
          theme: AppTheme.dark,
          home: const Row(
            children: [
              TeacherSidebar(
                currentRoute: AppRoutePaths.teacherDashboard,
                isCollapsed: false,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_sidebar_avatar')),
    );
    expect(avatar.equippedBorderId, 'starter_glow');
    expect(avatar.animateBorder, isTrue);
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
      expect(badgeFor('Review Work'), findsOneWidget);
      expect(badgeFor('Notifications'), findsOneWidget);
      expect(badgeFor('Messages'), findsOneWidget);

      activity.pendingJoinCountValue = 0;
      activity.notifyListeners();
      await tester.pump();

      expect(badgeFor('Classrooms'), findsNothing);
      expect(badgeFor('Review Work'), findsOneWidget);
      expect(badgeFor('Notifications'), findsOneWidget);
      expect(badgeFor('Messages'), findsOneWidget);
    },
  );

  testWidgets('teacher sidebar uses the shared docked pane when collapsed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: const Row(
            children: [
              TeacherSidebar(
                currentRoute: AppRoutePaths.teacherDashboard,
                isCollapsed: true,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(ElixSidebarMetrics.paneMotion);

    expect(tester.takeException(), isNull);
    expect(find.byType(ElixSidebarPane), findsOneWidget);
    expect(find.text('Teacher Workspace'), findsNothing);
    expect(find.text('EXP'), findsNothing);

    final pane = tester.widget<ElixSidebarPane>(find.byType(ElixSidebarPane));
    expect(pane.isCollapsed, isTrue);
    expect(
      tester.getSize(find.byType(ElixSidebarPane)).width,
      ElixSidebarMetrics.collapsedWidth,
    );

    final dashboard = tester
        .widgetList<ElixSidebarNavTile>(find.byType(ElixSidebarNavTile))
        .firstWhere((tile) => tile.label == 'Dashboard');
    expect(dashboard.isActive, isTrue);
    expect(dashboard.isCollapsed, isTrue);
  });

  testWidgets('teacher sidebar stays layout-safe through pane transitions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    var isCollapsed = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeacherSidebar(
                  currentRoute: AppRoutePaths.teacherDashboard,
                  isCollapsed: isCollapsed,
                  onToggleCollapse: () =>
                      setState(() => isCollapsed = !isCollapsed),
                  onLogout: _noop,
                ),
                const Expanded(child: ColoredBox(color: Color(0xFF050308))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ElixSidebarCollapseButton));
    await tester.pump();
    await tester.pump(ElixSidebarMetrics.paneMotion ~/ 2);
    expect(tester.takeException(), isNull);
    await tester.pump(ElixSidebarMetrics.paneMotion);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ElixSidebarCollapseButton));
    await tester.pump();
    await tester.pump(ElixSidebarMetrics.paneMotion ~/ 2);
    expect(tester.takeException(), isNull);
    await tester.pump(ElixSidebarMetrics.paneMotion);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

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
