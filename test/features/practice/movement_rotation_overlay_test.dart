import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/features/practice/just_dance/playground_session_controller.dart';
import 'package:elixr_application/features/practice/widgets/movement_rotation_overlay.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _movements = [
  Movement(
    name: 'First',
    difficulty: 'Easy',
    description: '',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Second',
    difficulty: 'Easy',
    description: '',
    requiresHandsDetection: true,
    enabled: true,
  ),
];

PlaygroundSessionController _controller() => PlaygroundSessionController(
  movements: _movements,
  assessmentDuration: const Duration(seconds: 20),
  getReadyDuration: const Duration(milliseconds: 1),
  tick: const Duration(milliseconds: 1),
);

Future<void> _pumpHud(
  WidgetTester tester,
  PlaygroundSessionController controller, {
  Size size = const Size(1200, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(
        content: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              children: [
                MovementRotationOverlay(
                  controller: controller,
                  onRestart: () {},
                  onEditSetlist: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('idle Playground does not show the active routine HUD', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pumpHud(tester, controller);
    expect(find.text('PLAYGROUND'), findsNothing);
    expect(find.text('Routine complete'), findsNothing);
  });

  testWidgets(
    'preparing and Get Ready expose movement guidance without success',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.start();
      await _pumpHud(tester, controller);
      expect(find.text('Preparing movement'), findsOneWidget);
      expect(find.text('Success'), findsNothing);
      controller.markMovementPrepared(controller.generation);
      await tester.pump();
      expect(find.text('Get Ready'), findsOneWidget);
      expect(find.text('First'), findsWidgets);
      controller.pause();
    },
  );

  testWidgets(
    'assessing shows current and next movement, progress, and pause resume',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final generation = controller.start()!;
      controller.markMovementPrepared(generation);
      await tester.pump(const Duration(milliseconds: 2));
      controller.markAssessing(generation);
      await _pumpHud(tester, controller);
      expect(find.text('Perform'), findsOneWidget);
      expect(find.textContaining('Up next · Second'), findsOneWidget);
      controller.pause();
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
    },
  );

  testWidgets(
    'success, missed, and completion show factual result presentation',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final first = controller.start()!;
      controller.markMovementPrepared(first);
      await tester.pump(const Duration(milliseconds: 2));
      controller.markAssessing(first);
      controller.markSuccessful(first);
      await _pumpHud(tester, controller);
      expect(find.text('Success'), findsOneWidget);
      final second = controller.beginNextMovement()!;
      controller.markMovementPrepared(second);
      await tester.pump(const Duration(milliseconds: 2));
      controller.markAssessing(second);
      controller.markMissed(second);
      controller.beginNextMovement();
      await tester.pump();
      expect(find.text('Routine complete'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('50% completed successfully'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
    },
  );

  testWidgets('wide and narrow HUD layouts do not overflow', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.start();
    await _pumpHud(tester, controller);
    expect(tester.takeException(), isNull);
    await _pumpHud(tester, controller, size: const Size(520, 400));
    expect(tester.takeException(), isNull);
  });
}
