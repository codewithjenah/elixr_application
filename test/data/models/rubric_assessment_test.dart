import 'package:flutter_test/flutter_test.dart';

import 'package:elixr_application/data/models/rubric_assessment.dart';

void main() {
  group('PerformanceLevel thresholds', () {
    test('fromTotal boundaries', () {
      expect(PerformanceLevel.fromTotal(0), PerformanceLevel.beginning);
      expect(PerformanceLevel.fromTotal(3), PerformanceLevel.beginning);
      expect(PerformanceLevel.fromTotal(4), PerformanceLevel.developing);
      expect(PerformanceLevel.fromTotal(6), PerformanceLevel.developing);
      expect(PerformanceLevel.fromTotal(7), PerformanceLevel.competent);
      expect(PerformanceLevel.fromTotal(9), PerformanceLevel.competent);
      expect(PerformanceLevel.fromTotal(10), PerformanceLevel.proficient);
      expect(PerformanceLevel.fromTotal(11), PerformanceLevel.proficient);
      expect(PerformanceLevel.fromTotal(12), PerformanceLevel.mastered);
    });

    test('fromAverage uses same policy', () {
      expect(PerformanceLevel.fromAverage(9.6), PerformanceLevel.proficient);
      // 3.4 rounds to 3 → beginning (same thresholds as fromTotal).
      expect(PerformanceLevel.fromAverage(3.4), PerformanceLevel.beginning);
      expect(PerformanceLevel.fromAverage(3.5), PerformanceLevel.developing);
    });

    test('rejects out of range', () {
      expect(() => PerformanceLevel.fromTotal(-1), throwsArgumentError);
      expect(() => PerformanceLevel.fromTotal(13), throwsArgumentError);
    });
  });

  group('RubricAssessment', () {
    test('derives total and performance level', () {
      const assessment = RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
      );
      expect(assessment.total, 10);
      expect(assessment.performanceLevel, PerformanceLevel.proficient);
    });

    test('Firestore round trip', () {
      const assessment = RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
      );
      final fields = assessment.toFirestoreFields();
      expect(fields['assessment_version'], 2);
      expect(fields['rubric_total'], 10);
      expect(fields['performance_level'], 'proficient');
      final parsed = RubricAssessment.tryFromFirestore(fields);
      expect(parsed, assessment);
    });

    test('JSON round trip', () {
      const assessment = RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
        techniqueReason: 'correct_technique',
      );
      final parsed = RubricAssessment.tryFromJson(assessment.toJson());
      expect(parsed?.total, 10);
      expect(parsed?.techniqueReason, 'correct_technique');
    });

    test('rejects mismatched total', () {
      final parsed = RubricAssessment.tryFromJson({
        'version': 2,
        'criteria': {
          'technique': {'score': 3, 'reason_code': 'a'},
          'stability': {'score': 3, 'reason_code': 'b'},
          'completion': {'score': 3, 'reason_code': 'c'},
          'prop_positioning': {'score': 3, 'reason_code': 'd'},
        },
        'total': 10,
        'performance_level': 'mastered',
      });
      expect(parsed, isNull);
    });

    test('rejects criterion above 3', () {
      final parsed = RubricAssessment.tryFromJson({
        'version': 2,
        'criteria': {
          'technique': {'score': 4, 'reason_code': 'a'},
          'stability': {'score': 3, 'reason_code': 'b'},
          'completion': {'score': 3, 'reason_code': 'c'},
          'prop_positioning': {'score': 3, 'reason_code': 'd'},
        },
        'total': 13,
        'performance_level': 'mastered',
      });
      expect(parsed, isNull);
    });

    test('legacy Firestore map without assessment_version is null', () {
      final parsed = RubricAssessment.tryFromFirestore({
        'score': 83,
        'movement_name': 'Hand Stall',
      });
      expect(parsed, isNull);
    });
  });
}
