import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
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
      return const ElixScaffoldPage(content: Center(child: ProgressRing()));
    }
    final challenge = _challenge;
    if (challenge == null) {
      return ElixScaffoldPage(
        content: ElixStatusPanel(
          title: 'Challenge unavailable',
          message: _error ?? 'This challenge cannot be opened.',
          isError: true,
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
            const ElixEditorialPageHeader(
              heading: 'Class Challenge',
              eyebrow: 'READY UP',
              variant: ElixEditorialHeaderVariant.compact,
            ),
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
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: ElixPanelCard(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    challenge.title,
                                    style: AppTheme.headingLarge,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    challenge.description,
                                    style: AppTheme.body,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  _InfoRow(
                                    label: 'Movement',
                                    value: challenge.movementName,
                                  ),
                                  _InfoRow(
                                    label: 'Prop',
                                    value: challenge.prop.displayLabel,
                                  ),
                                  _InfoRow(
                                    label: 'Scoring',
                                    value: 'Best ELIXR rubric total (0–12)',
                                  ),
                                  _InfoRow(
                                    label: 'Attempts',
                                    value: remaining == null
                                        ? 'Unlimited'
                                        : '$remaining remaining',
                                  ),
                                  _InfoRow(
                                    label: 'Personal best',
                                    value: personal == null
                                        ? 'No score yet'
                                        : '${personal.score}/12',
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    InfoBar(
                                      title: const Text('Cannot start'),
                                      content: Text(_error!),
                                      severity: InfoBarSeverity.error,
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.lg),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    runSpacing: AppSpacing.sm,
                                    children: [
                                      ElixPrimaryButton(
                                        label: 'Begin Challenge',
                                        icon: FluentIcons.play,
                                        expanded: false,
                                        isLoading: _reserving,
                                        onPressed:
                                            challenge.canStartAt(
                                                  DateTime.now(),
                                                ) &&
                                                (remaining == null ||
                                                    remaining > 0)
                                            ? _begin
                                            : null,
                                      ),
                                      Button(
                                        onPressed: () =>
                                            _showTutorial(challenge),
                                        child: const Text('View Tutorial'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

  Widget _buildPractice(
    ClassChallenge challenge,
    ClassChallengeAttempt attempt,
  ) {
    final userId = context.read<AuthService>().currentUser?.id ?? '';
    return StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
      stream: _repository.watchLeaderboard(challengeId: challenge.id),
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
                  .watchLeaderboard(challengeId: challenge.id)
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: AppTheme.bodySecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
