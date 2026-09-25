import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('write validation reports the two reference minimum', () {
    const incompleteTemplate = MovementTemplate(
      schemaVersion: 1,
      captureVersion: 1,
      durationMs: 1000,
      referenceCount: 1,
      requiredModalities: ['hands', 'prop_translation'],
      normalizationMetadata: {
        'anchor': 'shoulder_midpoint',
        'scale': 'shoulder_width',
        'mirrored': false,
      },
      featureCapabilities: {
        'pose': false,
        'hands': true,
        'prop_translation': true,
        'release_catch': false,
        'prop_rotation': false,
      },
      canonicalSequence: [
        {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
        {'timestamp_ms': 1000, 'pose': <String, dynamic>{}},
      ],
      variabilityMetadata: {'duration_std_ms': 0.0},
    );

    expect(
      () => validateCustomMovementWrite(
        ownerUid: 'trainee-1',
        template: incompleteTemplate,
        name: 'Bottle toss',
        description: 'Toss and catch the bottle with one hand.',
        difficulty: 'Easy',
        propType: TrainingProp.bottle,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'At least two valid reference demonstrations are required.',
        ),
      ),
    );
  });
}
