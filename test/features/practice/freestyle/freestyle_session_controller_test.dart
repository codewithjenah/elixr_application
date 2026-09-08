import 'package:elixr_application/data/models/recognition_event.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_models.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

RecognitionEvent _event({
  String eventId = 'e1',
  RecognitionKind kind = RecognitionKind.movement,
  String displayLabel = 'Normal Grip',
  RecognitionQuality quality = RecognitionQuality.perfect,
  String? movement = 'Normal Grip',
  TrainingProp prop = TrainingProp.bottle,
  bool identityRevealed = true,
}) {
  return RecognitionEvent(
    sessionId: 'session-1',
    eventId: eventId,
    kind: kind,
    displayLabel: displayLabel,
    identityRevealed: identityRevealed,
    quality: quality,
    movement: movement,
    propType: prop,
  );
}

void main() {
  test('start does not require a selected movement set', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start();
    expect(generation, isNotNull);
    expect(controller.phase, FreestyleSessionPhase.preparing);
    expect(controller.stats.movementsRecognized, 0);
  });

  test('one confirmed event increments combo and stats once', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    expect(controller.markPrepared(generation), isTrue);
    expect(controller.markActive(generation), isTrue);

    expect(controller.applyEvent(generation, _event()), isTrue);
    expect(controller.stats.movementsRecognized, 1);
    expect(controller.stats.uniqueUnlockedMovements, 1);
    expect(controller.stats.perfect, 1);
    expect(controller.stats.combo, 1);
    expect(controller.stats.bestCombo, 1);
    expect(controller.liveLabel, 'Normal Grip');

    expect(controller.applyEvent(generation, _event()), isFalse);
    expect(controller.stats.combo, 1);
    expect(controller.stats.movementsRecognized, 1);
  });

  test('leaving and re-entering can generate another event', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(generation, _event(eventId: 'first'));
    controller.applyEvent(generation, _event(eventId: 'second'));
    expect(controller.stats.movementsRecognized, 2);
    expect(controller.stats.combo, 2);
    expect(controller.stats.uniqueUnlockedMovements, 1);
  });

  test('locked identity is stored only as a generic advanced technique', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(
      generation,
      _event(
        kind: RecognitionKind.advancedTechnique,
        displayLabel: 'Advanced technique detected',
        movement: null,
        identityRevealed: false,
        quality: RecognitionQuality.great,
      ),
    );
    expect(controller.stats.advancedTechniques, 1);
    expect(controller.stats.movementsRecognized, 0);
    expect(controller.liveLabel, 'Advanced technique detected');
    expect(controller.stats.feed.single.displayLabel, isNot(contains('Stall')));
    expect(controller.stats.combo, 1);
  });

  test('pause ignores events and resume does not replay them', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    expect(controller.pause(generation), isTrue);
    expect(
      controller.applyEvent(generation, _event(eventId: 'paused')),
      isFalse,
    );
    expect(controller.stats.combo, 0);
    expect(controller.resume(generation), isTrue);
    expect(
      controller.applyEvent(generation, _event(eventId: 'paused')),
      isTrue,
    );
    expect(controller.stats.combo, 1);
  });

  test('failed action resets combo and does not count as a movement', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(generation, _event(eventId: 'ok'));
    controller.applyEvent(
      generation,
      _event(
        eventId: 'drop',
        kind: RecognitionKind.failedAction,
        displayLabel: '',
        movement: null,
        quality: RecognitionQuality.nice,
      ),
    );
    expect(controller.stats.combo, 0);
    expect(controller.stats.bestCombo, 1);
    expect(controller.stats.flips, 0);
    expect(controller.stats.movementsRecognized, 1);
  });

  test('flip and bottle/shaker props accumulate in summary stats', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(generation, _event(eventId: 'grip'));
    controller.applyEvent(
      generation,
      _event(
        eventId: 'flip-b',
        kind: RecognitionKind.flip,
        displayLabel: 'Flip',
        movement: null,
        quality: RecognitionQuality.perfect,
      ),
    );
    controller.applyEvent(
      generation,
      _event(
        eventId: 'shake',
        displayLabel: 'Hand Stall',
        movement: 'Hand Stall',
        prop: TrainingProp.shaker,
        quality: RecognitionQuality.nice,
      ),
    );
    expect(controller.stats.flips, 1);
    expect(controller.stats.nice, 1);
    expect(controller.stats.combo, 3);
    expect(
      controller.stats.props,
      containsAll({TrainingProp.bottle, TrainingProp.shaker}),
    );
  });

  test('stale generation cannot mutate the current session', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final first = controller.start()!;
    controller.cancelToIdle();
    final second = controller.start()!;
    expect(second, isNot(first));
    expect(controller.applyEvent(first, _event()), isFalse);
    expect(controller.stats.movementsRecognized, 0);
  });

  test('searching live state does not keep a previous candidate label', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.applyEvent(generation, _event());
    controller.applyLiveState(
      generation: generation,
      state: RecognitionState.searching,
    );
    expect(controller.liveLabel, isNull);
    expect(controller.liveQuality, isNull);
  });

  test('events arriving while ready during activate are counted once', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    expect(controller.markPrepared(generation), isTrue);
    expect(controller.phase, FreestyleSessionPhase.ready);
    expect(controller.applyEvent(generation, _event(eventId: 'during-activate')), isTrue);
    expect(controller.stats.combo, 1);
    expect(controller.liveLabel, 'Normal Grip');
    expect(
      controller.applyLiveState(
        generation: generation,
        state: RecognitionState.searching,
      ),
      isTrue,
    );
    expect(controller.liveLabel, isNull);
    expect(controller.markActive(generation), isTrue);
    expect(
      controller.applyEvent(generation, _event(eventId: 'during-activate')),
      isFalse,
    );
    expect(controller.stats.combo, 1);
  });

  test('resume after local pause can be rolled back by pausing again', () {
    final controller = FreestyleSessionController();
    addTearDown(controller.dispose);
    final generation = controller.start()!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    expect(controller.pause(generation), isTrue);
    expect(controller.resume(generation), isTrue);
    expect(controller.phase, FreestyleSessionPhase.active);
    expect(controller.pause(generation), isTrue);
    expect(controller.phase, FreestyleSessionPhase.paused);
    expect(
      controller.applyEvent(generation, _event(eventId: 'after-failed-resume')),
      isFalse,
    );
    expect(controller.stats.combo, 0);
  });
}
