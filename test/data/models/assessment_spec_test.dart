import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _golden({
  String laterality = 'either',
  Map<String, dynamic>? extra,
}) {
  return {
    'schema_version': 1,
    'template_id': 'balance_stall.wrist_v1',
    'prop': 'bottle',
    'target': 'wrist',
    'laterality': laterality,
    ...?extra,
  };
}

void main() {
  group('AssessmentSpec golden parse', () {
    test('parses the canonical Wrist Stall v1 spec', () {
      final spec = AssessmentSpec.tryFrom(_golden());
      expect(spec, isNotNull);
      expect(spec!.schemaVersion, 1);
      expect(spec.templateId, AssessmentTemplateId.balanceStallWristV1);
      expect(spec.prop, AssessmentProp.bottle);
      expect(spec.target, AssessmentTarget.wrist);
      expect(spec.laterality, AssessmentLaterality.either);
    });

    test('parses laterality either, left, and right', () {
      expect(
        AssessmentSpec.tryFrom(_golden(laterality: 'either'))?.laterality,
        AssessmentLaterality.either,
      );
      expect(
        AssessmentSpec.tryFrom(_golden(laterality: 'left'))?.laterality,
        AssessmentLaterality.left,
      );
      expect(
        AssessmentSpec.tryFrom(_golden(laterality: 'right'))?.laterality,
        AssessmentLaterality.right,
      );
    });
  });

  group('AssessmentSpec fail-closed validation', () {
    test('rejects schema 0, schema 2, and missing schema', () {
      expect(AssessmentSpec.tryFrom(_golden()..['schema_version'] = 0), isNull);
      expect(AssessmentSpec.tryFrom(_golden()..['schema_version'] = 2), isNull);
      final missing = _golden()..remove('schema_version');
      expect(AssessmentSpec.tryFrom(missing), isNull);
    });

    test('rejects unknown template id', () {
      expect(
        AssessmentSpec.tryFrom(
          _golden()..['template_id'] = 'balance_stall.elbow_v1',
        ),
        isNull,
      );
    });

    test('rejects shaker and other props', () {
      expect(AssessmentSpec.tryFrom(_golden()..['prop'] = 'shaker'), isNull);
      expect(
        AssessmentSpec.tryFrom(_golden()..['prop'] = 'bottle_and_shaker'),
        isNull,
      );
    });

    test('rejects a target that is not wrist', () {
      expect(AssessmentSpec.tryFrom(_golden()..['target'] = 'forearm'), isNull);
    });

    test('rejects invalid laterality', () {
      expect(AssessmentSpec.tryFrom(_golden(laterality: 'both')), isNull);
      expect(AssessmentSpec.tryFrom(_golden(laterality: 'Either')), isNull);
    });

    test('rejects missing required fields', () {
      for (final key in [
        'schema_version',
        'template_id',
        'prop',
        'target',
        'laterality',
      ]) {
        final raw = _golden()..remove(key);
        expect(AssessmentSpec.tryFrom(raw), isNull, reason: 'missing $key');
      }
    });

    test('rejects wrong field types and null required values', () {
      expect(
        AssessmentSpec.tryFrom(_golden()..['schema_version'] = '1'),
        isNull,
      );
      expect(
        AssessmentSpec.tryFrom(_golden()..['schema_version'] = 1.0),
        isNull,
      );
      expect(AssessmentSpec.tryFrom(_golden()..['template_id'] = 1), isNull);
      expect(AssessmentSpec.tryFrom(_golden()..['prop'] = true), isNull);
      expect(AssessmentSpec.tryFrom(_golden()..['laterality'] = null), isNull);
      expect(AssessmentSpec.tryFrom(null), isNull);
      expect(AssessmentSpec.tryFrom('balance_stall.wrist_v1'), isNull);
      expect(AssessmentSpec.tryFrom(<dynamic>[]), isNull);
    });

    test('rejects extra threshold, executable, and unknown keys', () {
      const extras = [
        'threshold',
        'thresholds',
        'distance',
        'tolerance',
        'confidence',
        'angle',
        'hold_seconds',
        'hold_frames',
        'eval',
        'formula',
        'code',
        'python',
        'javascript',
        'expression',
        'script',
        'raw_rule',
        'custom_rule',
        'custom_threshold',
        'arbitrary_unknown_key',
      ];
      for (final key in extras) {
        expect(
          AssessmentSpec.tryFrom(_golden(extra: {key: 1})),
          isNull,
          reason: 'extra $key',
        );
      }
    });
  });

  test('left and right Wrist Stall specs round-trip', () {
    for (final laterality in [
      AssessmentLaterality.left,
      AssessmentLaterality.right,
    ]) {
      final spec = AssessmentSpec(laterality: laterality);
      expect(spec.isWritableWristStallV1, isTrue);
      expect(AssessmentSpec.tryFrom(spec.toMap()), spec);
    }
    expect(
      const AssessmentSpec(
        laterality: AssessmentLaterality.either,
      ).isWritableWristStallV1,
      isFalse,
    );
    expect(
      const AssessmentSpec(
        laterality: AssessmentLaterality.either,
      ).isCanonicalWristStallV1,
      isTrue,
    );
  });

  test('protocol identity stays out of official progression catalogs', () {
    expect(
      movementCatalog.any(
        (movement) => movement.name == AssessmentSpec.protocolMovementName,
      ),
      isFalse,
    );
    expect(
      coachingMovementNames.contains(AssessmentSpec.protocolMovementName),
      isFalse,
    );
    expect(
      officialElixrMovementNames.contains(AssessmentSpec.protocolMovementName),
      isFalse,
    );
  });
}
