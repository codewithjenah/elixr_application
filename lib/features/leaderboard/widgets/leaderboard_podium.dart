import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_podium_card.dart';

enum LeaderboardPodiumVariant { full, compact }

class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({
    super.key,
    required this.podium,
    required this.currentUserId,
    this.currentUserProfilePictureUrl,
    this.variant = LeaderboardPodiumVariant.full,
    this.onTapPlayer,
  });

  final List<LeaderboardEntry> podium;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final LeaderboardPodiumVariant variant;
  final void Function(LeaderboardEntry entry, int rank)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    if (podium.isEmpty) return const SizedBox.shrink();

    final slots = LeaderboardPresentation.podiumDisplayOrder(podium);
    final gap = variant == LeaderboardPodiumVariant.compact
        ? AppSpacing.sm
        : AppSpacing.md;

    Widget cardFor(({int rank, LeaderboardEntry entry}) slot) {
      final isCurrentUser = slot.entry.userId == currentUserId;
      return LeaderboardPodiumCard(
        rank: slot.rank,
        entry: slot.entry,
        isCurrentUser: isCurrentUser,
        profilePictureUrl: LeaderboardPresentation.profilePictureUrlFor(
          entry: slot.entry,
          isCurrentUser: isCurrentUser,
          currentUserProfilePictureUrl: currentUserProfilePictureUrl,
        ),
        variant: variant,
        onTap: onTapPlayer == null
            ? null
            : () => onTapPlayer!(slot.entry, slot.rank),
      );
    }

    Widget cardForRank(int rank, LeaderboardEntry entry) {
      final isCurrentUser = entry.userId == currentUserId;
      return LeaderboardPodiumCard(
        rank: rank,
        entry: entry,
        isCurrentUser: isCurrentUser,
        profilePictureUrl: LeaderboardPresentation.profilePictureUrlFor(
          entry: entry,
          isCurrentUser: isCurrentUser,
          currentUserProfilePictureUrl: currentUserProfilePictureUrl,
        ),
        variant: variant,
        onTap: onTapPlayer == null ? null : () => onTapPlayer!(entry, rank),
      );
    }

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Wide desktop: second | first | third
        if (width >= 720 && podium.length == 3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  flex: slots[i].rank == 1 ? 12 : 10,
                  child: cardFor(slots[i]),
                ),
              ],
            ],
          );
        }

        // Wide but fewer than 3 players
        if (width >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < podium.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  flex: i == 0 ? 12 : 10,
                  child: cardForRank(i + 1, podium[i]),
                ),
              ],
            ],
          );
        }

        // Medium: first above second | third
        if (width >= 480 && podium.length >= 2) {
          return Column(
            children: [
              cardForRank(1, podium[0]),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cardForRank(2, podium[1])),
                  if (podium.length > 2) ...[
                    SizedBox(width: gap),
                    Expanded(child: cardForRank(3, podium[2])),
                  ],
                ],
              ),
            ],
          );
        }

        // Narrow: vertical stack first → second → third
        return Column(
          children: [
            for (var i = 0; i < podium.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              cardForRank(i + 1, podium[i]),
            ],
          ],
        );
      },
    );

    if (variant == LeaderboardPodiumVariant.compact) {
      return body;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Performers',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        body,
      ],
    );
  }
}
