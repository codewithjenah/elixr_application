import 'package:elixr_application/core/widgets/elix_sidebar.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
