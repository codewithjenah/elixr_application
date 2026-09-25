import 'package:flutter_test/flutter_test.dart';

import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';

Map<String, dynamic> templateMap() => {
  'schema_version': 1,
  'capture_version': 1,
  'duration_ms': 6000,
  'reference_count': 3,
  'required_modalities': ['pose', 'hands', 'prop_translation'],
  'normalization_metadata': {
    'anchor': 'shoulder_midpoint',
    'scale': 'shoulder_width',
    'mirrored': false,
  },
  'feature_capabilities': {
    'pose': true,
    'hands': true,
    'prop_translation': true,
    'release_catch': true,
    'prop_rotation': false,
  },
  'canonical_sequence': [
    {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
    {'timestamp_ms': 6000, 'pose': <String, dynamic>{}},
  ],
  'variability_metadata': {'duration_std_ms': 100.0},
  'prop_events': <Map<String, dynamic>>[],
};

void main() {
  group('MovementTemplate', () {
    test('accepts the shared versioned data-only envelope', () {
      final template = MovementTemplate.tryFrom(templateMap());

      expect(template, isNotNull);
      expect(template!.isReady, isTrue);
      expect(template.requiresRotation, isFalse);
      expect(template.toMap(), templateMap());
    });

    test('accepts two through ten references and rejects one', () {
      for (final count in [2, 3, 4, 5, 10]) {
        expect(
          MovementTemplate.tryFrom(
            templateMap()..['reference_count'] = count,
          )?.isReady,
          isTrue,
        );
      }
      expect(
        MovementTemplate.tryFrom(templateMap()..['reference_count'] = 1),
        isNull,
      );
      expect(
        MovementTemplate.tryFrom(templateMap()..['reference_count'] = 11),
        isNull,
      );
    });

    test('rejects executable/unknown fields and v1 rotation', () {
      final executable = templateMap()..['python_rule'] = 'eval(user_input)';
      final rotating = templateMap();
      (rotating['feature_capabilities']
              as Map<String, dynamic>)['prop_rotation'] =
          true;

      expect(MovementTemplate.tryFrom(executable), isNull);
      expect(MovementTemplate.tryFrom(rotating), isNull);
    });

    test('accepts v2 rotation trace and rejects invalid combinations', () {
      final rotating = templateMap()
        ..['schema_version'] = 2
        ..['canonical_sequence'] = List.generate(
          32,
          (index) => {
            'timestamp_ms': index * 200,
            'pose': <String, dynamic>{},
            'hands': <String, dynamic>{},
            'prop': {'x': 0.5, 'y': 0.5, 'confidence': 0.9},
            'prop_metadata': <String, dynamic>{},
          },
        )
        ..['rotation_trace'] = {
          'angles_rad': List<double>.generate(32, (i) => i * 0.2),
          'total_signed_rad': 6.2,
          'coverage': 0.95,
          'pair_coverage': 0.9,
        };
      (rotating['feature_capabilities']
              as Map<String, dynamic>)['prop_rotation'] =
          true;
      final parsed = MovementTemplate.tryFrom(rotating);
      expect(parsed, isNotNull);
      expect(parsed!.requiresRotation, isTrue);
      expect(parsed.toMap(), rotating);
      final shortSequence = Map<String, dynamic>.from(rotating)
        ..['canonical_sequence'] = templateMap()['canonical_sequence'];
      expect(MovementTemplate.tryFrom(shortSequence), isNull);

      final missingTrace = templateMap()..['schema_version'] = 2;
      (missingTrace['feature_capabilities']
              as Map<String, dynamic>)['prop_rotation'] =
          true;
      expect(MovementTemplate.tryFrom(missingTrace), isNull);
      final legacyWithTrace = templateMap()..['rotation_trace'] = null;
      expect(MovementTemplate.tryFrom(legacyWithTrace), isNull);
    });

    test('requires the exact capability contract', () {
      final missing = templateMap();
      (missing['feature_capabilities'] as Map<String, dynamic>).remove('hands');

      expect(MovementTemplate.tryFrom(missing), isNull);
    });

    test('derives one-hand and pose-optional readiness from capabilities', () {
      final oneHand = templateMap();
      oneHand['required_modalities'] = ['hands', 'prop_translation'];
      oneHand['feature_capabilities'] = {
        'pose': false,
        'hands': true,
        'prop_translation': true,
        'release_catch': false,
        'prop_rotation': false,
        'left_hand': true,
        'right_hand': false,
      };

      final template = MovementTemplate.tryFrom(oneHand);

      expect(template, isNotNull);
      expect(template!.requiredHandSides, ['left']);
      expect(template.readinessSpec.hands.wireValue, 'one_hand');
      expect(template.readinessSpec.body.wireValue, 'none');
      expect(template.readinessGuidance, contains('left hand'));
      expect(template.readinessGuidance, isNot(contains('upper body')));
    });

    test('legacy version-one hands capability keeps two-hand readiness', () {
      final template = MovementTemplate.tryFrom(templateMap());

      expect(template, isNotNull);
      expect(template!.requiredHandSides, ['left', 'right']);
      expect(template.readinessSpec.hands.wireValue, 'two_hands');
      expect(template.readinessSpec.body.wireValue, 'upper_body');
    });
  });

  group('CustomMovement', () {
    test('parses trainee ownership and immutable active revision identity', () {
      final movement = CustomMovement.tryFromMap({
        'owner_uid': 'trainee-1',
        'owner_role': 'trainee',
        'name': '  My Cascade  ',
        'description': '',
        'difficulty': 'Hard',
        'prop_type': 'shaker',
        'status': 'active',
        'active_revision_id': 'rev-1',
        'schema_version': 1,
      }, id: 'movement-1');

      expect(movement, isNotNull);
      expect(movement!.name, 'My Cascade');
      expect(movement.ownerRole, CustomMovementOwnerRole.trainee);
      expect(movement.isOwnedBy('trainee-1'), isTrue);
    });

    test('rejects dual-prop templates until two synchronized tracks exist', () {
      expect(
        CustomMovement.tryFromMap({
          'owner_uid': 'trainee-1',
          'owner_role': 'trainee',
          'name': 'Dual cascade',
          'description': '',
          'difficulty': 'Hard',
          'prop_type': 'bottle_and_shaker',
          'status': 'active',
          'active_revision_id': 'rev-1',
          'schema_version': 1,
        }, id: 'movement-1'),
        isNull,
      );
    });

    test('revision requires at least two references', () {
      final incomplete = templateMap()..['reference_count'] = 1;

      expect(
        CustomMovementRevision.tryFromMap({
          'movement_id': 'movement-1',
          'owner_uid': 'teacher-1',
          'owner_role': 'teacher',
          'schema_version': 1,
          'template': incomplete,
        }, id: 'rev-1'),
        isNull,
      );
    });
  });

  group('CustomMovementResult', () {
    test('parses bounded personal progress records', () {
      final result = CustomMovementResult.tryFromMap({
        'owner_uid': 'trainee-1',
        'movement_id': 'movement-1',
        'revision_id': 'revision-1',
        'result_type': 'personal_practice',
        'total_score': 87.5,
        'component_scores': {'Timing': 3},
        'feedback': ['Good timing'],
      }, id: 'result-1');

      expect(result, isNotNull);
      expect(result!.totalScore, 87.5);
      expect(result.componentScores, {'Timing': 3.0});
      expect(result.feedback, ['Good timing']);
    });

    test('rejects malformed scores and non-personal result records', () {
      final valid = {
        'owner_uid': 'trainee-1',
        'movement_id': 'movement-1',
        'revision_id': 'revision-1',
        'result_type': 'personal_practice',
        'total_score': 87.5,
        'component_scores': {'Timing': 3},
        'feedback': ['Good timing'],
      };

      expect(
        CustomMovementResult.tryFromMap({
          ...valid,
          'total_score': 101,
        }, id: 'result-1'),
        isNull,
      );
      expect(
        CustomMovementResult.tryFromMap({
          ...valid,
          'result_type': 'assignment',
        }, id: 'result-1'),
        isNull,
      );
    });
  });
}
