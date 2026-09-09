import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/shell/teacher_shell.dart';
import '../../core/theme/app_theme.dart';
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
                ElixPanelCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            FluentIcons.trophy,
                            size: 28,
                            color: Color(0xFFFF2FA8),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              challenge.title,
                              style: AppTheme.headingLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${challenge.movementName} · Best valid rubric score · Maximum 12',
                        style: AppTheme.bodySecondary,
                      ),
                    ],
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      children: [
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

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.userId});
  final List<ClassChallengeLeaderboardEntry> entries;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (var index = 0; index < entries.length; index++)
          SizedBox(
            width: 210,
            child: ElixPanelCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Text(
                    ['🥇', '🥈', '🥉'][index],
                    style: const TextStyle(fontSize: 30),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ProfileAvatarWidget(
                    initials: userInitials(entries[index].displayName),
                    networkImageUrl: entries[index].profilePictureUrl,
                    radius: 28,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    entries[index].displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headingMedium,
                  ),
                  if (entries[index].traineeId == userId)
                    const Text(
                      'You',
                      style: TextStyle(color: Color(0xFFFF2FA8)),
                    ),
                  Text(
                    '${entries[index].score}/12',
                    style: AppTheme.headingLarge,
                  ),
                ],
              ),
            ),
          ),
      ],
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
    return Container(
      key: Key('class_challenge_rank_$rank'),
      color: isYou ? const Color(0x18FF2FA8) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text('#$rank', style: AppTheme.headingMedium),
          ),
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
          SizedBox(
            width: 64,
            child: Text(
              '${entry.score}/12',
              textAlign: TextAlign.end,
              style: AppTheme.headingMedium,
            ),
          ),
        ],
      ),
    );
  }
}
