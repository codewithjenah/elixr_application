import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/coaching_notes/coaching_notes_controller.dart';
import 'package:elixr_teacher/features/coaching_notes/coaching_notes_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryCoachingNoteRepository repository;
  late TeacherCoachingNotesController controller;

  setUp(() {
    repository = InMemoryCoachingNoteRepository()
      ..approvedPairs.add('teacher_trainee');
    controller = TeacherCoachingNotesController(
      repository: repository,
      teacherId: 'teacher',
      traineeId: 'trainee',
    );
  });
  tearDown(() => controller.dispose());

  testWidgets('approved section and composer render at a narrow phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await controller.start();
    await tester.pumpWidget(_subject(controller));

    expect(find.text('Coaching Notes'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add note'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Add note'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing notes expose edit and delete actions', (tester) async {
    repository.notes.add(_note());
    await controller.start();
    await tester.pumpWidget(_subject(controller));

    expect(find.text('Keep the bottle upright.'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relationship-required state does not show Add note', (
    tester,
  ) async {
    controller.pause();
    await tester.pumpWidget(_subject(controller));

    expect(find.text('Coaching Notes'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add note'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _subject(TeacherCoachingNotesController controller) => MaterialApp(
  theme: buildTeacherTheme(),
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: CoachingNotesSection(controller: controller),
      ),
    ),
  ),
);

CoachingNote _note() => CoachingNote(
  id: 'note',
  teacherId: 'teacher',
  traineeId: 'trainee',
  teacherDisplayName: 'Teacher',
  body: 'Keep the bottle upright.',
  movementName: 'Hand Stall',
  createdAt: DateTime.utc(2026, 8, 14),
  updatedAt: DateTime.utc(2026, 8, 14),
);
