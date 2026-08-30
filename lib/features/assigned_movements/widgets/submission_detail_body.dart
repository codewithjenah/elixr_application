import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_submission_limits.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/rubric_assessment.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../features/history/history_format.dart';
import '../assigned_movement_list.dart';

enum SubmissionDetailViewerRole { trainee, teacher }

/// Role-agnostic submitted-work panel used by trainee assignment detail
/// and the teacher classwork drill-down.
class SubmissionDetailBody extends StatefulWidget {
  const SubmissionDetailBody({
    super.key,
    required this.assignment,
    required this.attempt,
    required this.viewerRole,
    this.submissionRepository,
    this.openLocalPlayback,
    this.releaseLocalPlayback,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt attempt;
  final SubmissionDetailViewerRole viewerRole;
  final AssignmentSubmissionRepository? submissionRepository;
  final Future<SubmissionPlaybackFile?> Function(AssignmentAttempt attempt)?
  openLocalPlayback;
  final Future<void> Function()? releaseLocalPlayback;

  @override
  State<SubmissionDetailBody> createState() => _SubmissionDetailBodyState();
}

class _SubmissionDetailBodyState extends State<SubmissionDetailBody> {
  final _playbackSession = ElixrPlaybackSession();
  SubmissionPlaybackFile? _playable;
  Object? _playableError;
  String? _playableAttemptId;

  AssignmentAttempt get attempt => widget.attempt;

  @override
  void initState() {
    super.initState();
    _loadForAttempt();
  }

  @override
  void didUpdateWidget(covariant SubmissionDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attempt.id != widget.attempt.id) {
      _loadForAttempt();
    }
  }

  @override
  void dispose() {
    unawaited(_releasePlayback(releaseHost: true));
    super.dispose();
  }

  void _loadForAttempt() {
    unawaited(_loadPlayback());
  }

  Future<void> _releasePlayback({required bool releaseHost}) async {
    await _playbackSession.release();
    if (releaseHost) {
      await widget.releaseLocalPlayback?.call();
    }
    _playable = null;
    _playableError = null;
    _playableAttemptId = null;
  }

  Future<void> _loadPlayback() async {
    final hadPlayback = _playableAttemptId != null || _playable != null;
    await _releasePlayback(releaseHost: hadPlayback);
    if (!mounted) return;
    if (!_shouldOfferPlayback) {
      setState(() {});
      return;
    }
    _playableAttemptId = attempt.id;
    _playable = null;
    _playableError = null;
    setState(() {});
    try {
      final opener =
          widget.openLocalPlayback ??
          widget.submissionRepository?.openLocalPlayback;
      final file = opener == null ? null : await opener(attempt);
      if (!mounted || _playableAttemptId != attempt.id) return;
      setState(() {
        _playable = file;
        _playableError = file == null
            ? const AssignmentSubmissionException(
                'This clip could not be opened.',
              )
            : null;
      });
    } catch (error) {
      if (!mounted || _playableAttemptId != attempt.id) return;
      setState(() {
        _playable = null;
        _playableError = error;
      });
    }
  }

  bool get _shouldOfferPlayback {
    if (!_isTeacherReviewedAttempt) return false;
    if (attempt.isUnsubmitting) return false;
    if (!attempt.hasPlayableVideo) return false;
    if (attempt.videoExpired) return false;
    return true;
  }

  bool get _isOfficialAttempt {
    return attempt.attemptKind == AssignmentAttemptKind.practicePointer ||
        attempt.attemptKind == AssignmentAttemptKind.templateScore;
  }

  bool get _isTeacherReviewedAttempt {
    return attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission ||
        attempt.attemptKind == AssignmentAttemptKind.teacherReviewDraft;
  }

  bool get _clipBytesGone {
    if (!_isTeacherReviewedAttempt) return false;
    if (attempt.isAbandonedTeacherReviewDraft) return false;
    if (attempt.status == AssignmentAttemptStatus.draft ||
        attempt.status == AssignmentAttemptStatus.inProgress) {
      return false;
    }
    return attempt.videoExpired || attempt.videoDeletedAt != null;
  }

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isTeacherReviewedAttempt) ...[
            Text(
              widget.viewerRole == SubmissionDetailViewerRole.teacher
                  ? 'Submission clip'
                  : 'Your clip',
              style: AppTheme.headingMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              key: const Key('submission_clip_preview'),
              height: 240,
              child: _TeacherReviewedSection.video(
                context: context,
                clipBytesGone: _clipBytesGone,
                shouldOfferPlayback: _shouldOfferPlayback,
                playable: _playable,
                playableError: _playableError,
                playbackSession: _playbackSession,
                onRetry: _loadForAttempt,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_isOfficialAttempt) ...[
            Text(
              widget.viewerRole == SubmissionDetailViewerRole.teacher
                  ? 'Submission clip'
                  : 'Your clip',
              style: AppTheme.headingMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            const SizedBox(
              key: Key('submission_official_no_clip'),
              height: 240,
              child: _OfficialNoClipPreview(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ElixPill(
                text: assignedMovementStatusLabel(
                  widget.assignment,
                  attempt,
                  attempt.isTeacherReviewSubmission ? attempt : null,
                ),
                color: assignedMovementStatusColor(
                  widget.assignment,
                  attempt,
                  attempt.isTeacherReviewSubmission ? attempt : null,
                ),
                compact: true,
              ),
              if (attempt.supersedesAttemptId != null &&
                  !attempt.isCanonicalTeacherReviewSubmission)
                ElixPill(
                  text: 'Resubmission',
                  color: AppColors.accent,
                  compact: true,
                ),
            ],
          ),
          if (_isOfficialAttempt) ...[
            const SizedBox(height: AppSpacing.md),
            _OfficialRubricSection(attempt: attempt),
          ],
          if (_isTeacherReviewedAttempt) ...[
            const SizedBox(height: AppSpacing.md),
            _TeacherReviewedSection(
              attempt: attempt,
              viewerRole: widget.viewerRole,
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficialNoClipPreview extends StatelessWidget {
  const _OfficialNoClipPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'No recording. Official ELIXR scores live practice and does '
            'not save a video clip. Recorded previews are on Teacher-created '
            'assignments after you submit.',
            textAlign: TextAlign.center,
            style: AppTheme.body.copyWith(color: const Color(0xFFE8E8E8)),
          ),
        ),
      ),
    );
  }
}

class _OfficialRubricSection extends StatelessWidget {
  const _OfficialRubricSection({required this.attempt});

  final AssignmentAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final rubric = attempt.rubric;
    return Column(
      key: const Key('submission_official_rubric'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rubric != null) ...[
          Text(
            '${rubricTotalLabel(rubric.total)} · ${rubric.performanceLevel.label}',
            style: AppTheme.headingMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final criterion in RubricCriterion.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${criterion.label}: ${rubric.scoreFor(criterion)}/3',
                style: AppTheme.body,
              ),
            ),
        ] else
          Text(
            'Official guided score is not available for this submission.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
        if (attempt.durationSeconds != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Duration ${formatTrainingDuration(attempt.durationSeconds!)}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        if (attempt.completedAt != null)
          Text(
            'Completed ${formatSubmissionTimestamp(attempt.completedAt!)}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
      ],
    );
  }
}

class _TeacherReviewedSection extends StatelessWidget {
  const _TeacherReviewedSection({
    required this.attempt,
    required this.viewerRole,
  });

  final AssignmentAttempt attempt;
  final SubmissionDetailViewerRole viewerRole;

  static Widget video({
    required BuildContext context,
    required bool clipBytesGone,
    required bool shouldOfferPlayback,
    required SubmissionPlaybackFile? playable,
    required Object? playableError,
    required ElixrPlaybackSession playbackSession,
    VoidCallback? onRetry,
  }) {
    if (clipBytesGone) {
      return Center(
        key: const Key('submission_retention_empty'),
        child: Text(
          'This clip was removed after ELIXR\'s retention window. '
          'Unreviewed submissions are kept for '
          '${AssignmentSubmissionLimits.unreviewedRetention.inDays} days. '
          'Reviewed submissions are kept for '
          '${AssignmentSubmissionLimits.reviewedRetention.inDays} days after '
          'review. Status, timestamps, and feedback remain available.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: AppColors.warning),
        ),
      );
    }
    if (!shouldOfferPlayback) {
      return Center(
        child: Text(
          'No submission clip is attached to this work.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
      );
    }
    if (playableError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This clip could not be opened.',
              style: AppTheme.body.copyWith(color: AppColors.error),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Button(
                key: const Key('submission_clip_retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      );
    }
    if (playable == null) {
      return const Center(child: ProgressRing());
    }
    return ElixrVideoPlayer(source: playable.uri, session: playbackSession);
  }

  @override
  Widget build(BuildContext context) {
    final feedback = attempt.reviewFeedback?.trim();
    final reviewed =
        attempt.status == AssignmentAttemptStatus.approved ||
        attempt.status == AssignmentAttemptStatus.needsRetry;
    final checked = attempt.isChecked;
    final reviewLabel = viewerRole == SubmissionDetailViewerRole.teacher
        ? 'Review'
        : 'Teacher review';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attempt.submittedAt != null)
          Text(
            'Submitted ${formatSubmissionTimestamp(attempt.submittedAt!)}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        if (attempt.videoDurationMs != null)
          Text(
            'Clip ${formatSubmissionDurationMs(attempt.videoDurationMs!)}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        if (reviewed) ...[
          const SizedBox(height: AppSpacing.md),
          Text('$reviewLabel: ${_verdictLabel(attempt)}', style: AppTheme.body),
          if (attempt.reviewedAt != null)
            Text(
              'Reviewed ${formatSubmissionTimestamp(attempt.reviewedAt!)}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              feedback,
              key: const Key('submission_review_feedback'),
              style: AppTheme.body,
            ),
          ],
        ],
        if (checked) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Score: ${attempt.gradeScore}/${attempt.gradeMaxScore}',
            key: const Key('submission_grade'),
            style: AppTheme.headingMedium,
          ),
          if (attempt.checkedAt != null)
            Text(
              'Checked ${formatSubmissionTimestamp(attempt.checkedAt!)}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              feedback,
              key: const Key('submission_review_feedback'),
              style: AppTheme.body,
            ),
          ],
          if (attempt.resultSentForCurrentRevision)
            Text(
              'Result sent to you in Messages',
              key: const Key('submission_result_sent'),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
        ],
      ],
    );
  }

  static String _verdictLabel(AssignmentAttempt attempt) {
    return switch (attempt.reviewVerdict) {
      AssignmentReviewVerdict.approved => 'Approved',
      AssignmentReviewVerdict.needsRetry => 'Needs retry',
      null => attempt.status.wireValue,
    };
  }
}

String formatSubmissionTimestamp(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String formatSubmissionDurationMs(int durationMs) {
  final totalSeconds = durationMs < 0 ? 0 : (durationMs / 1000).round();
  return formatTrainingDuration(totalSeconds);
}
