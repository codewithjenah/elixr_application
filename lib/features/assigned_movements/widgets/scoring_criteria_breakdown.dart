import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/teacher_activity_assessment.dart';

class ScoringCriteriaBreakdown extends StatelessWidget {
  const ScoringCriteriaBreakdown({
    super.key,
    required this.assessment,
    required this.scores,
    required this.total,
  });

  final TeacherActivityAssessmentConfig assessment;
  final Map<String, int> scores;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('scoring_criteria_breakdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scoring criteria', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final criterion in assessment.rubric.criteria)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(child: Text(criterion.label, style: AppTheme.body)),
                Text(
                  '${scores[criterion.id] ?? 0} / ${criterion.maximumPoints}',
                  key: Key('scoring_criterion_${criterion.id}'),
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Total',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$total / ${assessment.rubric.maximumScore}',
              key: const Key('scoring_criteria_total'),
              style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
