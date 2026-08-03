import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/features/practice/just_dance/movement_rotation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _movements = [
  Movement(
    name: 'A',
    difficulty: 'Easy',
    description: '',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'B',
    difficulty: 'Easy',
    description: '',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'C',
    difficulty: 'Easy',
    description: '',
    requiresHandsDetection: true,
    enabled: true,
  ),
];

void main() {
  group('MovementRotationController', () {
    test('advances to the next movement after the interval and loops', () async {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 1,
        tick: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.currentMovement?.name, 'A');
      expect(controller.nextMovement?.name, 'B');
      expect(controller.isRunning, isTrue);

      await Future.delayed(const Duration(milliseconds: 1300));
      expect(controller.currentMovement?.name, 'B');

      await Future.delayed(const Duration(milliseconds: 1300));
      expect(controller.currentMovement?.name, 'C');

      await Future.delayed(const Duration(milliseconds: 1300));
      expect(
        controller.currentMovement?.name,
        'A',
        reason: 'rotation loops back to the start of the setlist',
      );
    });

    test('pause freezes progress and resume continues advancing', () async {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 1,
        tick: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.start();
      await Future.delayed(const Duration(milliseconds: 300));
      controller.pause();
      expect(controller.isRunning, isFalse);
      final progressAtPause = controller.progress;

      await Future.delayed(const Duration(milliseconds: 500));
      expect(controller.progress, progressAtPause);
      expect(controller.currentMovement?.name, 'A');

      controller.resume();
      expect(controller.isRunning, isTrue);
      await Future.delayed(const Duration(milliseconds: 1300));
      expect(controller.currentMovement?.name, 'B');
    });

    test('skipNext / skipPrevious move immediately and wrap around', () {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 25,
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.currentMovement?.name, 'A');

      controller.skipNext();
      expect(controller.currentMovement?.name, 'B');

      controller.skipPrevious();
      expect(controller.currentMovement?.name, 'A');

      controller.skipPrevious();
      expect(
        controller.currentMovement?.name,
        'C',
        reason: 'skipping previous from the first entry wraps to the last',
      );
    });

    test('stop cancels the timer and resets to the first movement', () async {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 1,
        tick: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.start();
      await Future.delayed(const Duration(milliseconds: 1300));
      expect(controller.currentMovement?.name, 'B');

      controller.stop();
      expect(controller.hasTimer, isFalse);
      expect(controller.isRunning, isFalse);
      expect(controller.currentMovement?.name, 'A');
    });

    test('empty setlist has no current movement and start is a no-op', () {
      final controller = MovementRotationController(
        movements: const [],
        intervalSeconds: 25,
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.currentMovement, isNull);
      expect(controller.nextMovement, isNull);
      expect(controller.hasTimer, isFalse);
    });

    test('updateSetlist swaps the list live and restarts from the top', () {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 1,
        tick: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.skipNext();
      expect(controller.currentMovement?.name, 'B');

      const replacement = [
        Movement(
          name: 'D',
          difficulty: 'Hard',
          description: '',
          requiresHandsDetection: true,
          enabled: true,
        ),
      ];
      controller.updateSetlist(replacement, intervalSeconds: 40);
      expect(controller.currentMovement?.name, 'D');
      expect(controller.nextMovement, isNull);
      expect(
        controller.isRunning,
        isTrue,
        reason: 'a live edit must not interrupt an in-progress rotation',
      );
    });

    test('dispose cancels the timer and further calls are safely ignored', () {
      final controller = MovementRotationController(
        movements: _movements,
        intervalSeconds: 1,
        tick: const Duration(milliseconds: 100),
      );
      controller.start();
      controller.dispose();
      expect(controller.hasTimer, isFalse);

      // None of these should throw or notify a disposed ChangeNotifier.
      controller.start();
      controller.pause();
      controller.resume();
      controller.skipNext();
      controller.skipPrevious();
      controller.stop();
    });
  });
}
