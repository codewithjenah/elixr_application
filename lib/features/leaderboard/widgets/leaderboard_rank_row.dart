import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';

class LeaderboardRankRow extends StatefulWidget {
  const LeaderboardRankRow({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  State<LeaderboardRankRow> createState() => _LeaderboardRankRowState();
}

class _LeaderboardRankRowState extends State<LeaderboardRankRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;
    final active = widget.isCurrentUser || _hovered;
    final avgScore = widget.entry.averageScore.toStringAsFixed(0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isCurrentUser
              ? AppColors.primary.withValues(
                  alpha: context.isDarkTheme ? 0.10 : 0.08,
                )
              : active
              ? panel
              : panel.withValues(alpha: context.isDarkTheme ? 0.92 : 1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isCurrentUser
                ? AppColors.primary.withValues(alpha: 0.65)
                : active
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.accent.withValues(alpha: 0.22),
            width: widget.isCurrentUser ? 1.4 : 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;

            return Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '#${widget.rank}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
                LeaderboardInitialsAvatar(
                  initials: LeaderboardPresentation.initialsFor(
                    widget.entry.displayName,
                  ),
                  accent: AppColors.accent,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.elixTextPrimary,
                          ),
                        ),
                      ),
                      if (widget.isCurrentUser) ...[
                        const SizedBox(width: 8),
                        const LeaderboardYouBadge(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Lv. ${widget.entry.level}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextSecondary,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${widget.entry.sessionsCompleted}',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text(
                      avgScore,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: Text(
                    '${widget.entry.totalXp} XP',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
