import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Score band label for scored-session presentation only.
String trainingPerformanceLabel(int score) {
  final clamped = score.clamp(0, 100);
  if (clamped >= 85) return 'Excellent';
  if (clamped >= 70) return 'Developing';
  return 'Needs Practice';
}

double trainingPerformanceFraction(int? score) {
  if (score == null) return 0.0;
  return (score / 100).clamp(0.0, 1.0);
}

Color _bandColor(int? score) {
  if (score == null) return AppColors.textSecondary;
  final clamped = score.clamp(0, 100);
  if (clamped >= 85) return AppColors.success;
  if (clamped >= 70) return AppColors.primarySoft;
  return AppColors.warning;
}

/// Practice-session performance bar (not XP). Scored presentation only.
class TrainingPerformanceBar extends StatelessWidget {
  const TrainingPerformanceBar({super.key, required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final hasScore = score != null;
    final value = trainingPerformanceFraction(score);
    final bandLabel = hasScore
        ? trainingPerformanceLabel(score!)
        : 'Waiting for score';
    final display = hasScore ? '${score!.clamp(0, 100)} / 100' : '—';
    final bandColor = _bandColor(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Performance',
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
                color: hasScore
                    ? AppColors.primarySoft
                    : context.elixTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: ColoredBox(
            color: context.elixBorder.withValues(alpha: 0.35),
            child: SizedBox(
              height: 10,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: value),
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: hasScore && v > 0 ? v : 0.001,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: hasScore
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
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bandColor.withValues(alpha: hasScore ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: bandColor.withValues(alpha: hasScore ? 0.28 : 0.18),
            ),
          ),
          child: Text(
            bandLabel,
            style: AppTheme.caption.copyWith(
              color: hasScore ? bandColor : context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
