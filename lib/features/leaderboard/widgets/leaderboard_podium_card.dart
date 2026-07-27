import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_identity.dart';

const _silver = Color(0xFFB8C0CC);
const _bronze = Color(0xFFCD7F32);

class LeaderboardPodiumCard extends StatelessWidget {
  const LeaderboardPodiumCard({
    super.key,
    required this.rank,
    required this.entry,
    required this.isCurrentUser,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  Color get _accent {
    switch (rank) {
      case 1:
        return AppColors.warning;
      case 2:
        return _silver;
      case 3:
        return _bronze;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final accent = _accent;
    final panel = context.isDarkTheme
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, isFirst ? 18 : 14, 14, 14),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primary.withValues(alpha: 0.7)
              : accent.withValues(alpha: isFirst ? 0.55 : 0.35),
          width: isCurrentUser || isFirst ? 1.6 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: isFirst ? 0.18 : 0.10),
            panel.withValues(alpha: 0.2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isFirst ? 0.18 : 0.08),
            blurRadius: isFirst ? 22 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isFirst)
            const Text('👑', style: TextStyle(fontSize: 18))
          else
            Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          if (isFirst) const SizedBox(height: 4),
          if (isFirst)
            Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          const SizedBox(height: 8),
          LeaderboardInitialsAvatar(
            initials: LeaderboardPresentation.initialsFor(entry.displayName),
            accent: accent,
            size: isFirst ? 48 : 40,
          ),
          const SizedBox(height: 10),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 15 : 13,
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
          const SizedBox(height: 8),
          Text(
            '${entry.totalXp} XP',
            style: TextStyle(
              fontSize: isFirst ? 16 : 14,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(height: 8),
            const LeaderboardYouBadge(),
          ],
        ],
      ),
    );
  }
}
