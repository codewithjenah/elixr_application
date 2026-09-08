import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hand Stall Bottle and Shaker are distinct', () {
    const bottle = PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.bottle,
    );
    const shaker = PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.shaker,
    );
    expect(bottle, isNot(equals(shaker)));
    expect(bottle.persistenceKey, 'Hand Stall|bottle');
    expect(shaker.persistenceKey, 'Hand Stall|shaker');
  });

  test('round-trips persistence key', () {
    const v = PracticeVariant(
      movementName: 'Bottle in a tin',
      trainingProp: TrainingProp.bottleAndShaker,
    );
    expect(PracticeVariant.tryParsePersistenceKey(v.persistenceKey), v);
  });

  test('rejects malformed keys', () {
    expect(PracticeVariant.tryParsePersistenceKey('Hand Stall'), isNull);
    expect(PracticeVariant.tryParsePersistenceKey('Hand Stall|nope'), isNull);
  });
}
