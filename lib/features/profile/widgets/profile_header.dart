import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_identity.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.displayName,
    required this.isSelf,
    this.profilePictureUrl,
    this.equippedBorderId,
    this.level,
    this.totalXp,
    this.rank,
    this.showUnrankedLabel = false,
  });

  final String displayName;
  final bool isSelf;
  final String? profilePictureUrl;
  final String? equippedBorderId;
  final int? level;
  final int? totalXp;
  final int? rank;
  final bool showUnrankedLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? AppColors.panelSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          LeaderboardInitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(displayName),
            accent: AppColors.primary,
            size: 72,
            profilePictureUrl: profilePictureUrl,
            equippedBorderId: equippedBorderId,
            highlightRing: isSelf,
            animateBorder: true,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: context.elixTextPrimary,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const LeaderboardYouBadge(),
                    ],
                  ],
                ),
                if (level != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Level $level',
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
                if (totalXp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$totalXp XP',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
                if (rank != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Rank #$rank',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ] else if (showUnrankedLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Unranked',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
