import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';
import 'leaderboard_podium.dart';

class LeaderboardPodiumCard extends StatefulWidget {
  const LeaderboardPodiumCard({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
    this.profilePictureUrl,
    this.period = LeaderboardPeriod.allTime,
    this.variant = LeaderboardPodiumVariant.full,
    this.onTap,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final String? profilePictureUrl;
  final LeaderboardPeriod period;
  final LeaderboardPodiumVariant variant;
  final VoidCallback? onTap;

  @override
  State<LeaderboardPodiumCard> createState() => _LeaderboardPodiumCardState();
}

class _LeaderboardPodiumCardState extends State<LeaderboardPodiumCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isFirst = widget.rank == 1;
    final compact = widget.variant == LeaderboardPodiumVariant.compact;
    final accent = LeaderboardRankStyle.medalForRank(widget.rank);
    final metrics = LeaderboardPresentation.metricsFor(
      widget.entry,
      widget.period,
    );
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;
    final interactive = widget.onTap != null;
    final rankLabel = widget.rank >= 1 && widget.rank <= 3
        ? 'Top ${widget.rank}'
        : '#${widget.rank}';
    final avatarSize = compact ? (isFirst ? 48.0 : 44.0) : 54.0;

    return Tooltip(
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
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: double.infinity,
              height: compact
                  ? LeaderboardPodiumLayout.compactCardHeight
                  : LeaderboardPodiumLayout.fullCardHeight,
              padding: EdgeInsets.all(compact ? 12 : AppSpacing.md),
              decoration: BoxDecoration(
                color: _hovered
                    ? Color.lerp(
                        panel,
                        accent,
                        context.isDarkTheme ? 0.045 : 0.025,
                      )
                    : panel,
                borderRadius: BorderRadius.circular(compact ? 14 : 16),
                border: Border.all(
                  color: _focused
                      ? AppColors.primary.withValues(alpha: 0.90)
                      : accent.withValues(alpha: isFirst ? 0.62 : 0.28),
                  width: _focused || isFirst ? 1.5 : 1,
                ),
                boxShadow: isFirst
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 0,
                    child: Container(
                      height: isFirst ? 3 : 2,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isFirst ? 0.82 : 0.48),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      SizedBox(
                        height: compact ? 22 : 24,
                        child: Center(
                          child: Text(
                            isFirst ? '★ $rankLabel' : rankLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 11 : 12,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
                      LeaderboardInitialsAvatar(
                        initials: LeaderboardPresentation.initialsFor(
                          widget.entry.displayName,
                        ),
                        accent: accent,
                        size: avatarSize,
                        profilePictureUrl: widget.profilePictureUrl,
                        equippedBorderId: widget.entry.equippedBorderId,
                        highlightRing: widget.isCurrentUser,
                        animateBorder: true,
                      ),
                      SizedBox(height: compact ? 6 : AppSpacing.sm),
                      SizedBox(
                        height: 20,
                        width: double.infinity,
                        child: Text(
                          widget.entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w700,
                            color: context.elixTextPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SizedBox(
                        height: 16,
                        child: Text(
                          'Lv. ${widget.entry.level}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        LeaderboardPresentation.periodXpHeading(widget.period),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${metrics.xp} XP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.w800,
                          color: isFirst ? accent : AppColors.primarySoft,
                        ),
                      ),
                      SizedBox(
                        height: compact ? 18 : 22,
                        child: widget.isCurrentUser
                            ? const Align(
                                alignment: Alignment.bottomCenter,
                                child: LeaderboardYouBadge(compact: true),
                              )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
