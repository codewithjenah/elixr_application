import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _rubricSession({
  int technique = 3,
  int stability = 3,
  int completion = 2,
  int propPositioning = 2,
  int? claimedTotal,
  String? claimedLevel,
}) {
  return {
    'user_id': 'u1',
    'assessment_version': 2,
    'rubric': {
      'technique': technique,
      'stability': stability,
      'completion': completion,
      'prop_positioning': propPositioning,
    },
    'rubric_total': ?claimedTotal,
    'performance_level': ?claimedLevel,
  };
}

void main() {
  group('LeaderboardRepository.readSessionAssessment', () {
    test('legacy session resolves to its percentage score', () {
      final assessment = LeaderboardRepository.readSessionAssessment({
        'user_id': 'u1',
        'score': 82,
      });

      expect(assessment.isRubric, isFalse);
      expect(assessment.legacyScore, 82);
      expect(assessment.rubricTotal, isNull);
      expect(assessment.markerScoreField, {'score': 82});
    });

    test('legacy session rounds a whole-number double score', () {
      final assessment = LeaderboardRepository.readSessionAssessment({
        'user_id': 'u1',
        'score': 79.0,
      });
      expect(assessment.legacyScore, 79);
    });

    test('missing legacy score is rejected', () {
      expect(
        () => LeaderboardRepository.readSessionAssessment({'user_id': 'u1'}),
        throwsA(isA<LeaderboardAwardException>()),
      );
    });

    test('V2 session resolves to a rubric total and marker field', () {
      final assessment = LeaderboardRepository.readSessionAssessment(
        _rubricSession(claimedTotal: 10, claimedLevel: 'proficient'),
      );

      expect(assessment.isRubric, isTrue);
      expect(assessment.rubricTotal, 10);
      expect(assessment.legacyScore, isNull);
      expect(assessment.markerScoreField, {'rubric_total': 10});
    });

    test('V2 total is re-derived rather than trusted from the document', () {
      // A stored `rubric_total` that disagrees with the criteria is a
      // tampered or corrupt document and must not award anything.
      expect(
        () => LeaderboardRepository.readSessionAssessment(
          _rubricSession(claimedTotal: 12),
        ),
        throwsA(isA<LeaderboardAwardException>()),
      );
    });

    test('V2 session with a malformed rubric never falls back to score', () {
      expect(
        () => LeaderboardRepository.readSessionAssessment({
          'user_id': 'u1',
          'assessment_version': 2,
          'score': 95,
        }),
        throwsA(isA<LeaderboardAwardException>()),
      );
    });

    test('V2 session with an out-of-range criterion is rejected', () {
      expect(
        () => LeaderboardRepository.readSessionAssessment(
          _rubricSession(technique: 4),
        ),
        throwsA(isA<LeaderboardAwardException>()),
      );
    });

    test('a V2 award never contributes to the percentage aggregates', () {
      final assessment = LeaderboardRepository.readSessionAssessment(
        _rubricSession(),
      );
      // `legacyScore` is what the award plan consumes; null freezes
      // score_sum / average_score / best_score and their period mirrors.
      expect(assessment.legacyScore, isNull);
    });
  });

  group('LeaderboardRepository.ensureOfficialMovementForGlobalXp', () {
    test('official catalog names remain awardable', () {
      expect(
        () => LeaderboardRepository.ensureOfficialMovementForGlobalXp({
          'movement_name': 'Hand Stall',
        }),
        returnsNormally,
      );
    });

    test('non-official names cannot award global XP', () {
      for (final name in [
        'Wrist Stall',
        'Arm Stall',
        'Upper Forearm Stall',
        'Free Practice',
        'Not A Real Move',
      ]) {
        expect(
          () => LeaderboardRepository.ensureOfficialMovementForGlobalXp({
            'movement_name': name,
          }),
          throwsA(isA<LeaderboardAwardException>()),
          reason: name,
        );
      }
    });

    test('missing movement names cannot award global XP', () {
      expect(
        () => LeaderboardRepository.ensureOfficialMovementForGlobalXp({
          'user_id': 'u1',
        }),
        throwsA(isA<LeaderboardAwardException>()),
      );
    });
  });
}
