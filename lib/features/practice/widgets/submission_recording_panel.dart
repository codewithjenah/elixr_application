import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../submission_recording_controller.dart';

class SubmissionRecordingPanel extends StatefulWidget {
  const SubmissionRecordingPanel({
    super.key,
    required this.controller,
    required this.cameraReady,
  });

  final SubmissionRecordingController controller;
  final bool cameraReady;

  @override
  State<SubmissionRecordingPanel> createState() =>
      _SubmissionRecordingPanelState();
}

class _SubmissionRecordingPanelState extends State<SubmissionRecordingPanel> {
  final _previewPlayback = ElixrPlaybackSession();
  final _submittedPlayback = ElixrPlaybackSession();
  bool _loadingSubmittedClip = false;
  Object? _submittedClipError;

  SubmissionRecordingController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    unawaited(_ensureSubmittedClip());
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    unawaited(_previewPlayback.release());
    unawaited(_submittedPlayback.release());
    unawaited(controller.releaseSubmittedPlayback());
    super.dispose();
  }

  void _onController() {
    unawaited(_ensureSubmittedClip());
  }

  Future<void> _ensureSubmittedClip() async {
    if (controller.phase != SubmissionRecordingPhase.submitted &&
        controller.phase != SubmissionRecordingPhase.attached) {
      return;
    }
    if (controller.submittedPlayback != null) return;
    if (_loadingSubmittedClip) return;
    final attempt = controller.latestSubmission;
    if (attempt == null || !attempt.hasPlayableVideo || attempt.videoExpired) {
      return;
    }
    _loadingSubmittedClip = true;
    _submittedClipError = null;
    if (mounted) setState(() {});
    try {
      await controller.openSubmittedPlayback();
    } catch (error) {
      _submittedClipError = error;
    } finally {
      _loadingSubmittedClip = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final feedback = controller.needsRetryFeedback;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (feedback != null &&
                controller.phase == SubmissionRecordingPhase.idle) ...[
              Text('Teacher feedback', style: AppTheme.caption),
              const SizedBox(height: 4),
              Text(feedback, style: AppTheme.body),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (controller.errorMessage != null) ...[
              Text(
                controller.errorMessage!,
                style: AppTheme.bodySecondary.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ..._body(context),
          ],
        );
      },
    );
  }

  List<Widget> _body(BuildContext context) {
    final busy = controller.recordCommandInFlight;
    switch (controller.phase) {
      case SubmissionRecordingPhase.idle:
        return [
          ElixPrimaryButton(
            label: controller.isTeacherActivity
                ? 'Start Activity recording'
                : 'Record Submission',
            onPressed: widget.cameraReady && controller.canRecord && !busy
                ? (controller.isTeacherActivity
                      ? controller.beginRecording
                      : controller.requestConsent)
                : null,
          ),
        ];
      case SubmissionRecordingPhase.consent:
        return [
          Text(
            'This clip is recorded only for this assignment. The assigning '
            'Teacher can review it. Maximum about '
            '${controller.recordingDurationSeconds} seconds. It is '
            'not public, does not award XP, and ordinary practice stays '
            'unrecorded.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElixPrimaryButton(
            label: busy ? 'Starting…' : 'Start recording',
            isLoading: busy,
            onPressed: widget.cameraReady && !busy
                ? controller.beginRecording
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          ElixPrimaryButton(
            label: 'Cancel',
            variant: ElixButtonVariant.outline,
            onPressed: busy ? null : controller.cancelConsent,
          ),
        ];
      case SubmissionRecordingPhase.countdown:
        return [
          Text(
            'Get ready — recording starts in '
            '${controller.recordingCountdownSeconds}…',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          const ProgressRing(),
        ];
      case SubmissionRecordingPhase.recording:
        final limit = controller.recordingDurationSeconds;
        final remaining = limit - controller.elapsedSeconds;
        return [
          Text(
            'Recording ${controller.elapsedSeconds}s · ${remaining.clamp(0, limit)}s left',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          ElixPrimaryButton(
            label: busy ? 'Stopping…' : 'Stop recording',
            isLoading: busy,
            variant: ElixButtonVariant.destructive,
            onPressed: busy ? null : controller.stopRecording,
          ),
        ];
      case SubmissionRecordingPhase.preview:
        final clip = controller.clip;
        if (controller.isTeacherActivity) {
          return const [
            Center(child: ProgressRing()),
            SizedBox(height: AppSpacing.sm),
            Text('Submitting your Activity recording…'),
          ];
        }
        return [
          if (clip != null)
            SizedBox(
              height: 180,
              child: ElixrVideoPlayer(
                source: Uri.file(clip.localPath),
                session: _previewPlayback,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          ElixPrimaryButton(
            label: 'Use this recording',
            onPressed: busy ? null : () => _confirmSubmit(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          ElixPrimaryButton(
            label: 'Retake',
            variant: ElixButtonVariant.outline,
            onPressed: busy
                ? null
                : () => controller.retake(
                    releasePlayback: _previewPlayback.release,
                  ),
          ),
        ];
      case SubmissionRecordingPhase.submitting:
        return const [
          Center(child: ProgressRing()),
          SizedBox(height: AppSpacing.sm),
          Text('Saving recording…'),
        ];
      case SubmissionRecordingPhase.attached:
        if (controller.isTeacherActivity) {
          return [
            Text(
              'Your Activity recording is waiting to be sent to your Teacher.',
              style: AppTheme.body,
            ),
            const SizedBox(height: AppSpacing.sm),
            ElixPrimaryButton(
              label: 'Retry automatic submission',
              variant: ElixButtonVariant.outline,
              onPressed: busy ? null : controller.retryActivitySubmission,
            ),
          ];
        }
        return [
          Text(
            'Recording attached. Turn it in from the assignment page when you are ready.',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(height: 180, child: _submittedVideo()),
          const SizedBox(height: AppSpacing.sm),
          ElixPrimaryButton(
            label: 'Open assignment',
            variant: ElixButtonVariant.outline,
            onPressed: () => context.go(
              AppRoutePaths.assignmentDetail(controller.assignment.id),
            ),
          ),
        ];
      case SubmissionRecordingPhase.submitted:
        return [
          Text(
            controller.isTeacherActivity
                ? 'Your Activity recording was submitted to your Teacher for review.'
                : 'Submitted to your Teacher. Preview your clip below. '
                      'This clip does not award XP.',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(height: 180, child: _submittedVideo()),
          const SizedBox(height: AppSpacing.sm),
          ElixPrimaryButton(
            label: 'Open assignment',
            variant: ElixButtonVariant.outline,
            onPressed: () => context.go(
              AppRoutePaths.assignmentDetail(controller.assignment.id),
            ),
          ),
        ];
      case SubmissionRecordingPhase.failed:
        final canRetryActivityUpload =
            controller.isTeacherActivity &&
            controller.clip != null &&
            controller.latestSubmission?.activityAssessmentSnapshot != null;
        return [
          ElixPrimaryButton(
            label: canRetryActivityUpload
                ? 'Retry automatic submission'
                : 'Try again',
            variant: ElixButtonVariant.outline,
            onPressed: busy
                ? null
                : canRetryActivityUpload
                ? controller.retryActivitySubmission
                : () => controller.retake(
                    releasePlayback: _previewPlayback.release,
                  ),
          ),
        ];
    }
  }

  Future<void> _confirmSubmit(BuildContext context) async {
    final confirmed = await ElixDialog.confirm(
      context,
      title: 'Use this recording?',
      message:
          'This saves a private recording to Your work. It will not be sent '
          'to your Teacher until you choose Turn in on the assignment page.',
      confirmLabel: 'Use recording',
    );
    if (confirmed == true) {
      await _previewPlayback.release();
      await controller.saveDraft();
    }
  }

  Widget _submittedVideo() {
    final attempt = controller.latestSubmission;
    if (attempt == null || !attempt.hasPlayableVideo || attempt.videoExpired) {
      return Center(
        child: Text(
          attempt?.videoExpired == true
              ? 'This clip is no longer available.'
              : 'Your submitted clip will appear here after upload.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: AppColors.warning),
        ),
      );
    }
    if (_submittedClipError != null) {
      return Center(
        child: Text(
          'This clip could not be opened.',
          style: AppTheme.body.copyWith(color: AppColors.error),
        ),
      );
    }
    final playable = controller.submittedPlayback;
    if (_loadingSubmittedClip || playable == null) {
      return const Center(child: ProgressRing());
    }
    return ElixrVideoPlayer(source: playable.uri, session: _submittedPlayback);
  }
}
