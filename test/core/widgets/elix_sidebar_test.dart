import 'package:elixr_application/core/theme/app_theme.dart';
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

  testWidgets('trainee sidebar stays layout-safe through pane transitions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = AuthService(
      repository: _UnusedAuthRepository(),
      awaitInitialAuthState: () async {},
    );
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
                ElixSidebar(
                  currentRoute: '/dashboard',
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

  testWidgets('trainee sidebar docks flush in the application shell', (
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
          home: const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElixSidebar(
                currentRoute: '/dashboard',
                isCollapsed: false,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
              Expanded(child: ColoredBox(color: Color(0xFF050308))),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final paneRect = tester.getRect(find.byType(ElixSidebarPane));
    expect(paneRect.left, 0);
    expect(paneRect.top, 0);
    expect(paneRect.bottom, 760);
    expect(paneRect.width, ElixSidebarMetrics.expandedWidth);

    final paneContainer = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .firstWhere(
          (container) =>
              container.constraints?.maxWidth ==
              ElixSidebarMetrics.expandedWidth,
        );
    final decoration = paneContainer.decoration! as BoxDecoration;
    expect(decoration.borderRadius, ElixSidebarMetrics.paneBorderRadius);
    expect(decoration.border, isNull);
    expect(find.byType(ElixSidebarFacingHighlight), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed trainee sidebar stays docked to the shell', (
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
          home: const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElixSidebar(
                currentRoute: '/dashboard',
                isCollapsed: true,
                onToggleCollapse: _noop,
                onLogout: _noop,
              ),
              Expanded(child: ColoredBox(color: Color(0xFF050308))),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(ElixSidebarMetrics.paneMotion);

    final paneRect = tester.getRect(find.byType(ElixSidebarPane));
    expect(paneRect.left, 0);
    expect(paneRect.top, 0);
    expect(paneRect.bottom, 760);
    expect(paneRect.width, ElixSidebarMetrics.collapsedWidth);
    expect(tester.takeException(), isNull);
  });

  test(
    'docked pane geometry keeps square left corners and compact nav radius',
    () {
      expect(ElixSidebarMetrics.paneRadius, 28);
      expect(ElixSidebarMetrics.paneBorderRadius.topLeft, Radius.zero);
      expect(ElixSidebarMetrics.paneBorderRadius.bottomLeft, Radius.zero);
      expect(
        ElixSidebarMetrics.paneBorderRadius.topRight,
        const Radius.circular(28),
      );
      expect(
        ElixSidebarMetrics.paneBorderRadius.bottomRight,
        const Radius.circular(28),
      );
      expect(ElixSidebarMetrics.paneInset, EdgeInsets.zero);
      expect(ElixSidebarMetrics.navItemRadius, 12);
      expect(ElixSidebarMetrics.identityCardRadius, lessThanOrEqualTo(14));
      expect(
        ElixSidebarMetrics.navGroupLabelLeft,
        ElixSidebarMetrics.navOuterPadding +
            ElixSidebarMetrics.navInnerPadding +
            ElixSidebarMetrics.navIndicatorSlot +
            ElixSidebarMetrics.navIconSlot +
            ElixSidebarMetrics.navIconLabelGap,
      );
    },
  );
}

void _noop() {}
