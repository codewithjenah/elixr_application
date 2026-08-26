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
      expect(labels.contains('Assigned Movements'), isTrue);
      expect(labels.contains('Movements'), isTrue);

      final teacherAccessIndex = labels.indexOf('Teacher Access');
      expect(teacherAccessIndex, greaterThan(0));
      expect(labels[teacherAccessIndex - 1], 'Dashboard');
      final teacherAccess = elixSidebarItems[teacherAccessIndex];
      expect(teacherAccess.route, '/teacher-access');

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
