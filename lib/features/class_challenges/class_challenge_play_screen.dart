import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/models/class_challenge.dart';
import '../../data/models/class_challenge_session_context.dart';
import '../../data/repositories/class_challenge_repository.dart';
import '../../services/auth_service.dart';
import '../learning/movement_lesson_content.dart';
import '../learning/movement_tutorial_dialog.dart';
import '../practice/practice_screen.dart';

class ClassChallengePlayScreen extends StatefulWidget {
  const ClassChallengePlayScreen({
    super.key,
    required this.groupId,
    required this.challengeId,
  });

  final String groupId;
  final String challengeId;

  @override
  State<ClassChallengePlayScreen> createState() =>
      _ClassChallengePlayScreenState();
}

class _ClassChallengePlayScreenState extends State<ClassChallengePlayScreen> {
  ClassChallenge? _challenge;
  ClassChallengeAttempt? _attempt;
  bool _loading = true;
  bool _reserving = false;
  bool _completed = false;
  String? _error;

  ClassChallengeRepository get _repository =>
      context.read<ClassChallengeRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final challenge = await _repository.getChallenge(
        challengeId: widget.challengeId,
      );
      if (!mounted) return;
      setState(() {
        _challenge = challenge?.groupId == widget.groupId ? challenge : null;
        _loading = false;
        if (_challenge == null) _error = 'This challenge is not available.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this challenge. Check your connection.';
      });
    }
  }

  @override
  void dispose() {
    final challenge = _challenge;
    final attempt = _attempt;
    if (!_completed && challenge != null && attempt != null) {
      unawaited(
        _repository.abandonAttempt(
          challengeId: challenge.id,
          attemptId: attempt.id,
        ),
      );
    }
    super.dispose();
  }

  Future<void> _begin() async {
    final challenge = _challenge;
    if (challenge == null || _reserving) return;
    setState(() {
      _reserving = true;
      _error = null;
    });
    try {
      final attempt = await _repository.reserveAttempt(
        challengeId: challenge.id,
        requestId:
            'challenge-open-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() {
        _attempt = attempt;
        _reserving = false;
      });
    } on ClassChallengeException catch (failure) {
      if (!mounted) return;
      setState(() {
        _reserving = false;
        _error = switch (failure.code) {
          'not_started' => 'This challenge has not started yet.',
          'deadline_passed' => 'This challenge has ended.',
          'attempts_exhausted' => 'You have no attempts remaining.',
          'attempt_in_progress' =>
            'A challenge attempt is already in progress.',
          'offline' => 'You appear to be offline. Reconnect and try again.',
          _ => 'Could not start the challenge. Try again.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ElixScaffoldPage(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Expanded(child: Center(child: ProgressRing())),
          ],
        ),
      );
    }
    final challenge = _challenge;
    if (challenge == null) {
      return ElixScaffoldPage(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: ElixStatusPanel(
                title: 'Challenge unavailable',
                message: _error ?? 'This challenge cannot be opened.',
                isError: true,
              ),
            ),
          ],
        ),
      );
    }
    final attempt = _attempt;
    if (attempt != null) {
      return _buildPractice(challenge, attempt);
    }
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    return ElixScaffoldPage(
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: StreamBuilder<ClassChallengeParticipant?>(
                stream: _repository.watchParticipant(
                  challengeId: challenge.id,
                  traineeId: userId,
                ),
                builder: (context, participantSnapshot) =>
                    StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
                      stream: _repository.watchLeaderboard(
                        challengeId: challenge.id,
                        groupId: challenge.groupId,
                        teacherId: challenge.teacherId,
                      ),
                      builder: (context, leaderboardSnapshot) {
                        final participant = participantSnapshot.data;
                        final remaining =
                            participant?.attemptsRemaining(
                              challenge.attemptLimit,
                            ) ??
                            challenge.attemptLimit;
                        ClassChallengeLeaderboardEntry? personal;
                        for (final entry
                            in leaderboardSnapshot.data ?? const []) {
                          if (entry.traineeId == userId) personal = entry;
                        }
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: _ChallengeReadyPanel(
                              challenge: challenge,
                              remaining: remaining,
                              personalBest: personal?.score,
                              error: _error,
                              isReserving: _reserving,
                              canBegin:
                                  challenge.canStartAt(DateTime.now()) &&
                                  (remaining == null || remaining > 0),
                              onBegin: _begin,
                              onViewTutorial: () => _showTutorial(challenge),
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => ElixEditorialPageHeader(
    heading: 'Class Challenge',
    eyebrow: 'READY UP',
    variant: ElixEditorialHeaderVariant.compact,
    headingColor: _headerForegroundColor,
    leading: ElixBackButton(
      key: const Key('class_challenge_play_back'),
      label: 'Challenges',
      tooltip: 'Back to classroom challenges',
      semanticLabel: 'Back to classroom challenges',
      foregroundColor: _headerForegroundColor,
      onPressed: _backToChallenges,
    ),
  );

  Color? get _headerForegroundColor {
    if (context.isDarkTheme || context.isHighContrast) return null;
    return Colors.white;
  }

  void _backToChallenges() {
    context.go(
      '${AppRoutePaths.teacherAccessClass(widget.groupId)}?tab=challenges',
    );
  }

  Widget _buildPractice(
    ClassChallenge challenge,
    ClassChallengeAttempt attempt,
  ) {
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    return StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
      stream: _repository.watchLeaderboard(
        challengeId: challenge.id,
        groupId: challenge.groupId,
        teacherId: challenge.teacherId,
      ),
      builder: (context, snapshot) {
        int? previousBest;
        for (final entry in snapshot.data ?? const []) {
          if (entry.traineeId == userId) previousBest = entry.score;
        }
        return PracticeScreen(
          movement: challenge.movementName,
          difficulty: challenge.difficulty,
          prop: challenge.prop,
          challengeContext: ClassChallengeSessionContext(
            challengeId: challenge.id,
            groupId: challenge.groupId,
            teacherId: challenge.teacherId,
            attemptId: attempt.id,
          ),
          previousChallengeBest: previousBest,
          challengeReturnLocation: AppRoutePaths.classChallengeLeaderboard(
            challenge.groupId,
            challenge.id,
          ),
          onChallengeComplete: (sessionId) async {
            final best = await _repository.completeAttempt(
              challengeId: challenge.id,
              attemptId: attempt.id,
              sessionId: sessionId,
            );
            _completed = true;
            int? rank;
            try {
              final ranking = await _repository
                  .watchLeaderboard(
                    challengeId: challenge.id,
                    groupId: challenge.groupId,
                    teacherId: challenge.teacherId,
                  )
                  .first
                  .timeout(const Duration(seconds: 5));
              final index = ranking.indexWhere(
                (entry) => entry.traineeId == userId,
              );
              if (index >= 0) rank = index + 1;
            } on TimeoutException {
              rank = null;
            }
            return ClassChallengeCompletionReceipt(
              bestResult: best,
              rank: rank,
            );
          },
        );
      },
    );
  }

  void _showTutorial(ClassChallenge challenge) {
    final movement = movementCatalog.firstWhere(
      (item) => item.name == challenge.movementName,
    );
    showDialog<void>(
      context: context,
      builder: (context) => MovementTutorialDialog(
        movement: movement,
        prop: challenge.prop,
        lesson: MovementLesson.forMovement(movement),
      ),
    );
  }
}

class _ChallengeReadyPanel extends StatelessWidget {
  const _ChallengeReadyPanel({
    required this.challenge,
    required this.remaining,
    required this.personalBest,
    required this.error,
    required this.isReserving,
    required this.canBegin,
    required this.onBegin,
    required this.onViewTutorial,
  });

  final ClassChallenge challenge;
  final int? remaining;
  final int? personalBest;
  final String? error;
  final bool isReserving;
  final bool canBegin;
  final VoidCallback onBegin;
  final VoidCallback onViewTutorial;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return ElixPanelCard(
      variant: ElixPanelVariant.hero,
      accent: colors.brandPrimary,
      showAccentBar: true,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.brandPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ElixRadius.control),
                  border: Border.all(
                    color: colors.brandPrimary.withValues(alpha: 0.42),
                  ),
                ),
                child: Icon(
                  FluentIcons.lightning_bolt,
                  color: colors.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ElixEyebrow(label: 'LIVE CLASS CHALLENGE'),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      challenge.title,
                      style: AppTheme.displayHero(
                        context,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _AvailabilityBadge(enabled: canBegin),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            challenge.description,
            style: AppTheme.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 580;
              final stats = [
                _ChallengeStat(
                  icon: FluentIcons.completed_solid,
                  label: 'Movement',
                  value: challenge.movementName,
                ),
                _ChallengeStat(
                  icon: FluentIcons.product,
                  label: 'Prop',
                  value: challenge.prop.displayLabel,
                ),
                const _ChallengeStat(
                  icon: FluentIcons.bullseye_target,
                  label: 'Scoring',
                  value: 'Best score · 0–12',
                ),
                _ChallengeStat(
                  icon: FluentIcons.redo,
                  label: 'Attempts',
                  value: remaining == null ? 'Unlimited' : '$remaining left',
                ),
              ];
              return GridView.count(
                crossAxisCount: compact ? 1 : 2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: compact ? 4.4 : 2.85,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: stats,
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _PersonalBestStrip(score: personalBest),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ChallengeError(message: error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 480;
              final begin = ElixPrimaryButton(
                label: 'Begin Challenge',
                icon: FluentIcons.play,
                expanded: compact,
                isLoading: isReserving,
                onPressed: canBegin ? onBegin : null,
              );
              final tutorial = ElixPrimaryButton(
                label: 'View Tutorial',
                icon: FluentIcons.play_resume,
                variant: ElixButtonVariant.outline,
                expanded: compact,
                onPressed: onViewTutorial,
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        begin,
                        const SizedBox(height: AppSpacing.sm),
                        tutorial,
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        begin,
                        const SizedBox(width: AppSpacing.sm),
                        tutorial,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final tone = enabled ? colors.success : colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(ElixRadius.pill),
        border: Border.all(color: tone.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? FluentIcons.completed_solid : FluentIcons.clock,
            size: 12,
            color: tone,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            enabled ? 'READY NOW' : 'UNAVAILABLE',
            style: AppTheme.caption.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeStat extends StatelessWidget {
  const _ChallengeStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceBase.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(ElixRadius.control),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.brandSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.caption.copyWith(color: colors.textMuted),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalBestStrip extends StatelessWidget {
  const _PersonalBestStrip({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smPlus,
      ),
      decoration: BoxDecoration(
        color: colors.brandSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ElixRadius.control),
        border: Border.all(
          color: colors.brandSecondary.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.trophy2, color: colors.milestone, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Personal best',
              style: AppTheme.label(color: colors.textSecondary),
            ),
          ),
          Text(
            score == null ? 'No score yet' : '$score/12',
            style: AppTheme.compactMetric(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ChallengeError extends StatelessWidget {
  const _ChallengeError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ElixRadius.control),
        border: Border.all(color: colors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.error_badge, color: colors.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTheme.supporting(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
