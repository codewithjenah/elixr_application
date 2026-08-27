import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../../../data/models/assignment_submission_limits.dart';
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
    if (controller.phase != SubmissionRecordingPhase.submitted) return;
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
          Button(
            onPressed: widget.cameraReady && controller.canRecord && !busy
                ? controller.requestConsent
                : null,
            child: const Text('Record Submission'),
          ),
        ];
      case SubmissionRecordingPhase.consent:
        return [
          Text(
            'This clip is recorded only for this assignment. The assigning '
            'Teacher can review it. Maximum about '
            '${AssignmentSubmissionLimits.maxDurationSeconds} seconds. It is '
            'not public, does not award XP, and ordinary practice stays '
            'unrecorded.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: widget.cameraReady && !busy
                ? controller.beginRecording
                : null,
            child: busy
                ? const Text('Starting…')
                : const Text('Start recording'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Button(
            onPressed: busy ? null : controller.cancelConsent,
            child: const Text('Cancel'),
          ),
        ];
      case SubmissionRecordingPhase.recording:
        final remaining =
            AssignmentSubmissionLimits.maxDurationSeconds -
            controller.elapsedSeconds;
        return [
          Text(
            'Recording ${controller.elapsedSeconds}s · ${remaining.clamp(0, AssignmentSubmissionLimits.maxDurationSeconds)}s left',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: busy ? null : controller.stopRecording,
            child: busy
                ? const Text('Stopping…')
                : const Text('Stop recording'),
          ),
        ];
      case SubmissionRecordingPhase.preview:
        final clip = controller.clip;
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
          FilledButton(
            onPressed: busy ? null : () => _confirmSubmit(context),
            child: const Text('Submit to Teacher'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Button(
            onPressed: busy
                ? null
                : () => controller.retake(
                    releasePlayback: _previewPlayback.release,
                  ),
            child: const Text('Retake'),
          ),
        ];
      case SubmissionRecordingPhase.submitting:
        return const [
          Center(child: ProgressRing()),
          SizedBox(height: AppSpacing.sm),
          Text('Uploading submission…'),
        ];
      case SubmissionRecordingPhase.submitted:
        return [
          Text(
            'Submitted to your Teacher. Preview your clip below. '
            'This clip does not award XP.',
            style: AppTheme.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(height: 180, child: _submittedVideo()),
          const SizedBox(height: AppSpacing.sm),
          Button(
            onPressed: () => context.go(
              AppRoutePaths.assignmentDetail(controller.assignment.id),
            ),
            child: const Text('Open assignment'),
          ),
        ];
      case SubmissionRecordingPhase.failed:
        return [
          Button(
            onPressed: busy
                ? null
                : () => controller.retake(
                    releasePlayback: _previewPlayback.release,
                  ),
            child: const Text('Try again'),
          ),
        ];
    }
  }

  Future<void> _confirmSubmit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Submit this clip?'),
        content: const Text(
          'The assigning Teacher will be able to play this assignment clip. '
          'It is not public and does not award XP.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit to Teacher'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _previewPlayback.release();
      await controller.submitToTeacher();
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
