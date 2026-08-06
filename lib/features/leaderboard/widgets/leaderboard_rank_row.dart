import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';

/// Breakpoints for ranking-row column visibility.
abstract final class LeaderboardRankRowLayout {
  static const wideMin = 980.0;
  static const mediumMin = 720.0;

  static bool showBestScore(double width) => width >= wideMin;
  static bool showMetricColumns(double width) => width >= mediumMin;
}

/// Shared fixed column widths so header and data rows stay aligned.
abstract final class LeaderboardRankColumns {
  static const double accentGutter = 3;
  static const double rank = 56;
  static const double level = 72;
  static const double sessions = 84;
  static const double avgScore = 88;
  static const double bestScore = 88;
  static const double totalXp = 96;
  static const EdgeInsets rowPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(12, 4, 12, 8);

  static Widget row({
    required bool showBestScore,
    required Widget rank,
    required Widget player,
    required Widget level,
    required Widget sessions,
    required Widget avgScore,
    required Widget bestScore,
    required Widget totalXp,
  }) {
    return Row(
      children: [
        SizedBox(width: LeaderboardRankColumns.rank, child: rank),
        Expanded(child: player),
        SizedBox(width: LeaderboardRankColumns.level, child: level),
        SizedBox(width: LeaderboardRankColumns.sessions, child: sessions),
        SizedBox(width: LeaderboardRankColumns.avgScore, child: avgScore),
        if (showBestScore)
          SizedBox(width: LeaderboardRankColumns.bestScore, child: bestScore),
        SizedBox(width: LeaderboardRankColumns.totalXp, child: totalXp),
      ],
    );
  }
}

class LeaderboardRankRow extends StatefulWidget {
  const LeaderboardRankRow({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
    this.profilePictureUrl,
    this.showDivider = false,
    this.onTap,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  State<LeaderboardRankRow> createState() => _LeaderboardRankRowState();
}

class _LeaderboardRankRowState extends State<LeaderboardRankRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final avgScore = widget.entry.averageScore.toStringAsFixed(0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showDivider)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: context.elixBorder.withValues(alpha: 0.55),
          ),
        MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: double.infinity,
              decoration: BoxDecoration(
                color: widget.isCurrentUser
                    ? AppColors.primary.withValues(
                        alpha: context.isDarkTheme ? 0.08 : 0.06,
                      )
                    : _hovered
                    ? context.elixCardSurface.withValues(
                        alpha: context.isDarkTheme ? 0.55 : 0.7,
                      )
                    : Colors.transparent,
              ),
              child: Stack(
                children: [
                  // Fixed gutter so the YOU accent never shifts columns.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: LeaderboardRankColumns.accentGutter,
                    child: ColoredBox(
                      color: widget.isCurrentUser
                          ? AppColors.primary.withValues(alpha: 0.85)
                          : Colors.transparent,
                    ),
                  ),
                  Padding(
                    padding: LeaderboardRankColumns.rowPadding.copyWith(
                      left:
                          LeaderboardRankColumns.rowPadding.left +
                          LeaderboardRankColumns.accentGutter,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final wide = LeaderboardRankRowLayout.showBestScore(
                          width,
                        );
                        final medium =
                            LeaderboardRankRowLayout.showMetricColumns(width);

                        if (!medium) {
                          return _CompactRankRow(
                            rank: widget.rank,
                            entry: widget.entry,
                            isCurrentUser: widget.isCurrentUser,
                            profilePictureUrl: widget.profilePictureUrl,
                            avgScore: avgScore,
                          );
                        }

                        return LeaderboardRankColumns.row(
                          showBestScore: wide,
                          rank: Text(
                            '#${widget.rank}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: context.elixTextSecondary,
                            ),
                          ),
                          player: _PlayerCell(
                            entry: widget.entry,
                            isCurrentUser: widget.isCurrentUser,
                            profilePictureUrl: widget.profilePictureUrl,
                          ),
                          level: Text(
                            'Lv. ${widget.entry.level}',
                            textAlign: TextAlign.end,
                            style: _metricStyle(context),
                          ),
                          sessions: Text(
                            '${widget.entry.sessionsCompleted}',
                            textAlign: TextAlign.end,
                            style: _metricStyle(context),
                          ),
                          avgScore: Text(
                            avgScore,
                            textAlign: TextAlign.end,
                            style: _metricStyle(context),
                          ),
                          bestScore: Text(
                            '${widget.entry.bestScore}',
                            textAlign: TextAlign.end,
                            style: _metricStyle(context),
                          ),
                          totalXp: Text(
                            '${widget.entry.totalXp} XP',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _metricStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: context.elixTextSecondary,
    );
  }
}

class LeaderboardRankingsHeaderRow extends StatelessWidget {
  const LeaderboardRankingsHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: context.elixTextSecondary,
    );

    return Row(
      children: [
        const SizedBox(width: LeaderboardRankColumns.accentGutter),
        Expanded(
          child: Padding(
            padding: LeaderboardRankColumns.headerPadding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (!LeaderboardRankRowLayout.showMetricColumns(width)) {
                  return const SizedBox.shrink();
                }

                final wide = LeaderboardRankRowLayout.showBestScore(width);

                return LeaderboardRankColumns.row(
                  showBestScore: wide,
                  rank: Text('Rank', style: style),
                  player: Text('Player', style: style),
                  level: Text('Level', textAlign: TextAlign.end, style: style),
                  sessions: Text(
                    'Sessions',
                    textAlign: TextAlign.end,
                    style: style,
                  ),
                  avgScore: Text(
                    'Avg Score',
                    textAlign: TextAlign.end,
                    style: style,
                  ),
                  bestScore: Text(
                    'Best Score',
                    textAlign: TextAlign.end,
                    style: style,
                  ),
                  totalXp: Text(
                    'Total XP',
                    textAlign: TextAlign.end,
                    style: style,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerCell extends StatelessWidget {
  const _PlayerCell({
    required this.entry,
    required this.isCurrentUser,
    this.profilePictureUrl,
  });

  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        LeaderboardInitialsAvatar(
          initials: LeaderboardPresentation.initialsFor(entry.displayName),
          accent: AppColors.accent,
          size: 32,
          profilePictureUrl: profilePictureUrl,
          equippedBorderId: entry.equippedBorderId,
          highlightRing: isCurrentUser,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
        ),
        if (isCurrentUser) ...[
          const SizedBox(width: 8),
          const LeaderboardYouBadge(compact: true),
        ],
      ],
    );
  }
}

class _CompactRankRow extends StatelessWidget {
  const _CompactRankRow({
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
    required this.profilePictureUrl,
    required this.avgScore,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final String avgScore;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.elixTextSecondary,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LeaderboardInitialsAvatar(
                    initials: LeaderboardPresentation.initialsFor(
                      entry.displayName,
                    ),
                    accent: AppColors.accent,
                    size: 32,
                    profilePictureUrl: profilePictureUrl,
                    equippedBorderId: entry.equippedBorderId,
                    highlightRing: isCurrentUser,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const LeaderboardYouBadge(compact: true),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Lv. ${entry.level} • ${entry.sessionsCompleted} sessions • '
                '$avgScore avg',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${entry.totalXp} XP',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
