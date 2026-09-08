import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/features/practice/just_dance/playground_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _setlist = [
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
];

PlaygroundSessionController _controller({
  Duration assessment = const Duration(milliseconds: 80),
}) => PlaygroundSessionController(
  movements: _setlist,
  assessmentDuration: assessment,
  getReadyDuration: const Duration(milliseconds: 20),
  tick: const Duration(milliseconds: 10),
);

void main() {
  group('PlaygroundSessionController', () {
    test('elapsed assessment time marks a miss, never a success', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final generation = controller.start()!;
      controller.markMovementPrepared(generation);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      controller.markAssessing(generation);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.phase, PlaygroundSessionPhase.missed);
      expect(
        controller.outcomes.single.status,
        PlaygroundMovementStatus.missed,
      );
    });

    test(
      'official success completes and advances to the next selected movement',
      () async {
        final controller = _controller();
        addTearDown(controller.dispose);
        final first = controller.start()!;
        controller.markMovementPrepared(first);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        controller.markAssessing(first);
        expect(controller.markSuccessful(first), isTrue);
        final second = controller.beginNextMovement();
        expect(
          controller.outcomes.single.status,
          PlaygroundMovementStatus.success,
        );
        expect(controller.currentMovement?.name, 'B');
        expect(second, isNotNull);
        expect(controller.phase, PlaygroundSessionPhase.preparingMovement);
      },
    );

    test(
      'stale feedback generation cannot complete the next movement',
      () async {
        final controller = _controller();
        addTearDown(controller.dispose);
        final first = controller.start()!;
        controller.markMovementPrepared(first);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        controller.markAssessing(first);
        controller.markSuccessful(first);
        final second = controller.beginNextMovement()!;
        controller.markMovementPrepared(second);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        controller.markAssessing(second);
        expect(controller.markSuccessful(first), isFalse);
        expect(controller.phase, PlaygroundSessionPhase.assessing);
        expect(controller.outcomes, hasLength(1));
      },
    );

    test('final movement completes instead of looping', () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      var generation = controller.start()!;
      for (var i = 0; i < 2; i++) {
        controller.markMovementPrepared(generation);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        controller.markAssessing(generation);
        controller.markSuccessful(generation);
        final next = controller.beginNextMovement();
        if (i == 0) generation = next!;
        if (i == 1) expect(next, isNull);
      }
      expect(controller.phase, PlaygroundSessionPhase.completed);
      expect(controller.outcomes, hasLength(2));
    });

    test('empty setlist completes safely without a prepare generation', () {
      final controller = PlaygroundSessionController(
        movements: const [],
        assessmentDuration: const Duration(seconds: 1),
      );
      addTearDown(controller.dispose);
      expect(controller.start(), isNull);
      expect(controller.phase, PlaygroundSessionPhase.completed);
      expect(controller.currentMovement, isNull);
    });

    test(
      'pause freezes assessment timeout and manual next uses a miss transition',
      () async {
        final controller = _controller(
          assessment: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);
        final generation = controller.start()!;
        controller.markMovementPrepared(generation);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        controller.markAssessing(generation);
        controller.pause();
        await Future<void>.delayed(const Duration(milliseconds: 130));
        expect(controller.phase, PlaygroundSessionPhase.assessing);
        expect(
          controller.requestNext(),
          isFalse,
          reason: 'paused routines cannot progress invisibly',
        );
        controller.resume();
        expect(controller.requestNext(), isTrue);
        expect(
          controller.outcomes.single.status,
          PlaygroundMovementStatus.missed,
        );
        expect(controller.beginNextMovement(), isNotNull);
      },
    );
  });
}
