import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/manila_day.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../data/models/daily_quest_board.dart';
import '../../../data/models/quest_claim.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/gamification_repository.dart';
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
  Object? _error;
  String? _claimingQuestId;
  String? _retryableLeaderboardMissingQuestId;
  String? _claimErrorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? GamificationRepository();
    _loadBoard();
    _dayRolloverTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkDayRollover(),
    );
  }

  @override
  void didUpdateWidget(covariant DashboardQuestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadBoard();
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
      _loadBoard();
    }
  }

  Future<void> _loadBoard() async {
    final userId = widget.userId;
    _claimsSub?.cancel();
    _claimsSub = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _retryableLeaderboardMissingQuestId = null;
      });
    }

    try {
      final board = await _repository.getOrCreateDailyBoard(userId: userId);
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
    if (board == null || _claimingQuestId != null) return;

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
        case QuestClaimStatus.alreadyClaimed:
          break;
        case QuestClaimStatus.boardExpired:
        case QuestClaimStatus.boardMissing:
          unawaited(_loadBoard());
          break;
        case QuestClaimStatus.leaderboardMissing:
          setState(() => _retryableLeaderboardMissingQuestId = questId);
          break;
        case QuestClaimStatus.questNotCompleted:
          setState(
            () => _claimErrorMessage = 'Not quite there yet — keep practicing!',
          );
          break;
        case QuestClaimStatus.invalidQuest:
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
    return DashboardPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElixSectionHeader(
            heading: "Today's Quests",
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
          ..._buildBody(),
        ],
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: ProgressRing()),
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
        Button(onPressed: _loadBoard, child: const Text('Retry')),
      ];
    }

    if (_retryableLeaderboardMissingQuestId != null) {
      final questId = _retryableLeaderboardMissingQuestId!;
      return [
        Text(
          'Your profile is still loading. Try claiming again in a moment.',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Button(
          onPressed: () => _claim(questId),
          child: const Text('Retry claim'),
        ),
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
      if (_claimErrorMessage != null) ...[
        Text(
          _claimErrorMessage!,
          style: const TextStyle(fontSize: 11, color: AppColors.error),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
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
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.trophy2, size: 16, color: AppColors.success),
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
                    color: AppColors.primary.withValues(alpha: 0.85),
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

  @override
  Widget build(BuildContext context) {
    final claimable = quest.completed;
    final progress = quest.target <= 0
        ? 0.0
        : (quest.current / quest.target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: claimable
            ? AppColors.success.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  claimable
                      ? 'Ready to claim'
                      : '${quest.current}/${quest.target}',
                  style: TextStyle(
                    fontSize: 10,
                    color: claimable
                        ? AppColors.success
                        : context.elixTextSecondary,
                  ),
                ),
              ),
              if (claimable)
                SizedBox(
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
            ],
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
                        color: AppColors.accent.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
