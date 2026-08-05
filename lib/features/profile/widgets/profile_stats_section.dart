import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/public_profile_summary.dart';
import '../../history/history_format.dart';

class ProfileStatsSection extends StatelessWidget {
  const ProfileStatsSection({
    super.key,
    required this.leaderboardEntry,
    this.rank,
    this.summary,
  });

  final LeaderboardEntry? leaderboardEntry;
  final int? rank;
  final PublicProfileSummary? summary;

  @override
  Widget build(BuildContext context) {
    final entry = leaderboardEntry;
    if (entry == null) return const SizedBox.shrink();

    final rankLabel = rank != null ? '#$rank' : 'Unranked';
    final practiceTime = formatTrainingDuration(
      summary?.totalDurationSeconds ?? 0,
    );

    return _Panel(
      title: 'Player Stats',
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          _StatTile(label: 'Rank', value: rankLabel),
          _StatTile(label: 'Sessions', value: '${entry.sessionsCompleted}'),
          _StatTile(
            label: 'Average Score',
            value: entry.averageScore.toStringAsFixed(0),
          ),
          _StatTile(label: 'Best Score', value: '${entry.bestScore}'),
          _StatTile(label: 'Practice Time', value: practiceTime),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

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
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.elixTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
