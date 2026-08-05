import 'dart:convert';
import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
import 'package:elixr_application/features/practice/coaching/session_recommendation.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _frame({
  required String movement,
  String feedback = 'Keep refining technique.',
  String? feedbackCode = 'prop_not_steady',
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: movement,
    score: 70,
    feedback: feedback,
    feedbackType: 'warning',
    postureStatus: 'unstable',
    sessionState: 'active',
    feedbackCode: feedbackCode,
    feedbackCategory: 'technique',
  );
}

/// Phase C cross-layer consistency gate.
///
/// Authoritative product set: enabled entries in [movementCatalog].
/// Shared manifest: `test/fixtures/enabled_scored_movements.json` must match
/// that set and is also consumed by the Python consistency test.
Map<String, dynamic> _loadManifest() {
  final file = File('test/fixtures/enabled_scored_movements.json');
  expect(file.existsSync(), isTrue, reason: 'shared movement manifest missing');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<String> _manifestNames(Map<String, dynamic> manifest) {
  final movements = manifest['movements'] as List<dynamic>;
  return movements
      .map((entry) => (entry as Map<String, dynamic>)['name'] as String)
      .toList(growable: false);
}

void main() {
  late Map<String, dynamic> manifest;
  late List<String> manifestNames;
  late List<String> enabledCatalogNames;

  setUpAll(() {
    manifest = _loadManifest();
    manifestNames = _manifestNames(manifest);
    enabledCatalogNames = movementCatalog
        .where((m) => m.enabled)
        .map((m) => m.name)
        .toList(growable: false);
  });

  test('shared manifest matches enabled Flutter catalog exactly', () {
    expect(manifestNames, unorderedEquals(enabledCatalogNames));
    expect(manifest['authority'], isA<String>());
    expect((manifest['authority'] as String).isNotEmpty, isTrue);
  });

  test('every enabled movement has exactly one coaching config entry', () {
    for (final name in enabledCatalogNames) {
      expect(
        movementPositiveLockedCodes.keys.where((k) => k == name).length,
        1,
        reason: name,
      );
      expect(positiveLockedCodeForMovement(name), isNotNull, reason: name);
      expect(
        recommendedDurationForMovement(name),
        greaterThan(0),
        reason: name,
      );
      expect(movementCoachingProfileFor(name), isNotNull, reason: name);
      expect(confirmedStrengthMessageFor(name), isNotEmpty, reason: name);
      expect(formStrengthMessageFor(name), isNotEmpty, reason: name);
      expect(
        formStrengthMessageFor(name).toLowerCase(),
        isNot(contains('confirmed')),
        reason: name,
      );
    }
  });

  test('coaching config has no extras outside enabled catalog', () {
    expect(
      movementPositiveLockedCodes.keys.toSet(),
      equals(enabledCatalogNames.toSet()),
    );
    expect(
      movementRecommendedDurationSeconds.keys.toSet(),
      equals(enabledCatalogNames.toSet()),
    );
    expect(
      movementCoachingProfiles.keys.toSet(),
      equals(enabledCatalogNames.toSet()),
    );
  });

  test('positive success codes are nonempty and unique across movements', () {
    final codes = <String>{};
    for (final name in enabledCatalogNames) {
      final code = positiveLockedCodeForMovement(name)!;
      expect(code, isNotEmpty, reason: name);
      expect(codes.add(code), isTrue, reason: 'duplicate positive code $code');
    }
  });

  test('manifest positive codes match Flutter coaching config', () {
    final movements = manifest['movements'] as List<dynamic>;
    for (final entry in movements) {
      final map = entry as Map<String, dynamic>;
      final name = map['name'] as String;
      final positive = map['positive_code'] as String;
      expect(positiveLockedCodeForMovement(name), positive);
    }
  });

  test('focus copy exists for every listed technique code', () {
    final movements = manifest['movements'] as List<dynamic>;
    for (final entry in movements) {
      final map = entry as Map<String, dynamic>;
      final name = map['name'] as String;
      final codes = (map['technique_codes'] as List<dynamic>).cast<String>();
      for (final code in codes) {
        final focus = focusCopyForCode(
          code,
          prop: TrainingProp.bottle,
          fallbackMessage: '__NO_FOCUS_FALLBACK__',
        );
        expect(
          focus,
          isNot('__NO_FOCUS_FALLBACK__'),
          reason: '$name / $code missing explicit focus copy',
        );
        expect(focus, isNotEmpty, reason: '$name / $code');
      }
    }
  });

  test('same-movement recommendation is deterministic for every movement', () {
    for (final name in enabledCatalogNames) {
      SessionRecommendation build() => buildSessionRecommendation(
        movement: name,
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 70,
        positiveRatio: 0.4,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Keep refining technique.',
            occurrenceCount: 5,
            occurrenceRatio: 0.25,
            feedbackType: 'warning',
            representativeFeedback: _frame(movement: name),
            code: 'prop_not_steady',
          ),
        ],
        maxHoldDurationMs: 800,
        maxHoldProgress: 0.3,
        holdTargetMs: 2500,
      );

      final first = build();
      final second = build();
      expect(first.movementName, name);
      expect(second.movementName, name);
      expect(first.reason, second.reason);
      expect(first.targetLabel, second.targetLabel);
      expect(
        first.recommendedDurationSeconds,
        second.recommendedDurationSeconds,
      );
      expect(first.movementName, isNot(equals('Some Other Movement')));
    }
  });

  test('unknown movement falls back to default duration without crashing', () {
    expect(recommendedDurationForMovement('Legacy Unknown Stall'), 180);
    expect(positiveLockedCodeForMovement('Legacy Unknown Stall'), isNull);
    final recommendation = buildSessionRecommendation(
      movement: 'Legacy Unknown Stall',
      prop: TrainingProp.bottle,
      heldSteady: false,
      finalScore: 50,
      positiveRatio: 0,
      totalApplicableSamples: 0,
      improvements: const [],
      maxHoldDurationMs: 0,
      maxHoldProgress: 0,
      holdTargetMs: 0,
    );
    expect(recommendation.movementName, 'Legacy Unknown Stall');
    expect(recommendation.targetLabel, 'Complete one confirmed hold');
  });
}
