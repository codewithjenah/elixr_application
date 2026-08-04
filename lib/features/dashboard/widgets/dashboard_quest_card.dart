import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/manila_day.dart';
import '../../../data/models/daily_quest_board.dart';
import '../../../data/models/quest_claim.dart';
import '../../../data/models/session.dart';
import '../../../data/repositories/gamification_repository.dart';
import '../dashboard_quests.dart';
import 'dashboard_panel_card.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;
const _amber = AppColors.warning;

/// Dashboard "Today's Quest" panel: fetches/creates today's persisted daily
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
          // The live claims stream will update _claimedIds; nothing else to do.
          break;
        case QuestClaimStatus.boardExpired:
        case QuestClaimStatus.boardMissing:
          // The Manila day rolled over mid-claim; transparently refetch.
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
      accent: _pink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(FluentIcons.lightning_bolt, size: 14, color: _amber),
                  SizedBox(width: 6),
                  Text(
                    "Today's Quest",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (widget.streakDays > 0)
                DashboardPill(
                  text: '🔥 ${widget.streakDays} Day Streak',
                  color: _amber,
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
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Button(onPressed: _loadBoard, child: const Text('Retry')),
      ];
    }

    if (_retryableLeaderboardMissingQuestId != null) {
      final questId = _retryableLeaderboardMissingQuestId!;
      return [
        const Text(
          'Your profile is still loading. Try claiming again in a moment.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
            ? _CompleteBanner(key: const ValueKey('complete'))
            : Column(
                key: ValueKey(quests.map((q) => q.id).join(',')),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final quest in quests) ...[
                    _QuestTile(
                      quest: quest,
                      claiming: _claimingQuestId == quest.id,
                      claimDisabled: _claimingQuestId != null,
                      onClaim: () => _claim(quest.id),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
      const SizedBox(height: 4),
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
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(FluentIcons.trophy2_solid, size: 16, color: AppColors.success),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Daily board complete. See you tomorrow!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                claimedCount >= total
                    ? 'All quests claimed. Amazing work!'
                    : claimedCount > 0
                    ? 'Keep going — claim more XP!'
                    : 'Complete and claim quests to earn XP.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      Container(color: AppColors.border),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [_pink, _purple]),
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
        const SizedBox(width: 10),
        Text(
          '$claimedCount/$total claimed',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: claimable
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: claimable
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        quest.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+${quest.xp} XP',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  claimable
                      ? 'Ready to claim'
                      : '${quest.current}/${quest.target}',
                  style: TextStyle(
                    fontSize: 10,
                    color: claimable
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
    );
  }
}
