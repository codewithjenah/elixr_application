import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old records without prop_type default to Bottle', () {
    final session = Session.fromMap({
      'id': 'session-old',
      'user_id': 'user-1',
      'movement_name': 'Hand Stall',
      'difficulty': 'Medium',
      'score': 80,
      'duration_seconds': 30,
      'created_at': null,
    });

    expect(session.propType, TrainingProp.bottle);
    expect(session.toMap()['prop_type'], 'bottle');
  });

  test('shaker sessions serialize and deserialize prop_type', () {
    const session = Session(
      id: 'session-shaker',
      userId: 'user-1',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      score: 90,
      durationSeconds: 45,
      propType: TrainingProp.shaker,
    );

    expect(session.toMap()['prop_type'], 'shaker');
    expect(Session.fromMap(session.toMap()).propType, TrainingProp.shaker);
  });
}
