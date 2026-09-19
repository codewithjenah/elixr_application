import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/gamification_rules.dart';
import '../../../core/progression/progression_catalog.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/utils/manila_day.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_toast.dart';
import '../../../core/widgets/quest_reward_effect.dart';
import '../../../data/models/daily_quest.dart';
import '../../../data/models/daily_quest_board.dart';
import '../../../data/models/quest_claim.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/gamification_repository.dart';
import '../../../services/trainee_progression_service.dart';
import '../dashboard_quests.dart';
import 'dashboard_panel_card.dart';

/// Dashboard "Today's Quests" panel: fetches/creates today's persisted daily
/// quest board, shows the (at most 3) active quests with live progress, and
/// lets the user claim completed ones. Owns its own Firestore subscription
/// (same pattern as `DashboardLeaderboard`) so the rest of the dashboard can
/// load independently.
class DashboardQuestCard extends StatefulWidget {
  const DashboardQuestCard({
    super.key,
    required this.userId,
    required this.sessions,
    required this.streakDays,
    GamificationRepository? repository,
  }) : _repository = repository;

  final String userId;
  final List<Session> sessions;
  final int streakDays;
  final GamificationRepository? _repository;

  @override
  State<DashboardQuestCard> createState() => _DashboardQuestCardState();
}

class _DashboardQuestCardState extends State<DashboardQuestCard> {
  late final GamificationRepository _repository;
  StreamSubscription<Set<String>>? _claimsSub;
  Timer? _dayRolloverTimer;

  String? _loadedDayKey;
  DailyQuestBoard? _board;
  Set<String> _claimedIds = const {};
  bool _loading = true;
  bool _loadInFlight = false;
  Object? _error;
  String? _claimingQuestId;
  String? _retryableLeaderboardMissingQuestId;
  String? _claimErrorMessage;
  _QuestReward? _rewardFeedback;
  int _rewardFeedbackSequence = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? GamificationRepository();
    _dayRolloverTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkDayRollover(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final progression = Provider.of<TraineeProgressionService>(context);
    if (progression.isReady) {
      _ensureBoardLoaded();
    }
  }

