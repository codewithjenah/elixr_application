import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';

/// Breakpoints for ranking-row column visibility.
abstract final class LeaderboardRankRowLayout {
  static const mediumMin = 680.0;

  static bool showMetricColumns(double width) => width >= mediumMin;
}

/// Shared fixed column widths keep the header and every loaded page aligned.
///
/// Assessment V2 replaced the 0..100 session percentage with a 0..12 rubric
/// total, so the ranking table no longer exposes percentage score columns.
/// Ranking remains XP-based.
abstract final class LeaderboardRankColumns {
  static const double accentGutter = 3;
  static const double rank = 64;
  static const double sessions = 92;
  static const double xp = 116;
  static const EdgeInsets rowPadding = EdgeInsets.fromLTRB(16, 10, 16, 10);
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(16, 8, 16, 9);

  static Widget row({
    required Widget rank,
    required Widget player,
    required Widget sessions,
    required Widget xp,
  }) {
    return Row(
      children: [
        SizedBox(width: LeaderboardRankColumns.rank, child: rank),
        Expanded(child: player),
        SizedBox(width: LeaderboardRankColumns.sessions, child: sessions),
        SizedBox(width: LeaderboardRankColumns.xp, child: xp),
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
    this.period = LeaderboardPeriod.allTime,
    this.showDivider = false,
    this.onTap,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final LeaderboardPeriod period;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  State<LeaderboardRankRow> createState() => _LeaderboardRankRowState();
}

class _LeaderboardRankRowState extends State<LeaderboardRankRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final metrics = LeaderboardPresentation.metricsFor(
      widget.entry,
      widget.period,
    );
    final interactive = widget.onTap != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showDivider)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            color: context.elixBorder.withValues(alpha: 0.55),
          ),
        Tooltip(
          message: widget.entry.displayName,
          child: Semantics(
            button: interactive,
            label:
                'Rank ${widget.rank}, ${widget.entry.displayName}, '
                '${metrics.xp} XP',
            child: FocusableActionDetector(
              enabled: interactive,
              mouseCursor: interactive
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onTap?.call();
                    return null;
                  },
                ),
              },
              onShowHoverHighlight: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              onShowFocusHighlight: (value) {
                if (_focused != value) setState(() => _focused = value);
              },
              child: GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: double.infinity,
                  color: widget.isCurrentUser
                      ? AppColors.primary.withValues(
                          alpha: context.isDarkTheme ? 0.08 : 0.06,
                        )
                      : _hovered
                      ? context.elixCardSurface.withValues(
                          alpha: context.isDarkTheme ? 0.52 : 0.70,
                        )
                      : Colors.transparent,
                  child: Stack(
                    children: [
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
                            final medium =
                                LeaderboardRankRowLayout.showMetricColumns(
                                  width,
                                );

                            if (!medium) {
                              return _CompactRankRow(
                                rank: widget.rank,
                                entry: widget.entry,
                                isCurrentUser: widget.isCurrentUser,
                                profilePictureUrl: widget.profilePictureUrl,
                                metrics: metrics,
                              );
                            }

                            return LeaderboardRankColumns.row(
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
                              sessions: Text(
                                '${metrics.sessionsCompleted}',
                                textAlign: TextAlign.end,
                                style: _metricStyle(context),
                              ),
                              xp: Text(
                                '${metrics.xp} XP',
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
                      if (_focused)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.85,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
  const LeaderboardRankingsHeaderRow({
    super.key,
    this.period = LeaderboardPeriod.allTime,
  });

  final LeaderboardPeriod period;

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

                return LeaderboardRankColumns.row(
                  rank: Text('Rank', style: style),
                  player: Text('Player', style: style),
                  sessions: Text(
                    'Sessions',
                    textAlign: TextAlign.end,
                    style: style,
                  ),
                  xp: Text(
                    LeaderboardPresentation.periodXpHeading(period),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
          size: 34,
          profilePictureUrl: profilePictureUrl,
          equippedBorderId: entry.equippedBorderId,
          highlightRing: isCurrentUser,
          animateBorder: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _PlayerName(displayName: entry.displayName)),
                  if (isCurrentUser) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const LeaderboardYouBadge(compact: true),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Lv. ${entry.level}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
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
    required this.metrics,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final LeaderboardPeriodMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
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
        LeaderboardInitialsAvatar(
          initials: LeaderboardPresentation.initialsFor(entry.displayName),
          accent: AppColors.accent,
          size: 34,
          profilePictureUrl: profilePictureUrl,
          equippedBorderId: entry.equippedBorderId,
          highlightRing: isCurrentUser,
          animateBorder: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _PlayerName(displayName: entry.displayName)),
                  if (isCurrentUser) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const LeaderboardYouBadge(compact: true),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Lv. ${entry.level} • ${metrics.sessionsCompleted} sessions',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: Text(
              '${metrics.xp} XP',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Text(
      displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.elixTextPrimary,
      ),
    );
  }
}
