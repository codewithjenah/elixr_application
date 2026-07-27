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

/// Practice-session performance bar (not XP). Scored presentation only.
class TrainingPerformanceBar extends StatelessWidget {
  const TrainingPerformanceBar({super.key, required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final value = trainingPerformanceFraction(score);
    final bandLabel = score == null ? '—' : trainingPerformanceLabel(score!);
    final display = score == null ? '— / 100' : '${score!.clamp(0, 100)} / 100';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Performance',
              style: AppTheme.caption.copyWith(
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: context.elixTextSecondary,
              ),
            ),
            Text(
              display,
              style: AppTheme.caption.copyWith(
                color: AppColors.primarySoft,
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
              height: 8,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: value),
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v == 0 ? 0.001 : v,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primarySoft],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          bandLabel,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
      ],
    );
  }
}
