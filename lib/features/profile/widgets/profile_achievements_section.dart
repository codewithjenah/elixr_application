import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/achievement.dart';
import 'profile_section_card.dart';

class ProfileAchievementsSection extends StatelessWidget {
  const ProfileAchievementsSection({
    super.key,
    required this.achievements,
    this.maxVisible = 6,
    this.showViewAll = true,
  });

  final List<AchievementDefinition> achievements;
  final int maxVisible;
  final bool showViewAll;

  @override
  Widget build(BuildContext context) {
    final visible = achievements.length <= maxVisible
        ? achievements
        : achievements.take(maxVisible).toList(growable: false);

    return ProfileSectionCard(
      title: 'Achievements',
      trailing: showViewAll
          ? HyperlinkButton(
              onPressed: () => context.push('/achievements'),
              child: const Text('View All'),
            )
          : null,
      child: achievements.isEmpty
          ? Text(
              'No claimed achievements yet.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 900
                    ? 3
                    : width >= 560
                    ? 2
                    : 1;
                const gap = AppSpacing.sm;
                final tileWidth = (width - gap * (columns - 1)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final achievement in visible)
                      SizedBox(
                        width: tileWidth,
                        child: _ClaimedBadge(achievement: achievement),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _ClaimedBadge extends StatelessWidget {
  const _ClaimedBadge({required this.achievement});

  final AchievementDefinition achievement;

  @override
  Widget build(BuildContext context) {
    final milestone = context.elixColors.milestone;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : milestone.withValues(alpha: 0.35),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: FittedBox(
              fit: BoxFit.contain,
              child: ProfileBorderFrame(
                size: 36,
                equippedBorderId: achievement.rewardBorderId,
                child: ColoredBox(
                  color: context.isHighContrast
                      ? context.elixCardSurface
                      : milestone.withValues(alpha: 0.12),
                  child: Image.asset(
                    achievement.iconAssetPath,
                    fit: BoxFit.contain,
                    semanticLabel: achievement.title,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextPrimary,
                  ),
                ),
                Text(
                  achievement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