  @override
  void didUpdateWidget(covariant DashboardQuestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _board = null;
      _loadedDayKey = null;
      _error = null;
      _loadInFlight = false;
      _rewardFeedback = null;
      _ensureBoardLoaded();
    }
  }

  @override
  void dispose() {
    _claimsSub?.cancel();
    _dayRolloverTimer?.cancel();
    super.dispose();
  }

  void _checkDayRollover() {
    final currentDayKey = ManilaDay.dayKeyFor(DateTime.now().toUtc());
    if (_loadedDayKey != null &&
        !ManilaDay.dayKeyEquals(_loadedDayKey!, currentDayKey)) {
      _board = null;
      _error = null;
      _loadInFlight = false;
      _rewardFeedback = null;
      _ensureBoardLoaded();
    }
  }

  void _ensureBoardLoaded() {
    if (_board != null || _loadInFlight || _error != null) return;
    unawaited(_loadBoard());
  }

  Future<void> _loadBoard() async {
    final userId = widget.userId;
    final progression = context.read<TraineeProgressionService>();
    if (!progression.isReady) {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
          _retryableLeaderboardMissingQuestId = null;
        });
      }
      return;
    }

    _claimsSub?.cancel();
    _claimsSub = null;
    _loadInFlight = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _retryableLeaderboardMissingQuestId = null;
      });
    }

    try {
      final board = await _repository.getOrCreateDailyBoard(
        userId: userId,
        currentLevel: progression.level,
      );
      if (!mounted || widget.userId != userId) return;
      _loadedDayKey = board.dayKey;
      setState(() {
        _board = board;
        _loading = false;
      });
      _subscribeToClaims(userId, board.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } finally {
      _loadInFlight = false;
    }
  }

  void _subscribeToClaims(String userId, String boardId) {
    _claimsSub = _repository
        .watchClaimedQuestIds(userId: userId, boardId: boardId)
        .listen(
          (claimedIds) {
            if (!mounted) return;
            setState(() => _claimedIds = claimedIds);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _error = error);
          },
        );
  }

  Future<void> _claim(String questId) async {
    final board = _board;
    if (board == null ||
        _claimingQuestId != null ||
        _claimedIds.contains(questId)) {
      return;
    }
    DashboardQuest? quest;
    for (final candidate in buildActiveDashboardQuests(
      board: board,
      claimedQuestIds: _claimedIds,
      sessions: widget.sessions,
    )) {
      if (candidate.id == questId) {
        quest = candidate;
        break;
      }
    }
    final questTitle = quest?.title ?? 'Daily Quest';

    setState(() {
      _claimingQuestId = questId;
      _retryableLeaderboardMissingQuestId = null;
      _claimErrorMessage = null;
    });

    try {
      final windowed = sessionsWithinBoardWindow(board, widget.sessions);
      final result = await _repository.claimQuest(
        userId: widget.userId,
        questId: questId,
        sessionsToday: windowed,
      );

      if (!mounted) return;

      switch (result.status) {
        case QuestClaimStatus.claimed:
          ElixToast.showSuccess(
            context,
            message: '+${result.xpAwarded} XP • $questTitle claimed',
          );
          setState(() {
            _claimedIds = {..._claimedIds, questId};
            _rewardFeedback = _QuestReward(
              eventId: '$questId-${++_rewardFeedbackSequence}',
              xp: result.xpAwarded,
              questTitle: questTitle,
            );
          });
          break;
        case QuestClaimStatus.alreadyClaimed:
          ElixToast.showInfo(
            context,
            message: 'This quest reward was already claimed.',
          );
          setState(() => _claimedIds = {..._claimedIds, questId});
          break;
        case QuestClaimStatus.boardExpired:
        case QuestClaimStatus.boardMissing:
          ElixToast.showInfo(
            context,
            message: 'Today\'s quest board changed. Refreshing it now.',
          );
          _board = null;
          _error = null;
          unawaited(_loadBoard());
          break;
        case QuestClaimStatus.leaderboardMissing:
          ElixToast.showInfo(
            context,
            message: 'Your XP profile is still loading. Try again shortly.',
          );
          setState(() => _retryableLeaderboardMissingQuestId = questId);
          break;
        case QuestClaimStatus.questNotCompleted:
          ElixToast.showInfo(
            context,
            message: 'This quest is not complete yet.',
          );
          setState(
            () => _claimErrorMessage = 'Not quite there yet — keep practicing!',
          );
          break;
        case QuestClaimStatus.invalidQuest:
          ElixToast.showError(
            context,
            message: 'This quest is no longer available.',
          );
          setState(
            () => _claimErrorMessage = 'This quest is no longer available.',
          );
          break;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Quest claim failed: userId=${widget.userId} questId=$questId error=$error',
        );
      }
      if (mounted) {
        ElixToast.showError(
          context,
          message: 'Could not claim this quest. Try again.',
        );
        setState(
          () => _claimErrorMessage = 'Could not claim this quest. Try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _claimingQuestId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progression = context.watch<TraineeProgressionService>();
    return DashboardPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElixSectionHeader(
            heading: "Today's Quests",
            subtitle: 'Earn XP to unlock your next movement',
            actions: [
              if (widget.streakDays > 0)
                DashboardPill(
                  text: '${widget.streakDays}-day streak',
                  color: context.elixColors.milestone,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ..._buildBody(progression),
        ],
      ),
    );
  }

  List<Widget> _buildBody(TraineeProgressionService progression) {
    if (!progression.isReady || (_loading && _board == null)) {
      final label = !progression.isReady
          ? 'Loading your level…'
          : "Loading today's quests…";
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final board = _board;
    if (_error != null || board == null) {
      return [
        Text(
          'Could not load today\'s quests.',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuestAction(
          onPressed: () {
            _error = null;
            _board = null;
            unawaited(_loadBoard());
          },
          label: 'Retry',
        ),
      ];
    }

    if (_retryableLeaderboardMissingQuestId != null) {
      final questId = _retryableLeaderboardMissingQuestId!;
      return [
        _ProgressionStrip(progression: progression),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your profile is still loading. Try claiming again in a moment.',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuestAction(onPressed: () => _claim(questId), label: 'Retry claim'),
        const SizedBox(height: AppSpacing.md),
      ];
    }

    final complete = isDailyBoardComplete(
      board: board,
      claimedQuestIds: _claimedIds,
    );
    final quests = complete
        ? const <DashboardQuest>[]
        : buildActiveDashboardQuests(
            board: board,
            claimedQuestIds: _claimedIds,
            sessions: widget.sessions,
          );

    return [
      _ProgressionStrip(progression: progression),
      const SizedBox(height: AppSpacing.md),
      if (_claimErrorMessage != null) ...[
        Text(
          _claimErrorMessage!,
          style: ElixTypography.caption(color: context.elixColors.error),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (_rewardFeedback case final reward?)
        QuestRewardEffect(
          eventId: reward.eventId,
          xp: reward.xp,
          questTitle: reward.questTitle,
        ),
      AnimatedSwitcher(
        duration: ElixMotion.duration(
          context,
          const Duration(milliseconds: 260),
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(sizeFactor: animation, child: child),
        ),
        child: complete
            ? const _CompleteBanner(key: ValueKey('complete'))
            : Column(
                key: ValueKey(quests.map((q) => q.id).join(',')),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < quests.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    _QuestTile(
                      quest: quests[i],
                      claiming: _claimingQuestId == quests[i].id,
                      claimDisabled: _claimingQuestId != null,
                      onClaim: () => _claim(quests[i].id),
                    ),
                  ],
                ],
              ),
      ),
      const SizedBox(height: 10),
      _BoardGauge(
        claimedCount: _claimedIds.length,
        total: board.questIds.length,
      ),
    ];
  }
}

class _QuestReward {
  const _QuestReward({
    required this.eventId,
    required this.xp,
    required this.questTitle,
  });

  final String eventId;
  final int xp;
  final String questTitle;
}

class _QuestAction extends StatelessWidget {
  const _QuestAction({required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return Button(onPressed: onPressed, child: Text(label));
    }
    return shad.ShadButton.outline(onPressed: onPressed, child: Text(label));
  }
}

class _ProgressionStrip extends StatelessWidget {
  const _ProgressionStrip({required this.progression});

  final TraineeProgressionService progression;

  @override
  Widget build(BuildContext context) {
    final level = progression.level;
    final next = nextUnlockAfterLevel(level);
    final remaining = xpRemainingToNextUnlock(progression.totalXp);
    final into = GamificationRules.xpIntoLevel(progression.totalXp);
    final perLevel = GamificationRules.xpPerLevel;
    final unlocked = next == null;
    final nextLabel = unlocked
        ? 'All movement variants unlocked'
        : 'Next unlock: ${next.movementName} • ${next.trainingProp.displayLabel}';
    final remainingLabel = unlocked ? null : '$remaining XP remaining';
    final progress = unlocked ? 1.0 : into / perLevel;
    final semanticLabel = [
      'Level $level',
      nextLabel,
      ?remainingLabel,
    ].join('. ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: context.elixColors.surfaceTinted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              label: semanticLabel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Level $level',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nextLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.elixTextPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (remainingLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      remainingLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Container(
                            color: context.elixBorder.withValues(alpha: 0.5),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: Container(
                              color: context.elixColors.brandPrimary.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          HyperlinkButton(
            onPressed: () => context.go(AppRoutePaths.movements),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
            ),
            child: const Text('View movements', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _CompleteBanner extends StatelessWidget {
  const _CompleteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: context.elixColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.trophy2,
            size: 16,
            color: context.elixColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Daily board complete. See you tomorrow!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.elixTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardGauge extends StatelessWidget {
  const _BoardGauge({required this.claimedCount, required this.total});

  final int claimedCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : claimedCount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                claimedCount >= total
                    ? 'All quests claimed'
                    : claimedCount > 0
                    ? 'Keep going — claim more XP'
                    : 'Complete and claim quests for XP',
                style: TextStyle(
                  fontSize: 11,
                  color: context.elixTextSecondary,
                ),
              ),
            ),
            Text(
              '$claimedCount/$total',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.elixTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Container(color: context.elixBorder.withValues(alpha: 0.5)),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    color: context.elixColors.brandPrimary.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestTile extends StatelessWidget {
  const _QuestTile({
    required this.quest,
    required this.claiming,
    required this.claimDisabled,
    required this.onClaim,
  });

  final DashboardQuest quest;
  final bool claiming;
  final bool claimDisabled;
  final VoidCallback onClaim;

  Color _tierColor(BuildContext context) => switch (quest.tier) {
    QuestTier.easy => context.elixColors.success,
    QuestTier.medium => context.elixColors.warning,
    QuestTier.hard => context.elixColors.brandPrimary,
  };

  @override
  Widget build(BuildContext context) {
    final claimable = quest.completed;
    final progress = quest.target <= 0
        ? 0.0
        : (quest.current / quest.target).clamp(0.0, 1.0);
    final progressLabel = claimable
        ? 'Ready to claim'
        : '${quest.current}/${quest.target}';
    final semanticLabel = [
      '${quest.tier.label} quest: ${quest.title}',
      'Progress ${quest.current} of ${quest.target}',
      'Reward ${quest.xp} XP',
      claimable ? 'Ready to claim' : 'Not ready to claim',
    ].join('. ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: claimable
            ? context.elixColors.success.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: semanticLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DashboardPill(
                      text: quest.tier.label,
                      color: _tierColor(context),
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        quest.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.elixTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+${quest.xp} XP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.elixColors.milestone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: claimable
                        ? context.elixColors.success
                        : context.elixTextSecondary,
                  ),
                ),
                if (!claimable) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Container(
                            color: context.elixBorder.withValues(alpha: 0.45),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              color: context.elixColors.brandSecondary
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (claimable) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 28,
                child: Button(
                  onPressed: claimDisabled ? null : onClaim,
                  child: claiming
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : const Text('Claim', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
