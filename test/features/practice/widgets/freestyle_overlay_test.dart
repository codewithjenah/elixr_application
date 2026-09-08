import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/recognition_event.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_session_controller.dart';
import 'package:elixr_application/features/practice/widgets/freestyle_overlay.dart';
import 'package:elixr_application/features/practice/widgets/freestyle_summary_sheet.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('overlay shows confirmed labels without setlist chrome', (
    tester,
  ) async {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
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
    expect(find.text('NORMAL GRIP'), findsOneWidget);
    expect(find.text('PERFECT'), findsOneWidget);
    expect(find.text('1x COMBO'), findsOneWidget);
    expect(find.text('Bottle detected'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
  });

  testWidgets('summary lists generic advanced technique without names', (
    tester,
  ) async {
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
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.text('Freestyle Complete'), findsOneWidget);
    expect(find.text('Advanced technique'), findsOneWidget);
    expect(find.text('Elbow Stall'), findsNothing);
    expect(find.text('Forearm Stall'), findsNothing);
  });
}
