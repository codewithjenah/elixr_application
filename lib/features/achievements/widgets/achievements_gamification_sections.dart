import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/gamification_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/achievement.dart';
import '../../../data/models/daily_quest.dart';
import '../../../data/models/profile_border.dart';
import '../../dashboard/dashboard_quests.dart';

class ReadyToClaimSection extends StatelessWidget {
  const ReadyToClaimSection({
    super.key,
    required this.quests,
    required this.achievements,
    required this.loadingQuests,
    required this.questLoadError,
    required this.claimingQuestIds,
    required this.claimingAchievementId,
    required this.onClaimQuest,
    required this.onClaimAchievement,
    required this.onRetryQuests,
  });

  final List<DashboardQuest> quests;
  final List<AchievementViewData> achievements;
  final bool loadingQuests;
  final String? questLoadError;
  final Set<String> claimingQuestIds;
  final String? claimingAchievementId;
  final ValueChanged<String> onClaimQuest;
  final ValueChanged<String> onClaimAchievement;
  final VoidCallback onRetryQuests;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ready_to_claim_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(
          icon: FluentIcons.giftbox_open,
          title: 'Ready to claim',
          subtitle: 'Collect completed quest XP and achievement rewards.',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (loadingQuests)
          const _LoadingState()
        else if (questLoadError != null)
          _LoadErrorState(onRetry: onRetryQuests)
        else if (quests.isEmpty && achievements.isEmpty)
          const _EmptyClaimState()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              const gap = AppSpacing.sm;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final quest in quests)
                    SizedBox(
                      width: width,
                      child: _ClaimableQuestCard(
                        quest: quest,
                        claiming: claimingQuestIds.contains(quest.id),
                        onClaim: () => onClaimQuest(quest.id),
                      ),
                    ),
                  for (final achievement in achievements)
                    SizedBox(
                      width: width,
                      child: _ClaimableAchievementCard(
                        view: achievement,
                        claiming:
                            claimingAchievementId == achievement.definition.id,
                        onClaim: () =>
                            onClaimAchievement(achievement.definition.id),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class HowToEarnXpSection extends StatelessWidget {
  const HowToEarnXpSection({super.key});

  @override
  Widget build(BuildContext context) {
    final sources = <_XpSource>[
      const _XpSource(
        label: 'Practice session',
        value: GamificationRules.xpPerSession,
        detail: 'Complete an eligible official practice session.',
        color: AppColors.accent,
        icon: FluentIcons.play_solid,
      ),
      for (final tier in QuestTier.values)
        _XpSource(
          label: '${tier.label} quest',
          value: tier.xp,
          detail:
              'Complete and claim a ${tier.label.toLowerCase()} Daily Quest.',
          color: _tierColor(tier),
          icon: FluentIcons.checkbox_composite,
        ),
    ];

    return Container(
      key: const Key('how_to_earn_xp_section'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixColors.surfaceRaised.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(
            icon: FluentIcons.lightning_bolt,
            title: 'How to earn XP',
            subtitle:
                'Complete practice sessions and claim Daily Quests to increase your level.',
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              const gap = AppSpacing.sm;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final source in sources)
                    SizedBox(
                      width: width,
                      child: _XpSourceCard(source: source),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.headingMedium.copyWith(
                  color: context.elixTextPrimary,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClaimableQuestCard extends StatelessWidget {
  const _ClaimableQuestCard({
    required this.quest,
    required this.claiming,
    required this.onClaim,
  });

  final DashboardQuest quest;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(quest.tier);
    return Container(
      key: Key('ready_quest_${quest.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.elixColors.surfaceRaised.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RewardTypePill(label: quest.tier.label, color: color),
              const SizedBox(width: 7),
              Text(
                'DAILY QUEST',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            quest.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.elixTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reward: +${quest.xp} XP',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: 30,
                child: Button(
                  onPressed: claiming ? null : onClaim,
                  child: claiming
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('Claim'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimableAchievementCard extends StatelessWidget {
  const _ClaimableAchievementCard({
    required this.view,
    required this.claiming,
    required this.onClaim,
  });

  final AchievementViewData view;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final definition = view.definition;
    final border = profileBorderById(definition.rewardBorderId);
    return Container(
      key: Key('ready_achievement_${definition.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.elixColors.surfaceRaised.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: context.elixColors.milestone.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RewardTypePill(
            label: 'Achievement',
            color: context.elixColors.milestone,
          ),
          const SizedBox(height: 7),
          Text(
            definition.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.elixTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reward: ${border?.displayName ?? 'Profile'} frame',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.elixTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                height: 30,
                child: Button(
                  onPressed: claiming ? null : onClaim,
                  child: claiming
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('Claim'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardTypePill extends StatelessWidget {
  const _RewardTypePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _XpSource {
  const _XpSource({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final String detail;
  final Color color;
  final IconData icon;
}

class _XpSourceCard extends StatelessWidget {
  const _XpSourceCard({required this.source});

  final _XpSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: source.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: source.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(source.icon, size: 15, color: source.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        source.label,
                        style: TextStyle(
                          color: context.elixTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '+${source.value} XP',
                      style: TextStyle(
                        color: source.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  source.detail,
                  style: TextStyle(
                    color: context.elixTextSecondary,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2)),
          SizedBox(width: AppSpacing.sm),
          Text('Checking completed rewards…'),
        ],
      ),
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  const _LoadErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Could not load today\'s quest rewards.',
            style: TextStyle(color: context.elixTextSecondary, fontSize: 12),
          ),
        ),
        Button(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _EmptyClaimState extends StatelessWidget {
  const _EmptyClaimState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ready_to_claim_empty_state'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm + 1,
      ),
      decoration: BoxDecoration(
        color: context.elixColors.surfaceRaised.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.52)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.elixColors.surfaceTinted.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.giftbox,
              size: 14,
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing to claim yet',
                  style: TextStyle(
                    color: context.elixTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Complete your quests and achievements to unlock rewards.',
                  style: TextStyle(
                    color: context.elixTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _tierColor(QuestTier tier) => switch (tier) {
  QuestTier.easy => AppColors.success,
  QuestTier.medium => AppColors.warning,
  QuestTier.hard => AppColors.primary,
};
