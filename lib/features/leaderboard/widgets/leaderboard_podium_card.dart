import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';
import 'leaderboard_podium.dart';

class LeaderboardPodiumCard extends StatelessWidget {
  const LeaderboardPodiumCard({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
    this.profilePictureUrl,
    this.variant = LeaderboardPodiumVariant.full,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final LeaderboardPodiumVariant variant;

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final compact = variant == LeaderboardPodiumVariant.compact;
    final accent = LeaderboardRankStyle.medalForRank(rank);
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;

    final topPad = compact ? (isFirst ? 16.0 : 12.0) : (isFirst ? 20.0 : 14.0);
    final sidePad = compact ? 10.0 : 14.0;
    final avatarSize = compact
        ? (isFirst ? 40.0 : 34.0)
        : (isFirst ? 48.0 : 40.0);
    final nameSize = compact
        ? (isFirst ? 13.0 : 12.0)
        : (isFirst ? 15.0 : 13.0);
    final xpSize = compact ? (isFirst ? 14.0 : 12.0) : (isFirst ? 16.0 : 14.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(sidePad, topPad, sidePad, sidePad),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(
          color: accent.withValues(alpha: isFirst ? 0.5 : 0.32),
          width: isFirst ? 1.4 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: isFirst ? 0.14 : 0.08),
            panel.withValues(alpha: 0.15),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isFirst ? 0.10 : 0.05),
            blurRadius: isFirst ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      foregroundDecoration: isCurrentUser
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 14 : 16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.45),
                width: 1.5,
              ),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isFirst ? '★ #$rank' : '#$rank',
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          LeaderboardInitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(entry.displayName),
            accent: accent,
            size: avatarSize,
            profilePictureUrl: profilePictureUrl,
            highlightRing: isCurrentUser,
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: nameSize,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lv. ${entry.level}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.elixTextSecondary,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '${entry.totalXp} XP',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: xpSize,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          // Reserve identical badge slot so YOU never changes card height.
          SizedBox(
            height: compact ? 22 : 26,
            child: isCurrentUser
                ? const Align(
                    alignment: Alignment.bottomCenter,
                    child: LeaderboardYouBadge(compact: true),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
