import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/achievement.dart';
import '../../../data/models/profile_border.dart';

class AchievementCard extends StatelessWidget {
  const AchievementCard({
    super.key,
    required this.view,
    required this.claiming,
    required this.onClaim,
  });

  final AchievementViewData view;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    final locked = state == AchievementState.locked;
    final claimable = state == AchievementState.claimable;
    final claimed = state == AchievementState.claimed;
    final border = profileBorderById(view.definition.rewardBorderId);

    return Opacity(
      opacity: locked ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: claimable
                ? AppColors.primary.withValues(alpha: 0.55)
                : claimed
                ? AppColors.success.withValues(alpha: 0.4)
                : context.elixBorder.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileBorderFrame(
                  size: 44,
                  equippedBorderId: view.definition.rewardBorderId,
                  child: Container(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    child: Icon(
                      FluentIcons.trophy2,
                      size: 20,
                      color: locked
                          ? context.elixTextSecondary
                          : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.definition.title,
                        style: AppTheme.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.elixTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _categoryLabel(view.definition.category),
                        style: AppTheme.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _StateChip(state: state),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              view.definition.description,
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${view.progress.current} / ${view.progress.target}',
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
                if (border != null)
                  Text(
                    border.displayName,
                    style: AppTheme.caption.copyWith(
                      color: Color(border.primaryColorValue),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(
                      color: context.elixBorder.withValues(alpha: 0.45),
                    ),
                    FractionallySizedBox(
                      widthFactor: view.progress.normalizedProgress,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (claimable)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: claiming ? null : onClaim,
                  child: claiming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('Claim'),
                ),
              )
            else if (claimed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Claimed',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  locked ? 'Locked' : 'In progress',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _categoryLabel(AchievementCategory category) {
    return switch (category) {
      AchievementCategory.sessions => 'Sessions',
      AchievementCategory.score => 'Score',
      AchievementCategory.exploration => 'Exploration',
      AchievementCategory.consistency => 'Consistency',
      AchievementCategory.specialization => 'Specialization',
    };
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final AchievementState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      AchievementState.locked => ('Locked', context.elixTextSecondary),
      AchievementState.inProgress => ('In Progress', AppColors.warning),
      AchievementState.claimable => ('Claimable', AppColors.primary),
      AchievementState.claimed => ('Claimed', AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
