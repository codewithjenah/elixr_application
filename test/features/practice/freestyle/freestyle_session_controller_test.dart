import 'package:elixr_application/data/models/recognition_event.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
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
  int? targetGeneration,
  String? customMovementId,
  String? revisionId,
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
    targetGeneration: targetGeneration,
    customMovementId: customMovementId,
    revisionId: revisionId,
  );
}

MovementTemplate _template() => MovementTemplate.tryFrom({
  'schema_version': 1,
  'capture_version': 1,
  'duration_ms': 900,
  'reference_count': 2,
  'required_modalities': ['prop_translation'],
  'normalization_metadata': <String, dynamic>{},
  'feature_capabilities': {
    'pose': false,
    'hands': false,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': false,
  },
  'canonical_sequence': [
    for (var index = 0; index < 32; index++) {'timestamp_ms': index * 30},
  ],
  'variability_metadata': <String, dynamic>{},
  'prop_events': <Map<String, dynamic>>[],
})!;

CustomMovement _custom({
  String id = 'custom-1',
  String name = 'Normal Grip',
  CustomMovementStatus status = CustomMovementStatus.active,
  TrainingProp prop = TrainingProp.bottle,
  String revisionId = 'rev-1',
  String difficulty = 'Easy',
}) => CustomMovement(
  id: id,
  ownerUid: 'owner',
  ownerRole: CustomMovementOwnerRole.trainee,
  name: name,
  description: '',
  difficulty: difficulty,
  propType: prop,
  status: status,
  activeRevisionId: revisionId,
);

CustomMovementRevision _revision({
  String id = 'rev-1',
  String movementId = 'custom-1',
  String ownerUid = 'owner',
  MovementTemplate? template,
}) => CustomMovementRevision(
  id: id,
  movementId: movementId,
  ownerUid: ownerUid,
  ownerRole: CustomMovementOwnerRole.trainee,
  template: template ?? _template(),
);

