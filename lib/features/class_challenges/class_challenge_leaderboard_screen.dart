import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/shell/teacher_shell.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/class_challenge.dart';
import '../../data/repositories/class_challenge_repository.dart';
import '../../services/auth_service.dart';

class ClassChallengeLeaderboardScreen extends StatelessWidget {
  const ClassChallengeLeaderboardScreen({
    super.key,
    required this.groupId,
    required this.challengeId,
    required this.teacherView,
  });

  final String groupId;
  final String challengeId;
  final bool teacherView;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ClassChallengeRepository>();
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    final body = FutureBuilder<ClassChallenge?>(
      future: repository.getChallenge(challengeId: challengeId),
      builder: (context, challengeSnapshot) {
        if (challengeSnapshot.hasError) {
          return const ElixStatusPanel(
            title: 'Leaderboard unavailable',
            message: 'You may no longer have access to this classroom.',
            isError: true,
          );
        }
        if (!challengeSnapshot.hasData) {
          return const Center(child: ProgressRing());
        }
        final challenge = challengeSnapshot.data;
        if (challenge == null || challenge.groupId != groupId) {
          return const ElixStatusPanel(
            title: 'Challenge not found',
            message: 'This challenge is not available in this classroom.',
            isError: true,
          );
        }
        return StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
          stream: repository.watchLeaderboard(
            challengeId: challenge.id,
            groupId: challenge.groupId,
            teacherId: challenge.teacherId,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const ElixStatusPanel(
                title: 'Could not load rankings',
                message: 'Check your connection and try again.',
                isError: true,
              );
            }
            if (!snapshot.hasData) return const Center(child: ProgressRing());
            final entries = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElixBackButton(
                  label: 'Challenges',
                  tooltip: 'Back to classroom challenges',
                  semanticLabel: 'Back to classroom challenges',
                  onPressed: () => context.go(
                    teacherView
                        ? '${AppRoutePaths.teacherGroup(groupId)}?tab=challenges'
                        : '${AppRoutePaths.teacherAccessClass(groupId)}?tab=challenges',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _LeaderboardHero(challenge: challenge, entryCount: entries.length),
                const SizedBox(height: AppSpacing.md),
                if (entries.isEmpty)
                  const ElixStatusPanel(
                    key: Key('class_challenge_leaderboard_empty'),
                    icon: FluentIcons.trophy,
                    title: 'The leaderboard is open',
                    message:
                        'No valid challenge results have been submitted yet.',
                  )
                else ...[
                  _Podium(entries: entries.take(3).toList(), userId: userId),
                  const SizedBox(height: AppSpacing.md),
                  ElixPanelCard(
                    variant: ElixPanelVariant.elevated,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        const _RankListLabel(),
                        for (var index = 0; index < entries.length; index++)
                          _RankRow(
                            rank: index + 1,
                            entry: entries[index],
                            isYou: entries[index].traineeId == userId,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );

    if (teacherView) {
      return TeacherScaffoldPage(
        header: const ElixEditorialPageHeader(
          heading: 'Class Leaderboard',
          eyebrow: 'CLASS CHALLENGE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: body,
      );
    }
    return ElixScaffoldPage(
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ElixEditorialPageHeader(
              heading: 'Class Leaderboard',
              eyebrow: 'CLASS CHALLENGE',
              variant: ElixEditorialHeaderVariant.compact,
            ),
            Padding(padding: const EdgeInsets.all(AppSpacing.md), child: body),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardHero extends StatelessWidget {
  const _LeaderboardHero({required this.challenge, required this.entryCount});

  final ClassChallenge challenge;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return ElixPanelCard(
      variant: ElixPanelVariant.hero,
      accent: colors.brandPrimary,
      showAccentBar: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.milestone.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(ElixRadius.control),
              border: Border.all(color: colors.milestone.withValues(alpha: 0.4)),
            ),
            child: Icon(FluentIcons.trophy2, color: colors.milestone, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ElixEyebrow(label: 'CHALLENGE RANKINGS'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  challenge.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.pageTitle(context, color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${challenge.movementName} · Best valid score · Maximum 12',
                  style: AppTheme.supporting(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _EntryCount(count: entryCount),
        ],
      ),
    );
  }
}

class _EntryCount extends StatelessWidget {
  const _EntryCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smPlus,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceBase.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(ElixRadius.control),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: [
          Text('$count', style: AppTheme.compactMetric()),
          Text(
            count == 1 ? 'PLAYER' : 'PLAYERS',
            style: AppTheme.caption.copyWith(
              color: colors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.userId});
  final List<ClassChallengeLeaderboardEntry> entries;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final orderedEntries = entries.length == 3
        ? [entries[1], entries[0], entries[2]]
        : entries;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final entry in orderedEntries)
          SizedBox(
            width: 220,
            child: _PodiumCard(
              entry: entry,
              rank: entries.indexOf(entry) + 1,
              isYou: entry.traineeId == userId,
            ),
          ),
      ],
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.entry,
    required this.rank,
    required this.isYou,
  });

  final ClassChallengeLeaderboardEntry entry;
  final int rank;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final medal = switch (rank) {
      1 => colors.milestone,
      2 => colors.textSecondary,
      _ => colors.warning,
    };
    return ElixPanelCard(
      variant: rank == 1 ? ElixPanelVariant.hero : ElixPanelVariant.elevated,
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      borderColor: medal.withValues(alpha: rank == 1 ? 0.58 : 0.3),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: medal.withValues(alpha: 0.48)),
            ),
            child: Text(
              '#$rank',
              style: AppTheme.label(color: medal).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ProfileAvatarWidget(
            initials: userInitials(entry.displayName),
            networkImageUrl: entry.profilePictureUrl,
            radius: 30,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.cardTitle(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (isYou)
            ElixPill(
              text: 'YOU',
              color: colors.brandSecondary,
              compact: true,
            )
          else
            Text(
              'Best attempt',
              style: AppTheme.caption.copyWith(color: colors.textMuted),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${entry.score}/12',
            style: AppTheme.metric(context, color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _RankListLabel extends StatelessWidget {
  const _RankListLabel();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.mdPlus,
      AppSpacing.xs,
      AppSpacing.mdPlus,
      AppSpacing.sm,
    ),
    child: Text(
      'ALL RANKINGS',
      style: AppTheme.eyebrow(color: context.elixColors.textMuted),
    ),
  );
}

class _RankMarker extends StatelessWidget {
  const _RankMarker({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final tone = rank == 1
        ? colors.milestone
        : rank == 2
        ? colors.textSecondary
        : rank == 3
        ? colors.warning
        : colors.textMuted;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: 0.13),
      ),
      child: Text(
        '$rank',
        style: AppTheme.label(color: tone).copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.brandSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ElixRadius.pill),
      ),
      child: Text(
        '$score/12',
        style: AppTheme.label(color: colors.textPrimary).copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.entry,
    required this.isYou,
  });
  final int rank;
  final ClassChallengeLeaderboardEntry entry;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        key: Key('class_challenge_rank_$rank'),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.smPlus,
        ),
        decoration: BoxDecoration(
          color: isYou
              ? context.elixColors.brandPrimary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(ElixRadius.control),
          border: Border.all(
            color: isYou
                ? context.elixColors.brandPrimary.withValues(alpha: 0.42)
                : Colors.transparent,
          ),
        ),
        child: constraints.maxWidth < 520
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RankMarker(rank: rank),
                  const SizedBox(width: AppSpacing.sm),
                  ProfileAvatarWidget(
                    initials: userInitials(entry.displayName),
                    networkImageUrl: entry.profilePictureUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.displayName}${isYou ? ' · You' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Attempt ${entry.bestAttemptNumber}',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ScorePill(score: entry.score),
                ],
              )
            : Row(
                children: [
                  _RankMarker(rank: rank),
                  const SizedBox(width: AppSpacing.sm),
                  ProfileAvatarWidget(
                    initials: userInitials(entry.displayName),
                    networkImageUrl: entry.profilePictureUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${entry.displayName}${isYou ? '  ·  You' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('Attempt ${entry.bestAttemptNumber}'),
                  ),
                  _ScorePill(score: entry.score),
                ],
              ),
      ),
    );
  }
}
