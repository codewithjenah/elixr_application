import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
import '../leaderboard_presentation.dart';
import 'leaderboard_podium_card.dart';

enum LeaderboardPodiumVariant { full, compact }

abstract final class LeaderboardPodiumLayout {
  static const double fullWideMin = 860;
  static const double compactWideMin = 720;
  static const double mediumMin = 560;
  static const double fullCardHeight = 296;
  static const double compactCardHeight = 276;
}

class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({
    super.key,
    required this.podium,
    required this.currentUserId,
    this.currentUserProfilePictureUrl,
    this.period = LeaderboardPeriod.allTime,
    this.variant = LeaderboardPodiumVariant.full,
    this.onTapPlayer,
  });

  final List<LeaderboardEntry> podium;
  final String? currentUserId;
  final String? currentUserProfilePictureUrl;
  final LeaderboardPeriod period;
  final LeaderboardPodiumVariant variant;
  final void Function(LeaderboardEntry entry, int rank)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    if (podium.isEmpty) return const SizedBox.shrink();

    final displaySlots = LeaderboardPresentation.podiumDisplayOrder(podium);
    final gap = variant == LeaderboardPodiumVariant.compact
        ? AppSpacing.sm
        : AppSpacing.md;
    final cardHeight = variant == LeaderboardPodiumVariant.compact
        ? LeaderboardPodiumLayout.compactCardHeight
        : LeaderboardPodiumLayout.fullCardHeight;

    Widget cardFor(({int rank, LeaderboardEntry entry}) slot) {
      final isCurrentUser = slot.entry.userId == currentUserId;
      return SizedBox(
        key: ValueKey('leaderboard-podium-${slot.entry.userId}'),
        height: cardHeight,
        child: LeaderboardPodiumCard(
          rank: slot.rank,
          entry: slot.entry,
          isCurrentUser: isCurrentUser,
          profilePictureUrl: LeaderboardPresentation.profilePictureUrlFor(
            entry: slot.entry,
            isCurrentUser: isCurrentUser,
            currentUserProfilePictureUrl: currentUserProfilePictureUrl,
          ),
          period: period,
          variant: variant,
          onTap: onTapPlayer == null
              ? null
              : () => onTapPlayer!(slot.entry, slot.rank),
        ),
      );
    }

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wideMin = variant == LeaderboardPodiumVariant.compact
            ? LeaderboardPodiumLayout.compactWideMin
            : LeaderboardPodiumLayout.fullWideMin;

        if (width >= wideMin) {
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < displaySlots.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: cardFor(displaySlots[i])),
              ],
            ],
          );
          if (displaySlots.length == 3) return row;

          final thirdWidth = (width - (gap * 2)) / 3;
          final partialWidth =
              (thirdWidth * displaySlots.length) +
              (gap * (displaySlots.length - 1));
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: partialWidth),
              child: row,
            ),
          );
        }

        // Medium windows make the champion the clear first read, then place
        // second and third in an equal two-column row.
        if (width >= LeaderboardPodiumLayout.mediumMin && podium.length >= 2) {
          final first = (rank: 1, entry: podium[0]);
          final second = (rank: 2, entry: podium[1]);
          final third = podium.length > 2 ? (rank: 3, entry: podium[2]) : null;
          return Column(
            children: [
              cardFor(first),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cardFor(second)),
                  if (third != null) ...[
                    SizedBox(width: gap),
                    Expanded(child: cardFor(third)),
                  ],
                ],
              ),
            ],
          );
        }

        // Narrow windows retain natural rank order and never compress cards.
        return Column(
          children: [
            for (var i = 0; i < podium.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              cardFor((rank: i + 1, entry: podium[i])),
            ],
          ],
        );
      },
    );

    if (variant == LeaderboardPodiumVariant.compact) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LeaderboardPresentation.periodTopThreeHeading(period),
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
