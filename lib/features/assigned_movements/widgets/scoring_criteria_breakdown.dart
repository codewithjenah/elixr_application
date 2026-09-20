import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../data/models/teacher_activity_assessment.dart';

/// Read-only score summary shown once work has been checked.
///
/// Presentation only: the stored criterion scores and total are rendered
/// exactly as saved, with the total carrying the strongest hierarchy and each
/// criterion shown as a compact metric row with a subtle strength bar.
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
    final maximum = assessment.rubric.maximumScore;
    final percent = maximum > 0 ? (total / maximum * 100).round() : null;
    final criteria = assessment.rubric.criteria;
    return Column(
      key: const Key('scoring_criteria_breakdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text('Scoring criteria', style: AppTheme.headingMedium),
            ),
            Text(
              '$total / $maximum',
              key: const Key('scoring_criteria_total'),
              style: AppTheme.metric(context),
            ),
            if (percent != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '$percent%',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.smPlus),
        Container(
          decoration: BoxDecoration(
            color: context.elixColors.surfaceTinted,
            borderRadius: BorderRadius.circular(ElixRadius.card),
            border: Border.all(color: context.elixBorder),
          ),
          child: Column(
            children: [
              for (var i = 0; i < criteria.length; i++) ...[
                if (i > 0) Container(height: 1, color: context.elixBorder),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          criteria[i].label,
                          style: AppTheme.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smPlus),
                      SizedBox(
                        width: 56,
                        child: ProgressBar(
                          value:
                              ((scores[criteria[i].id] ?? 0) /
                                      criteria[i].maximumPoints *
                                      100)
                                  .clamp(0.0, 100.0)
                                  .toDouble(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smPlus),
                      Text(
                        '${scores[criteria[i].id] ?? 0} / ${criteria[i].maximumPoints}',
                        key: Key('scoring_criterion_${criteria[i].id}'),
                        style: AppTheme.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
