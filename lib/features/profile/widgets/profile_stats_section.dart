import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/public_profile_summary.dart';
import '../../history/history_format.dart';
import 'profile_section_card.dart';

/// Separates a confirmed absence from asynchronous rank resolution failures.
enum ProfileRankState { resolving, ranked, unranked, unavailable }

class ProfileStatsSection extends StatelessWidget {
  const ProfileStatsSection({
    super.key,
    required this.leaderboardEntry,
    this.rank,
    this.rankState,
    this.summary,
  });

  final LeaderboardEntry? leaderboardEntry;
  final int? rank;
  final ProfileRankState? rankState;
  final PublicProfileSummary? summary;

  static const _fiveColumnMinWidth = 1050.0;
  static const _threeColumnMinWidth = 700.0;

  @override
  Widget build(BuildContext context) {
    final entry = leaderboardEntry;
    if (entry == null) return const SizedBox.shrink();

    final effectiveRankState = rank != null
        ? ProfileRankState.ranked
        // Keep the established public-profile contract for callers that do
        // not provide the richer asynchronous state. Teacher Details passes
        // it explicitly and never uses this fallback while resolving.
        : rankState ?? ProfileRankState.unranked;
    final rankLabel = switch (effectiveRankState) {
      ProfileRankState.ranked => '#$rank',
      ProfileRankState.unranked => 'Unranked',
      ProfileRankState.unavailable => 'Unavailable',
      ProfileRankState.resolving => '—',
    };
    final practiceTime = formatTrainingDuration(
      summary?.totalDurationSeconds ?? 0,
    );

    final milestone = context.elixColors.milestone;
    final tiles = [
      _StatData(
        label: 'Rank',
        value: rankLabel,
        valueColor: rank == 1 ? milestone : null,
      ),
      _StatData(label: 'Sessions', value: '${entry.sessionsCompleted}'),
      _StatData(
        label: 'Average Score',
        value: entry.averageScore.toStringAsFixed(0),
      ),
      _StatData(
        label: 'Best Score',
        value: '${entry.bestScore}',
        valueColor: entry.bestScore > 0 ? milestone : null,
      ),
      _StatData(label: 'Practice Time', value: practiceTime),
    ];

    return ProfileSectionCard(
      title: 'Player Stats',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= _fiveColumnMinWidth
              ? 5
              : width >= _threeColumnMinWidth
              ? 3
              : 2;
          const gap = AppSpacing.md;
          final tileWidth = (width - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final tile in tiles)
                SizedBox(
                  width: tileWidth,
                  child: _StatTile(
                    label: tile.label,
                    value: tile.value,
                    valueColor: tile.valueColor,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatData {
  const _StatData({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.metric(
              context,
              color: valueColor ?? context.elixTextPrimary,
            ).copyWith(fontSize: 20, height: 1.1),
          ),
        ],
      ),
    );
  }
}
