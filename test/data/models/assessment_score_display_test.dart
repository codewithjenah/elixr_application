import 'package:elixr_application/data/models/assessment_score_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official scores retain /12 and add normalized percentage', () {
    expect(AssessmentScoreDisplay.official(9), '9/12 • 75%');
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
