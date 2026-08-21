import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import 'teacher_movements_controller.dart';

class TeacherReviewsPane extends StatefulWidget {
  const TeacherReviewsPane({super.key, required this.controller});

  final TeacherMovementsController controller;

  @override
  State<TeacherReviewsPane> createState() => _TeacherReviewsPaneState();
}

class _TeacherReviewsPaneState extends State<TeacherReviewsPane> {
  final _feedback = TextEditingController();
  final _playbackSession = ElixrPlaybackSession();
  SubmissionPlaybackFile? _playable;
  Object? _playableError;
  String? _playableAttemptId;

  TeacherMovementsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _feedback.dispose();
    unawaited(_releasePlayback());
    super.dispose();
  }

  void _onController() {
    final selected = controller.selectedReview;
    if (selected == null) {
      if (_playableAttemptId != null || _playable != null) {
        unawaited(_releasePlayback());
      }
      if (mounted) setState(() {});
      return;
    }
    if (_playableAttemptId != selected.id) {
      _feedback.text = controller.reviewFeedbackDraft ?? '';
      unawaited(_loadPlayback(selected));
    }
    if (mounted) setState(() {});
  }

  Future<void> _releasePlayback() async {
    await _playbackSession.release();
    await controller.releasePlaybackCache();
    _playable = null;
    _playableError = null;
    _playableAttemptId = null;
  }

  Future<void> _openReview(AssignmentAttempt? attempt) async {
    await _playbackSession.release();
    await controller.selectReview(attempt);
  }

  Future<void> _loadPlayback(AssignmentAttempt attempt) async {
    await _playbackSession.release();
    _playableAttemptId = attempt.id;
    _playable = null;
    _playableError = null;
    if (mounted) setState(() {});
    try {
      final file = await controller.openLocalPlayback(attempt);
      if (!mounted || _playableAttemptId != attempt.id) return;
      setState(() {
        _playable = file;
        _playableError = null;
      });
    } catch (error) {
      if (!mounted || _playableAttemptId != attempt.id) return;
      setState(() {
        _playable = null;
        _playableError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedReview;
    if (selected != null) {
      return _Detail(
        controller: controller,
        attempt: selected,
        feedback: _feedback,
        playable: _playable,
        playableError: _playableError,
        playbackSession: _playbackSession,
        onBack: () => _openReview(null),
      );
    }
    final queue = controller.reviewQueue;
    if (queue.isEmpty) {
      return const Center(
        child: Text(
          'No Teacher-reviewed submissions yet.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: queue.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final attempt = queue[index];
        final assignment = controller.assignmentFor(attempt);
        final videoLabel = !attempt.hasPlayableVideo
            ? 'Video removed'
            : attempt.videoExpired
            ? 'Video expired'
            : 'Video available';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.traineeName(attempt.traineeId),
                        style: AppTheme.headingMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${assignment?.displayTitle ?? 'Assignment'} · '
                        '${controller.groupName(attempt.groupId)} · '
                        '${attempt.status.wireValue} · $videoLabel',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                      if (attempt.submittedAt != null)
                        Text(
                          'Submitted ${attempt.submittedAt!.toLocal().toIso8601String().split('T').first}',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      if (attempt.supersedesAttemptId != null)
                        Text(
                          'Replacement for a previous needs-retry clip',
                          style: AppTheme.caption,
                        ),
                    ],
                  ),
                ),
                Button(
                  onPressed: () => _openReview(attempt),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.controller,
    required this.attempt,
    required this.feedback,
    required this.playable,
    required this.playableError,
    required this.playbackSession,
    required this.onBack,
  });

  final TeacherMovementsController controller;
  final AssignmentAttempt attempt;
  final TextEditingController feedback;
  final SubmissionPlaybackFile? playable;
  final Object? playableError;
  final ElixrPlaybackSession playbackSession;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final assignment = controller.assignmentFor(attempt);
    final canReview = attempt.status == AssignmentAttemptStatus.submitted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Button(
            onPressed: onBack,
            child: const Text('Back to reviews'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          controller.traineeName(attempt.traineeId),
          style: AppTheme.headingMedium,
        ),
        Text(
          '${assignment?.displayTitle ?? 'Assignment'} · '
          '${controller.groupName(attempt.groupId)}',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 240, child: _video()),
        const SizedBox(height: AppSpacing.md),
        Text('Status: ${attempt.status.wireValue}', style: AppTheme.body),
        if (attempt.reviewFeedback != null &&
            attempt.reviewFeedback!.isNotEmpty)
          Text('Feedback: ${attempt.reviewFeedback}', style: AppTheme.body),
        if (canReview) ...[
          const SizedBox(height: AppSpacing.sm),
          TextBox(
            controller: feedback,
            maxLength: 1000,
            maxLines: 4,
            placeholder: 'Bounded feedback for the Trainee',
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilledButton(
                onPressed: controller.busy
                    ? null
                    : () => controller.reviewSelected(
                        verdict: AssignmentReviewVerdict.approved,
                        feedback: feedback.text,
                      ),
                child: const Text('Approve'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Button(
                onPressed: controller.busy
                    ? null
                    : () => controller.reviewSelected(
                        verdict: AssignmentReviewVerdict.needsRetry,
                        feedback: feedback.text,
                      ),
                child: const Text('Needs Retry'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _video() {
    if (!attempt.hasPlayableVideo || attempt.videoExpired) {
      return Center(
        child: Text(
          'This clip is no longer available. The review history is kept.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: AppColors.warning),
        ),
      );
    }
    if (playableError != null) {
      return Center(
        child: Text(
          'This clip could not be opened.',
          style: AppTheme.body.copyWith(color: AppColors.error),
        ),
      );
    }
    if (playable == null) {
      return const Center(child: ProgressRing());
    }
    return ElixrVideoPlayer(source: playable!.uri, session: playbackSession);
  }
}
