import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/learning/movement_lesson.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lesson action buttons fit without horizontal overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: const MovementLessonScreen(
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
      FluentApp(
        theme: AppTheme.dark,
        home: const MovementLessonScreen(
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
