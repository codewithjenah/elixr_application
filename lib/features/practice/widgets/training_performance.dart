import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/rubric_assessment.dart';

/// Assessment V2 rubric total presented as a 0..12 performance level.
String trainingPerformanceLabel(int total) =>
    PerformanceLevel.fromTotal(total.clamp(0, RubricScale.maxTotal)).label;

double trainingPerformanceFraction(int? total) {
  if (total == null) return 0.0;
  return (total / RubricScale.maxTotal).clamp(0.0, 1.0);
}

/// Rubric scale constants shared by practice performance widgets.
abstract final class RubricScale {
  static const maxTotal = 12;
  static const maxCriterion = 3;
}

Color performanceLevelColor(PerformanceLevel? level) => switch (level) {
  null => AppColors.textSecondary,
  PerformanceLevel.mastered || PerformanceLevel.proficient => AppColors.success,
  PerformanceLevel.competent => AppColors.primarySoft,
  PerformanceLevel.developing => AppColors.warning,
  PerformanceLevel.beginning => AppColors.error,
};

/// Practice-session rubric bar (not XP). Scored presentation only.
class TrainingPerformanceBar extends StatelessWidget {
  const TrainingPerformanceBar({super.key, required this.total});

  /// Rubric total (0..12), or null before the first assessment frame.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final hasTotal = total != null;
    final clamped = hasTotal ? total!.clamp(0, RubricScale.maxTotal) : 0;
    final value = trainingPerformanceFraction(total);
    final level = hasTotal ? PerformanceLevel.fromTotal(clamped) : null;
    final levelLabel = level?.label ?? 'Waiting for assessment';
    final display = hasTotal ? '$clamped / ${RubricScale.maxTotal}' : '—';
    final levelColor = performanceLevelColor(level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Current Performance',
              style: AppTheme.caption.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: context.elixTextSecondary,
              ),
            ),
            const Spacer(),
            Text(
              display,
              style: AppTheme.caption.copyWith(
                color: hasTotal
                    ? AppColors.primarySoft
                    : context.elixTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: ColoredBox(
            color: context.elixBorder.withValues(alpha: 0.35),
            child: SizedBox(
              height: 7,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: value),
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: hasTotal && v > 0 ? v : 0.001,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: hasTotal
                            ? [
                                AppColors.primary,
                                AppColors.accent,
                                AppColors.primarySoft,
                              ]
                            : [
                                context.elixBorder.withValues(alpha: 0.25),
                                context.elixBorder.withValues(alpha: 0.25),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: levelColor.withValues(alpha: hasTotal ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: levelColor.withValues(alpha: hasTotal ? 0.28 : 0.18),
            ),
          ),
          child: Text(
            levelLabel,
            style: AppTheme.caption.copyWith(
              color: hasTotal ? levelColor : context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Live 2x2 breakdown of the four rubric criteria (each 0..3).
class RubricCriteriaTiles extends StatelessWidget {
  const RubricCriteriaTiles({super.key, required this.assessment});

  final RubricAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    const criteria = RubricCriterion.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < criteria.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CriterionTile(
                    criterion: criteria[row],
                    assessment: assessment,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CriterionTile(
                    criterion: criteria[row + 1],
                    assessment: assessment,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CriterionTile extends StatelessWidget {
  const _CriterionTile({required this.criterion, required this.assessment});

  final RubricCriterion criterion;
  final RubricAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final score = assessment?.scoreFor(criterion);
    return Container(
      key: ValueKey('rubric-criterion-${criterion.wireValue}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: AppTheme.practiceMetricTileDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            criterion.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(
              fontSize: 10.5,
              height: 1.2,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w700,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            score != null ? '$score / ${RubricScale.maxCriterion}' : '—',
            style: AppTheme.body.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: score != null
                  ? AppColors.primary
                  : context.elixTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
