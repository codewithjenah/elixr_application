import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_podium_card.dart';

class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({
    super.key,
    required this.podium,
    required this.currentUserId,
  });

  final List<LeaderboardEntry> podium;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (podium.isEmpty) return const SizedBox.shrink();

    final slots = LeaderboardPresentation.podiumDisplayOrder(podium);

    Widget cardForRank(int rank, LeaderboardEntry entry) {
      return LeaderboardPodiumCard(
        rank: rank,
        entry: entry,
        isCurrentUser: entry.userId == currentUserId,
      );
    }

    Widget cardForSlot(({int rank, LeaderboardEntry entry}) slot) {
      return cardForRank(slot.rank, slot.entry);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 720 && podium.length == 3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: slots[i].rank == 1 ? 12 : 10,
                  child: cardForSlot(slots[i]),
                ),
              ],
            ],
          );
        }
        if (width >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < podium.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: i == 0 ? 12 : 10,
                  child: cardForRank(i + 1, podium[i]),
                ),
              ],
            ],
          );
        }
        if (width >= 480 && podium.length >= 2) {
          return Column(
            children: [
              cardForRank(1, podium[0]),
              if (podium.length > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: cardForRank(2, podium[1])),
                    if (podium.length > 2) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: cardForRank(3, podium[2])),
                    ],
                  ],
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < podium.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cardForRank(i + 1, podium[i]),
            ],
          ],
        );
      },
    );
  }
}
