import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/learning/movement_lesson.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assigned lesson paths keep assignmentId out of a return URL', () {
    final lesson = AppRoutePaths.movementLesson(
      movement: 'Claw Grip',
      difficulty: 'Easy',
      prop: 'bottle',
      assignmentId: 'asg1',
    );
    expect(lesson, contains('/learn/movement/'));
    expect(lesson, contains('assignmentId=asg1'));
    expect(lesson.contains('returnUrl='), isFalse);
    expect(AppRoutePaths.assignedPractice('asg1'), '/assigned-practice/asg1');
    expect(
      AppRoutePaths.assignmentIdFromAssignedPractice('/assigned-practice/asg1'),
      'asg1',
    );
  });

  testWidgets('assignment lesson preserves assignmentId in the lesson UI', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: const MovementLessonScreen(
          movement: 'Claw Grip',
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
          assignmentId: 'asg1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Back to Assigned Movements'), findsOneWidget);
    expect(find.text('Back to tutorials'), findsNothing);
    expect(find.text('Start guided practice'), findsOneWidget);
  });
}
