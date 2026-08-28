import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
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
    this.period = LeaderboardPeriod.allTime,
    this.onTapPlayer,
  });

  final List<({int rank, LeaderboardEntry entry})> rows;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final Widget footer;
  final LeaderboardPeriod period;
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
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: context.isDarkTheme ? 0.12 : 0.05,
            ),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
            child: const ElixSectionHeader(heading: 'Rankings'),
          ),
          Container(
            color: context.elixCardSurface.withValues(
              alpha: context.isDarkTheme ? 0.42 : 0.62,
            ),
            child: Column(
              children: [
                LeaderboardRankingsHeaderRow(period: period),
                Container(height: 1, color: context.elixBorder),
              ],
            ),
          ),
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
              period: period,
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
