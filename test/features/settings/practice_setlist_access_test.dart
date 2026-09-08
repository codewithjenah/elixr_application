import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_access.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/settings/widgets/practice_setlist_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const handBottle = PracticeVariant(
    movementName: 'Hand Stall',
    trainingProp: TrainingProp.bottle,
  );

  test('personalReady is selectable for the runnable set', () {
    final state = practiceSetlistSelectionState(
      evaluatePersonal(
        variant: handBottle,
        currentLevel: 5,
        tutorialCompleted: true,
      ),
    );
    expect(state, PracticeSetlistSelectionState.selectable);
    expect(practiceSetlistStatusLabel(state, requiredLevel: 5), isNull);
  });

  test('personalLearn shows Learn first and is not selectable', () {
    final state = practiceSetlistSelectionState(
      evaluatePersonal(
        variant: handBottle,
        currentLevel: 5,
        tutorialCompleted: false,
      ),
    );
    expect(state, PracticeSetlistSelectionState.learnFirst);
    expect(practiceSetlistCanAdd(state), isFalse);
    expect(
      practiceSetlistStatusLabel(state, requiredLevel: 5),
      'Learn first',
    );
  });

  test('personalLocked shows required level and is not selectable', () {
    final state = practiceSetlistSelectionState(
      evaluatePersonal(
        variant: handBottle,
        currentLevel: 1,
        tutorialCompleted: true,
      ),
    );
    expect(state, PracticeSetlistSelectionState.locked);
    expect(practiceSetlistCanAdd(state), isFalse);
    expect(
      practiceSetlistStatusLabel(state, requiredLevel: 5),
      'Locked · Level 5',
    );
  });

  test('selected non-ready variants can still be removed', () {
    expect(
      practiceSetlistCanRemove(
        PracticeSetlistSelectionState.learnFirst,
        selected: true,
      ),
      isTrue,
    );
    expect(
      practiceSetlistCanRemove(
        PracticeSetlistSelectionState.locked,
        selected: true,
      ),
      isTrue,
    );
    expect(
      practiceSetlistCanRemove(
        PracticeSetlistSelectionState.locked,
        selected: false,
      ),
      isFalse,
    );
  });
}
