import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_rank_row.dart';

/// Cohesive rankings panel: title, optional column headers, rows, and footer.
class LeaderboardRankingsSection extends StatelessWidget {
  const LeaderboardRankingsSection({
    super.key,
    required this.rows,
    required this.currentUserId,
    this.currentUserProfilePictureUrl,
    required this.footer,
    this.onTapPlayer,
  });

  final List<({int rank, LeaderboardEntry entry})> rows;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final Widget footer;
  final void Function(LeaderboardEntry entry, int rank)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accent.withValues(
            alpha: context.isDarkTheme ? 0.22 : 0.16,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              'Rankings',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
          ),
          LeaderboardRankingsHeaderRow(),
          for (var i = 0; i < rows.length; i++)
            LeaderboardRankRow(
              rank: rows[i].rank,
              entry: rows[i].entry,
              isCurrentUser: rows[i].entry.userId == currentUserId,
              profilePictureUrl: LeaderboardPresentation.profilePictureUrlFor(
                entry: rows[i].entry,
                isCurrentUser: rows[i].entry.userId == currentUserId,
                currentUserProfilePictureUrl: currentUserProfilePictureUrl,
              ),
              showDivider: i > 0,
              onTap: onTapPlayer == null
                  ? null
                  : () => onTapPlayer!(rows[i].entry, rows[i].rank),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: footer,
          ),
        ],
      ),
    );
  }
}
