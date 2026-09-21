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
      expect(template.claimsUnsupportedRotation, isFalse);
      expect(template.toMap(), templateMap());
    });

    test('rejects executable/unknown fields and unsupported rotation', () {
      final executable = templateMap()..['python_rule'] = 'eval(user_input)';
      final rotating = templateMap();
      (rotating['feature_capabilities']
              as Map<String, dynamic>)['prop_rotation'] =
          true;

      expect(MovementTemplate.tryFrom(executable), isNull);
      expect(MovementTemplate.tryFrom(rotating), isNull);
    });

    test('requires the exact capability contract', () {
      final missing = templateMap();
      (missing['feature_capabilities'] as Map<String, dynamic>).remove('hands');

      expect(MovementTemplate.tryFrom(missing), isNull);
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

    test('revision requires at least three references', () {
      final incomplete = templateMap()..['reference_count'] = 2;

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
}
