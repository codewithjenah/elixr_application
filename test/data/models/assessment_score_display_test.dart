import 'package:elixr_application/data/models/assessment_score_display.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official scores stay on the 0..12 scale without a percentage', () {
    expect(AssessmentScoreDisplay.official(9), '9/12');
    expect(AssessmentScoreDisplay.official(12), '12/12');
    expect(AssessmentScoreDisplay.official(0), '0/12');
  });

  test('official averages stay on the 0..12 scale', () {
    expect(AssessmentScoreDisplay.officialAverage(8.25), '8.3/12');
    expect(AssessmentScoreDisplay.officialAverage(10.0), '10/12');
    expect(AssessmentScoreDisplay.officialAverage(9.5), '9.5/12');
  });

  test('friendly performance labels map from PerformanceLevel', () {
    expect(
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.beginning),
      'Getting Started',
    );
    expect(
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.developing),
      'Learning',
    );
    expect(
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.competent),
      'Good',
    );
    expect(
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.proficient),
      'Great',
    );
    expect(
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.mastered),
      'Mastered',
    );
  });

  test('performance labels for totals use PerformanceLevel.fromTotal', () {
    expect(
      AssessmentScoreDisplay.performanceLabelForTotal(3),
      'Getting Started',
    );
    expect(AssessmentScoreDisplay.performanceLabelForTotal(6), 'Learning');
    expect(AssessmentScoreDisplay.performanceLabelForTotal(9), 'Good');
    expect(AssessmentScoreDisplay.performanceLabelForTotal(11), 'Great');
    expect(AssessmentScoreDisplay.performanceLabelForTotal(12), 'Mastered');
  });

  test('friendly criterion labels map from RubricCriterion', () {
    expect(
      AssessmentScoreDisplay.criterionLabel(RubricCriterion.technique),
      'Form',
    );
    expect(
      AssessmentScoreDisplay.criterionLabel(RubricCriterion.stability),
      'Control',
    );
    expect(
      AssessmentScoreDisplay.criterionLabel(RubricCriterion.completion),
      'Finish',
    );
    expect(
      AssessmentScoreDisplay.criterionLabel(RubricCriterion.propPositioning),
      'Position',
    );
  });

  test('official with performance pairs /12 and the friendly label', () {
    expect(AssessmentScoreDisplay.officialWithPerformance(8), '8/12 · Good');
    expect(AssessmentScoreDisplay.officialWithPerformance(10), '10/12 · Great');
  });

  test('criterion scores use friendly names on the 0..3 scale', () {
    expect(
      AssessmentScoreDisplay.criterionScore(RubricCriterion.technique, 3),
      'Form 3/3',
    );
    expect(
      AssessmentScoreDisplay.criterionScore(
        RubricCriterion.stability,
        2,
        colon: true,
      ),
      'Control: 2/3',
    );
  });

  test('official semantics include score and friendly label', () {
    expect(
      AssessmentScoreDisplay.officialSemantics(8),
      'ELIXR Score 8 out of 12, Good',
    );
  });

  test('Teacher Activity scores retain assignment maximum', () {
    expect(
      AssessmentScoreDisplay.teacherActivity(earned: 44, maximum: 50),
      '44/50 • 88%',
    );
  });

  test('normalization is bounded and handles invalid maximum', () {
    expect(
      AssessmentScoreDisplay.normalizedPercentage(earned: 14, maximum: 12),
      100,
    );
    expect(
      AssessmentScoreDisplay.normalizedPercentage(earned: 4, maximum: 0),
      0,
    );
  });
}