void main() {
  test('difficulty weights progress and use available tiers', () {
    expect(
      endlessDifficultyWeights(0)['Easy'],
      greaterThan(endlessDifficultyWeights(0)['Hard']!),
    );
    expect(
      endlessDifficultyWeights(7)['Medium'],
      greaterThan(endlessDifficultyWeights(7)['Easy']!),
    );
    expect(
      endlessDifficultyWeights(15)['Hard'],
      greaterThan(endlessDifficultyWeights(15)['Easy']!),
    );
    const hardOnly = [
      EndlessTarget(
        movement: 'Hard Move',
        prop: TrainingProp.bottle,
        difficulty: 'Hard',
      ),
    ];
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    controller.start(pool: hardOnly);
    expect(controller.currentTarget?.difficulty, 'Hard');
    expect(controller.upcomingTargets, hasLength(2));
  });
  test('custom target timer allows the learned movement to finish', () {
    final template = MovementTemplate.tryFrom({
      ..._template().toMap(),
      'duration_ms': 15000,
    })!;
    final target = EndlessTarget(
      movement: 'Long toss',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
      kind: EndlessTargetKind.customMovement,
      template: template,
    );
    expect(target.seconds, 20);
    expect(
      EndlessTarget(
        movement: 'Normal Grip',
        prop: TrainingProp.bottle,
        difficulty: 'Easy',
      ).seconds,
      8,
    );
  });

  test('custom pool requires active owned matching revision and prop', () {
    final pool = eligibleCustomEndlessTargets(
      movements: [
        _custom(),
        _custom(id: 'archived', status: CustomMovementStatus.archived),
        _custom(id: 'wrong-prop', prop: TrainingProp.shaker),
        _custom(id: 'missing', revisionId: 'missing-revision'),
        _custom(id: 'invalid', revisionId: 'invalid-revision'),
        _custom(id: 'too-long', revisionId: 'long-revision'),
      ],
      revisions: [
        _revision(),
        _revision(id: 'foreign', movementId: 'missing', ownerUid: 'other'),
        _revision(
          id: 'invalid-revision',
          movementId: 'invalid',
          template: MovementTemplate.tryFrom({
            ..._template().toMap(),
            'canonical_sequence': [
              {'timestamp_ms': 0},
              {'timestamp_ms': 900},
            ],
          })!,
        ),
        _revision(
          id: 'long-revision',
          movementId: 'too-long',
          template: MovementTemplate.tryFrom({
            ..._template().toMap(),
            'duration_ms': 30000,
          })!,
        ),
      ],
      ownerUid: 'owner',
      selectedProp: TrainingProp.bottle,
    );
    expect(pool, hasLength(1));
    expect(pool.single.identity, 'custom:custom-1:rev-1');
    expect(pool.single.template, isNotNull);
  });

  testWidgets('same-name custom success requires stable IDs and scores once', (
    tester,
  ) async {
    final official = const EndlessTarget(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
    );
    final custom = EndlessTarget(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
      kind: EndlessTargetKind.customMovement,
      customMovementId: 'custom-1',
      revisionId: 'rev-1',
      template: _template(),
    );
    expect(official.identity, isNot(custom.identity));
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final generation = controller.start(pool: [custom])!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.confirmTarget(generation, 1);
    expect(
      controller.applyEvent(generation, _event(targetGeneration: 1)),
      isFalse,
    );
    final success = _event(
      eventId: 'custom-ok',
      targetGeneration: 1,
      customMovementId: 'custom-1',
      revisionId: 'rev-1',
    );
    expect(controller.applyEvent(generation, success), isTrue);
    expect(controller.applyEvent(generation, success), isFalse);
    expect(controller.stats.runScore, 3);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      controller.applyEvent(
        generation,
        _event(
          eventId: 'late',
          targetGeneration: 1,
          customMovementId: 'custom-1',
          revisionId: 'rev-1',
        ),
      ),
      isFalse,
    );
  });

  testWidgets('unavailable custom target is excluded and run continues', (
    tester,
  ) async {
    final custom = EndlessTarget(
      movement: 'My Move',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
      kind: EndlessTargetKind.customMovement,
      customMovementId: 'custom-1',
      revisionId: 'rev-1',
      template: _template(),
    );
    const official = EndlessTarget(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
    );
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final generation = controller.start(pool: [custom, official])!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    expect(controller.currentTarget?.identity, custom.identity);
    expect(controller.excludeCurrentTarget(generation, 1), isTrue);
    expect(controller.currentTarget?.identity, official.identity);
    expect(controller.targetGeneration, 2);
    expect(controller.stats.missed, 0);
    expect(controller.confirmTarget(generation, 2), isTrue);
    expect(
      controller.applyEvent(
        generation,
        _event(
          eventId: 'stale-custom',
          movement: 'My Move',
          targetGeneration: 1,
          customMovementId: 'custom-1',
          revisionId: 'rev-1',
        ),
      ),
      isFalse,
    );
    controller.beginEnding(generation);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('single custom target repeats after timeout without deadlock', (
    tester,
  ) async {
    final custom = EndlessTarget(
      movement: 'My Move',
      prop: TrainingProp.bottle,
      difficulty: 'Hard',
      kind: EndlessTargetKind.customMovement,
      customMovementId: 'custom-1',
      revisionId: 'rev-1',
      template: _template(),
    );
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final generation = controller.start(pool: [custom])!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    expect(controller.upcomingTargets, hasLength(2));
    controller.confirmTarget(generation, 1);
    await tester.pump(const Duration(seconds: 12));
    expect(controller.stats.missed, 1);
    expect(controller.currentTarget?.identity, custom.identity);
    expect(controller.targetGeneration, 2);
  });
  const endlessPool = [
    EndlessTarget(
      movement: 'Normal Grip',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
    ),
    EndlessTarget(
      movement: 'Hand Stall',
      prop: TrainingProp.bottle,
      difficulty: 'Medium',
    ),
    EndlessTarget(
      movement: 'Reverse Grip',
      prop: TrainingProp.bottle,
      difficulty: 'Easy',
    ),
  ];

  test('Endless pool uses only ready single-prop variants', () {
    final ready = [
      (movement: 'Normal Grip', prop: TrainingProp.bottle),
      (movement: 'Hand Stall', prop: TrainingProp.shaker),
      (movement: 'Double Hand Stall', prop: TrainingProp.bottle),
      (movement: 'Bottle in a tin', prop: TrainingProp.bottleAndShaker),
    ];
    final bottle = endlessPoolFromReady(ready, TrainingProp.bottle);
    expect(
      bottle.map((target) => target.movement),
      containsAll(['Normal Grip', 'Toss & Catch']),
    );
    expect(
      bottle.map((target) => target.movement),
      isNot(contains('Double Hand Stall')),
    );
    expect(
      bottle.map((target) => target.movement),
      isNot(contains('Hand Stall')),
    );
    final shaker = endlessPoolFromReady(ready, TrainingProp.shaker);
    expect(
      shaker.map((target) => target.movement),
      containsAll(['Hand Stall', 'Toss & Catch']),
    );
    expect(
      shaker.every((target) => target.prop == TrainingProp.shaker),
      isTrue,
    );
  });

  testWidgets(
    'Endless target accepts one matching event, scores and advances',
    (tester) async {
      final controller = FreestyleSessionController(randomIndex: (_) => 0);
      addTearDown(controller.dispose);
      final generation = controller.start(pool: endlessPool)!;
      controller.markPrepared(generation);
      controller.markActive(generation);
      final first = controller.currentTarget!;
      expect(controller.upcomingTargets, hasLength(2));
      expect(controller.confirmTarget(generation, 1), isTrue);
      expect(
        controller.applyEvent(
          generation,
          _event(
            eventId: 'wrong',
            movement: 'Locked Move',
            targetGeneration: 1,
          ),
        ),
        isFalse,
      );
      expect(
        controller.applyEvent(
          generation,
          _event(
            eventId: 'success',
            movement: first.movement,
            displayLabel: first.movement,
            targetGeneration: 1,
          ),
        ),
        isTrue,
      );
      expect(
        controller.applyEvent(
          generation,
          _event(
            eventId: 'duplicate',
            movement: first.movement,
            targetGeneration: 1,
          ),
        ),
        isFalse,
      );
      expect(controller.stats.runScore, 3);
      expect(controller.stats.combo, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.targetGeneration, 2);
      expect(controller.currentTarget!.movement, isNot(first.movement));
      expect(
        controller.applyEvent(
          generation,
          _event(
            eventId: 'late',
            movement: first.movement,
            targetGeneration: 1,
          ),
        ),
        isFalse,
      );
      expect(controller.stats.movementsRecognized, 1);
    },
  );

  testWidgets('Endless timeout misses, resets combo, and pause freezes timer', (
    tester,
  ) async {
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final generation = controller.start(pool: endlessPool)!;
    controller.markPrepared(generation);
    controller.markActive(generation);
    controller.confirmTarget(generation, 1);
    final firstSeconds = controller.remainingSeconds;
    controller.pause(generation);
    await tester.pump(const Duration(seconds: 20));
    expect(controller.remainingSeconds, firstSeconds);
    controller.resume(generation);
    await tester.pump(Duration(seconds: firstSeconds));
    expect(controller.stats.missed, 1);
    expect(controller.targetGeneration, 2);
    expect(controller.stats.combo, 0);
    expect(controller.stats.runScore, 0);
    expect(controller.targetReady, isFalse);
  });

  testWidgets(
    'Endless Nice and Great score one and two without a combo multiplier',
    (tester) async {
      final controller = FreestyleSessionController(randomIndex: (_) => 0);
      addTearDown(controller.dispose);
      final generation = controller.start(pool: endlessPool)!;
      controller.markPrepared(generation);
      controller.markActive(generation);
      for (final quality in [
        RecognitionQuality.nice,
        RecognitionQuality.great,
      ]) {
        final target = controller.currentTarget!;
        final targetGeneration = controller.targetGeneration;
        controller.confirmTarget(generation, targetGeneration);
        expect(
          controller.applyEvent(
            generation,
            _event(
              eventId: 'score-$targetGeneration',
              movement: target.movement,
              displayLabel: target.movement,
              quality: quality,
              targetGeneration: targetGeneration,
            ),
          ),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(controller.stats.runScore, 3);
      expect(controller.stats.combo, 2);
      expect(controller.stats.nice, 1);
      expect(controller.stats.great, 1);
      controller.confirmTarget(generation, controller.targetGeneration);
      await tester.pump(Duration(seconds: controller.remainingSeconds));
      expect(controller.stats.missed, 1);
      expect(controller.stats.combo, 0);
      expect(controller.stats.runScore, 3);
    },
  );

  test('Endless fresh run invalidates old generation', () {
    final controller = FreestyleSessionController(randomIndex: (_) => 0);
    addTearDown(controller.dispose);
    final old = controller.start(pool: endlessPool)!;
    controller.cancelToIdle();
    final fresh = controller.start(pool: endlessPool)!;
    controller.markPrepared(fresh);
    controller.markActive(fresh);
    controller.confirmTarget(fresh, 1);
    expect(controller.applyEvent(old, _event(targetGeneration: 1)), isFalse);
    expect(controller.stats.runScore, 0);
  });

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
    expect(
      controller.applyEvent(generation, _event(eventId: 'during-activate')),
      isTrue,
    );
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
