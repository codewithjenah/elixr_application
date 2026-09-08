import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/widgets/elix_sidebar.dart';
import 'package:elixr_application/core/widgets/elix_sidebar_chrome.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _UnusedAuthRepository extends Fake implements AuthRepositoryBase {}

void main() {
  test(
    'sidebar has one Sessions destination and no Calendar or History items',
    () {
      final labels = elixSidebarItems.map((item) => item.label).toList();
      expect(labels.where((label) => label == 'Sessions'), ['Sessions']);
      expect(labels.contains('Calendar'), isFalse);
      expect(labels.contains('History'), isFalse);
      expect(labels.contains('Assigned Movements'), isFalse);
      expect(labels.contains('Movements'), isTrue);

      final classroomIndex = labels.indexOf('Classroom');
      expect(classroomIndex, greaterThan(0));
      expect(labels[classroomIndex - 1], 'Dashboard');
      final classroom = elixSidebarItems[classroomIndex];
      expect(classroom.route, '/teacher-access');

      final playground = elixSidebarItems.singleWhere(
        (item) => item.label == 'Playground',
      );
      expect(playground.route, '/live-practice');

      final sessions = elixSidebarItems.singleWhere(
        (item) => item.label == 'Sessions',
      );
      expect(sessions.route, '/training');

      final notifications = elixSidebarItems.singleWhere(
        (item) => item.label == 'Notifications',
      );
      expect(notifications.route, '/activity-center');
      expect(notifications.group, SidebarGroup.insights);
    },
  );

  test('Sessions stays selected for planner and history paths', () {
    expect(isElixSidebarRouteActive('/training', '/training'), isTrue);
    expect(isElixSidebarRouteActive('/dashboard', '/training'), isFalse);
    expect(isElixSidebarRouteActive('/learn', '/training'), isFalse);
    expect(
      isElixSidebarRouteActive('/learn/movement/Hand%20Stall', '/learn'),
      isTrue,
    );
    expect(
      isElixSidebarRouteActive('/teacher-access', '/teacher-access'),
      isTrue,
    );
    expect(
      isElixSidebarRouteActive('/teacher-access/group-1', '/teacher-access'),
      isTrue,
    );
  });

  testWidgets('trainee sidebar identifies the trainee workspace', (
    tester,
  ) async {
    // A 960px-tall Windows window can be roughly this logical height under
    // common display scaling. The slogan must not be gated out at this size.
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = AuthService(
      repository: _UnusedAuthRepository(),
      awaitInitialAuthState: () async {},
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: const ElixSidebar(
            currentRoute: '/dashboard',
            isCollapsed: false,
            onToggleCollapse: _noop,
            onLogout: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Trainee Workspace'), findsOneWidget);
    expect(find.text('Flair Training'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.byType(ElixSidebarPane), findsOneWidget);
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);

    final dashboard = tester.widget<ElixSidebarNavTile>(
      find.ancestor(
        of: find.text('Dashboard'),
        matching: find.byType(ElixSidebarNavTile),
      ),
    );
    expect(dashboard.isActive, isTrue);
    expect(dashboard.isCollapsed, isFalse);
  });

  testWidgets('collapsed trainee sidebar keeps destinations usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = AuthService(
      repository: _UnusedAuthRepository(),
      awaitInitialAuthState: () async {},
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(
          theme: AppTheme.dark,
          home: const ElixSidebar(
            currentRoute: '/training',
            isCollapsed: true,
            onToggleCollapse: _noop,
            onLogout: _noop,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(ElixSidebarMetrics.paneMotion);

    expect(tester.takeException(), isNull);
    expect(find.byType(ElixSidebarPane), findsOneWidget);
    expect(find.text('Trainee Workspace'), findsNothing);
    expect(find.byType(ElixSidebarNavTile), findsWidgets);

    final pane = tester.widget<ElixSidebarPane>(find.byType(ElixSidebarPane));
    expect(pane.isCollapsed, isTrue);

    final sessions = tester
        .widgetList<ElixSidebarNavTile>(find.byType(ElixSidebarNavTile))
        .firstWhere((tile) => tile.label == 'Sessions');
    expect(sessions.isActive, isTrue);
    expect(sessions.isCollapsed, isTrue);
  });

  test('floating pane geometry is shared and uses the 22px surface radius', () {
    expect(ElixSidebarMetrics.paneRadius, AppSpacing.practiceSurfaceRadius);
    expect(ElixSidebarMetrics.paneRadius, 22);
    expect(ElixSidebarMetrics.paneInset.left, greaterThan(0));
    expect(ElixSidebarMetrics.paneInset.top, greaterThan(0));
    expect(ElixSidebarMetrics.paneInset.bottom, greaterThan(0));
    expect(ElixSidebarMetrics.paneInset.right, greaterThan(0));
    expect(
      ElixSidebarMetrics.navGroupLabelLeft,
      ElixSidebarMetrics.navOuterPadding +
          ElixSidebarMetrics.navInnerPadding +
          ElixSidebarMetrics.navIndicatorSlot +
          ElixSidebarMetrics.navIconSlot +
          ElixSidebarMetrics.navIconLabelGap,
    );
  });
}

void _noop() {}
