import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_controller.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_screen.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_summary.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _teacherId = 'teacher';
final _now = DateTime.utc(2026, 8, 19, 10);

ElixrGroup _group() => ElixrGroup(
  id: 'group-1',
  teacherId: _teacherId,
  name: 'Group 1',
  status: ElixrGroupStatus.active,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

GroupMembership _membership() => GroupMembership(
  id: GroupMembership.documentId(groupId: 'group-1', traineeId: 'student'),
  groupId: 'group-1',
  teacherId: _teacherId,
  traineeId: 'student',
  traineeDisplayName: 'Ada Lovelace',
  teacherDisplayName: 'Teacher',
  status: GroupMembershipStatus.approved,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late InMemoryTeacherProgressRepository progress;
  late TeacherAnalyticsController controller;

  setUp(() {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    progress = InMemoryTeacherProgressRepository();
    groups.seedGroup(_group());
    groups.seedMembership(_membership());
    progress.sessions['student'] = [
      const PublicProfileSession(
        sessionId: 'session-1',
        userId: 'student',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: RubricAssessment(
          technique: 2,
          stability: 2,
          completion: 2,
          propPositioning: 2,
        ),
        assessmentVersion: 2,
        durationSeconds: 60,
        propType: TrainingProp.bottle,
        createdAt: '2026-08-19T09:00:00.000Z',
      ),
    ];
    controller = TeacherAnalyticsController(
      groupRepository: groups,
      assignmentRepository: assignments,
      progressRepository: progress,
      teacherId: _teacherId,
      nowUtc: () => _now,
    );
  });

  tearDown(() {
    controller.dispose();
    groups.dispose();
    assignments.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.start();
    await controller.setCustomRange(
      startDate: DateTime(2026, 8, 19),
      endDate: DateTime(2026, 8, 19),
    );
    await tester.pumpWidget(
      FluentApp(
        theme: FluentThemeData(),
        home: TeacherAnalyticsScreen(controller: controller),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a one-day chart without layout exceptions', (
    tester,
  ) async {
    await pumpScreen(tester, const Size(1280, 900));

    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Average class score'), findsOneWidget);
    expect(find.text('Most practiced'), findsOneWidget);
    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(
      tester.getRect(find.text('Not enough data yet')).height,
      lessThan(40),
    );
    expect(
      tester.getRect(find.byKey(const Key('teacher_analytics_refresh'))).right,
      greaterThan(1200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses simple words when no scored practice is available', (
    tester,
  ) async {
    progress.sessions['student'] = const [];

    await pumpScreen(tester, const Size(1280, 900));

    expect(find.text('Score progress over time'), findsOneWidget);
    expect(
      find.text('No practice sessions with scores in this time range yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('Assessment V2'), findsNothing);
    expect(find.textContaining('rubric'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wraps filters, metrics, and comparison content at narrow width',
    (tester) async {
      await pumpScreen(tester, const Size(640, 900));

      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Class comparison'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard summary shows concise charts from its snapshot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.start();
    await tester.pumpWidget(
      FluentApp(
        theme: FluentThemeData(),
        home: SingleChildScrollView(
          child: SizedBox(
            width: 1000,
            child: TeacherAnalyticsSummary(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Score progress'), findsOneWidget);
    expect(find.text('Practice by classroom'), findsOneWidget);
    expect(find.text('Average practice score over time.'), findsOneWidget);
    expect(find.text('Practice sessions recorded this week.'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byKey(const Key('teacher_analytics_refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_analytics_view_analytics')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard summary uses friendly empty states without overflow', (
    tester,
  ) async {
    progress.sessions['student'] = const [];
    await tester.binding.setSurfaceSize(const Size(620, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.start();
    await tester.pumpWidget(
      FluentApp(
        theme: FluentThemeData(),
        home: SingleChildScrollView(
          child: SizedBox(
            width: 560,
            child: TeacherAnalyticsSummary(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No scored practice yet.'), findsOneWidget);
    expect(find.text('No practice activity yet.'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
