import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/practice_screen.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeCatalogStep? _nextSummaryStep({
  required int? currentLevel,
  required bool? tutorialCompleted,
  bool assignmentScoped = false,
  bool challengeScoped = false,
}) {
  return nextPracticeSummaryStep(
    movementName: 'Normal Grip',
    prop: TrainingProp.bottle,
    assignmentScoped: assignmentScoped,
    challengeScoped: challengeScoped,
    currentLevel: currentLevel,
    tutorialCompleted: (_) => tutorialCompleted,
  );
}

void main() {
  test('locked immediate successor is not exposed or skipped', () {
    final catalogCandidate = nextEnabledPracticeAfter(
      'Normal Grip',
      TrainingProp.bottle,
    );

    expect(catalogCandidate?.movement.name, "Bartender's Grip");
    expect(_nextSummaryStep(currentLevel: 1, tutorialCompleted: true), isNull);
  });

  test('personally ready immediate successor is exposed', () {
    final next = _nextSummaryStep(currentLevel: 2, tutorialCompleted: true);

    expect(next?.movement.name, "Bartender's Grip");
    expect(next?.prop, TrainingProp.bottle);
  });

  test('tutorial-incomplete immediate successor is not exposed', () {
    expect(_nextSummaryStep(currentLevel: 2, tutorialCompleted: false), isNull);
  });

  test('unresolved progression or tutorial state fails closed', () {
    expect(
      _nextSummaryStep(currentLevel: null, tutorialCompleted: true),
      isNull,
    );
    expect(_nextSummaryStep(currentLevel: 2, tutorialCompleted: null), isNull);
  });

  test('assignment-scoped sessions retain no catalog auto-next', () {
    expect(
      _nextSummaryStep(
        currentLevel: 2,
        tutorialCompleted: true,
        assignmentScoped: true,
      ),
      isNull,
    );
  });

  test('challenge-scoped sessions retain no catalog auto-next', () {
    expect(
      _nextSummaryStep(
        currentLevel: 2,
        tutorialCompleted: true,
        challengeScoped: true,
      ),
      isNull,
    );
  });
}
