import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/recognition_event.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_session_controller.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_models.dart';
import 'package:elixr_application/features/practice/widgets/freestyle_overlay.dart';
import 'package:elixr_application/features/practice/widgets/freestyle_summary_sheet.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overlay shows confirmed labels without setlist chrome', (
    tester,
  ) async {
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final generation = controller.start(
      pool: const [
        EndlessTarget(
          movement: 'Normal Grip',
          prop: TrainingProp.bottle,
          difficulty: 'Easy',
        ),
        EndlessTarget(
          movement: 'Toss & Catch',
          prop: TrainingProp.bottle,
          difficulty: 'Medium',
        ),
      ],
    )!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.confirmTarget(generation, controller.targetGeneration);
    controller.applyLiveState(
      generation: generation,
      detectedProp: TrainingProp.bottle,
    );
    controller.applyEvent(
      generation,
      const RecognitionEvent(
        sessionId: 's',
        eventId: 'e1',
        kind: RecognitionKind.movement,
        displayLabel: 'Normal Grip',
        identityRevealed: true,
        quality: RecognitionQuality.perfect,
        movement: 'Normal Grip',
        propType: TrainingProp.bottle,
        targetGeneration: 1,
      ),
    );

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SizedBox(
            width: 900,
            height: 600,
            child: FreestyleOverlay(
              controller: controller,
              onPause: () {},
              onResume: () {},
              onQuit: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Build Your Set'), findsNothing);
    expect(find.text('Normal Grip'), findsWidgets);
    expect(find.text('PERFECT'), findsOneWidget);
    expect(find.textContaining('COMBO 1'), findsOneWidget);
    expect(find.text('Prop detected'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('End Session'), findsOneWidget);
    controller.cancelToIdle();
  });

  testWidgets('summary lists generic advanced technique without names', (
    tester,
  ) async {
    bool? playAgain;
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(
      generation,
      const RecognitionEvent(
        sessionId: 's',
        eventId: 'adv',
        kind: RecognitionKind.advancedTechnique,
        displayLabel: 'Advanced technique detected',
        identityRevealed: false,
        quality: RecognitionQuality.great,
      ),
    );

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Builder(
            builder: (context) {
              return Button(
                child: const Text('Show summary'),
                onPressed: () {
                  FreestyleSummarySheet.show(
                    context,
                    stats: controller.stats,
                    durationSeconds: 12,
                    onDone: () {},
                  ).then((value) => playAgain = value);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.text('Endless Run Summary'), findsOneWidget);
    expect(find.text('Run score'), findsOneWidget);
    expect(find.text('Elbow Stall'), findsNothing);
    expect(find.text('Forearm Stall'), findsNothing);
    await tester.tap(find.text('Play Again'));
    await tester.pumpAndSettle();
    expect(playAgain, isTrue);
  });
}
