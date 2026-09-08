import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/learning/movement_lesson.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ReadyTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

Widget _wrapLesson(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TraineeProgressionService>(
        create: (_) => TraineeProgressionService.ready(totalXp: 20 * 250),
      ),
      ChangeNotifierProvider<TutorialProgressService>(
        create: (_) => _ReadyTutorials(),
      ),
    ],
    child: FluentApp(theme: AppTheme.dark, home: child),
  );
}

void main() {
  testWidgets('lesson action buttons fit without horizontal overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);

    await tester.pumpWidget(
      _wrapLesson(
        const MovementLessonScreen(
          movement: 'Claw Grip',
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Back to tutorials'), findsOneWidget);
    expect(find.text('Start guided practice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('difficulty pill stays with the lesson title', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);

    await tester.pumpWidget(
      _wrapLesson(
        const MovementLessonScreen(
          movement: 'Claw Grip',
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text('Claw Grip')).dy;
    final pillTop = tester.getTopLeft(find.text('Easy')).dy;
    expect(pillTop, greaterThan(titleTop));
  });
}
