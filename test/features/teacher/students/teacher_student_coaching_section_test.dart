import 'package:elixr_application/features/teacher/students/teacher_student_coaching_section.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_detail_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late FakeTeacherLinksRepository links;
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late InMemoryCoachingNoteRepository coaching;
  late TeacherStudentDetailController controller;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    links = FakeTeacherLinksRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    coaching = InMemoryCoachingNoteRepository()
      ..approvedClassroom.add('group-1::teacher::trainee')
      ..approvedClassroom.add('group-2::teacher::trainee');
    controller = TeacherStudentDetailController(
      groupRepository: groups,
      relationshipRepository: links,
      progressRepository: progress,
      publicProfileRepository: profiles,
      teacherId: 'teacher',
      traineeId: 'trainee',
    );
  });

  tearDown(() {
    controller.dispose();
    groups.dispose();
  });

  void seedAuthorized({bool twoGroups = false}) {
    final first = membership(
      groupId: 'group-1',
      teacherId: 'teacher',
      traineeId: 'trainee',
    );
    controller
      ..approvedMemberships = [first]
      ..classroomMemberships = [first]
      ..selectedGroupId = 'group-1'
      ..state = TeacherStudentDetailState.waitingForAccess;
    if (twoGroups) {
      final second = membership(
        groupId: 'group-2',
        teacherId: 'teacher',
        traineeId: 'trainee',
      );
      controller
        ..approvedMemberships = [first, second]
        ..classroomMemberships = [first, second];
    }
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<CoachingNoteRepository>.value(
        value: coaching,
        child: FluentApp(
          home: TeacherStudentCoachingSection(
            controller: controller,
            teacherDisplayName: 'Grace Hopper',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('authorized group coaching shows add note and selected group', (
    tester,
  ) async {
    seedAuthorized();
    await coaching.createNote(
      teacherId: 'teacher',
      traineeId: 'trainee',
      body: 'Keep the bottle high.',
      groupId: 'group-1',
    );
    await pumpSection(tester);

    expect(find.text('Add note'), findsOneWidget);
    expect(find.textContaining('Classroom group: group-1'), findsOneWidget);
    expect(find.text('Keep the bottle high.'), findsOneWidget);
  });

  testWidgets('changing selected group reloads that group coaching notes', (
    tester,
  ) async {
    seedAuthorized(twoGroups: true);
    await coaching.createNote(
      teacherId: 'teacher',
      traineeId: 'trainee',
      body: 'Group one note',
      groupId: 'group-1',
    );
    await coaching.createNote(
      teacherId: 'teacher',
      traineeId: 'trainee',
      body: 'Group two note',
      groupId: 'group-2',
    );
    await pumpSection(tester);
    expect(find.text('Group one note'), findsOneWidget);
    expect(find.text('Group two note'), findsNothing);
    expect(find.byType(ComboBox<String>), findsOneWidget);

    controller.setSelectedGroupId('group-2');
    await tester.pump();

    expect(find.textContaining('Classroom group: group-2'), findsOneWidget);
    expect(find.text('Group two note'), findsOneWidget);
    expect(find.text('Group one note'), findsNothing);
    expect(find.text('Add note'), findsOneWidget);
  });
}
