import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_sidebar.dart';
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
    await tester.binding.setSurfaceSize(const Size(1280, 900));
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
  });
}

void _noop() {}
