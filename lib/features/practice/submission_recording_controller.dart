import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/assignment_attempt.dart';
import '../../data/models/assignment_submission_limits.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/teacher_activity_assessment.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/websocket_service.dart';

enum SubmissionRecordingPhase {
  idle,
  consent,
  countdown,
  recording,
  preview,
  submitting,
  attached,
  submitted,
  failed,
}

/// Deletes a local MP4 after playback has released it.
///
/// On Windows, Media Foundation may keep the file open until the player
/// controller is disposed. [releasePlayback] must complete first. Retries
/// cover a short residual lock; orphan temp cleanup remains a last resort.
Future<void> deleteLocalClipAfterPlaybackRelease({
  required String path,
  Future<void> Function()? releasePlayback,
  Future<void> Function(Duration delay)? delay,
  Future<void> Function(String path)? deleteFile,
  int retries = 5,
}) async {
  if (releasePlayback != null) {
    await releasePlayback();
  }
  final wait = delay ?? Future<void>.delayed;
  final doDelete =
      deleteFile ??
      (target) async {
        final file = File(target);
        if (await file.exists()) {
          await file.delete();
        }
      };
  for (var attempt = 0; attempt < retries; attempt++) {
    try {
      await doDelete(path);
      return;
    } on FileSystemException {
      if (attempt == retries - 1) return;
      await wait(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}

/// Trainee Record Submission state machine. Does not write sessions or XP.
class SubmissionRecordingController extends ChangeNotifier {
  SubmissionRecordingController({
    required this.websocket,
    required this.classroom,
    required this.submissions,
    required this.assignment,
    required this.traineeId,
    this.onRecordingModeStarted,
    this.onRecordingModeEnded,
    this.recordingCountdown = const Duration(seconds: 3),
  });

  final WebSocketService websocket;
  final ClassroomAssignmentRepository classroom;
  final AssignmentSubmissionRepository submissions;
  final GroupAssignment assignment;
  final String traineeId;
  final VoidCallback? onRecordingModeStarted;
  final VoidCallback? onRecordingModeEnded;
  final Duration recordingCountdown;

  SubmissionRecordingPhase phase = SubmissionRecordingPhase.idle;
  SubmissionRecordResult? clip;
  String? errorMessage;
  int elapsedSeconds = 0;
  int recordingCountdownSeconds = 0;
  AssignmentAttempt? latestSubmission;
  Timer? _timer;
  bool _recordCommandInFlight = false;
  bool _recordingModeActive = false;
  bool _disposed = false;
  SubmissionPlaybackFile? _submittedPlayback;

  bool get recordCommandInFlight => _recordCommandInFlight;

  /// A configured assessment marks the new Teacher Activity flow. Legacy
  /// teacher-created assignments retain their private-draft workflow.
  bool get isTeacherActivity => assignment.activityAssessment != null;

  /// A submitted Activity keeps the exact assessment configuration that
  /// applied to that attempt. Before the attempt exists, use the published
  /// assignment configuration to prepare the recording experience.
  TeacherActivityAssessmentConfig? get activityAssessment =>
      latestSubmission?.activityAssessmentSnapshot ??
      assignment.activityAssessment;

  int get recordingDurationSeconds => isTeacherActivity
      ? assignment.activityAssessment!.recordingDurationSeconds
      : AssignmentSubmissionLimits.maxDurationSeconds;

  bool get canRecord {
    final current = latestSubmission;
    return current == null ||
        current.status == AssignmentAttemptStatus.draft ||
        current.status == AssignmentAttemptStatus.inProgress;
  }

  String? get needsRetryFeedback {
    final current = latestSubmission;
    if (current == null) return null;
    if (current.status != AssignmentAttemptStatus.needsRetry) return null;
    return current.reviewFeedback;
  }

  bool _acquireRecordCommand() {
    if (_disposed || _recordCommandInFlight) return false;
    _recordCommandInFlight = true;
    notifyListeners();
    return true;
  }

  void _releaseRecordCommand() {
    _recordCommandInFlight = false;
    if (!_disposed) notifyListeners();
  }

  void _startRecordingMode() {
    if (_recordingModeActive) return;
    _recordingModeActive = true;
    onRecordingModeStarted?.call();
  }

  void _endRecordingMode() {
    if (!_recordingModeActive) return;
    _recordingModeActive = false;
    onRecordingModeEnded?.call();
  }

  Future<void> refreshLatestSubmission() async {
    final attempts = await classroom
        .watchAttemptsForTrainee(traineeId: traineeId)
        .first;
    if (isTeacherActivity) {
      final activityAttempts =
          [
            for (final attempt in attempts)
              if (attempt.assignmentId == assignment.id &&
                  attempt.activityAssessmentSnapshot != null &&
                  !attempt.isAbandonedTeacherReviewDraft)
                attempt,
          ]..sort((a, b) {
            final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bAt.compareTo(aAt);
          });
      final latest = activityAttempts.isEmpty ? null : activityAttempts.first;
      if (_isStalePreSubmissionSnapshot(latest)) return;
      latestSubmission = latest;
      if (latest?.status == AssignmentAttemptStatus.submitted ||
          latest?.status == AssignmentAttemptStatus.checked ||
          latest?.status == AssignmentAttemptStatus.unsubmitting ||
          latest?.status == AssignmentAttemptStatus.approved ||
          latest?.status == AssignmentAttemptStatus.needsRetry) {
        if (phase == SubmissionRecordingPhase.idle ||
            phase == SubmissionRecordingPhase.failed) {
          phase = SubmissionRecordingPhase.submitted;
        }
      } else if (latest?.hasAttachedDraftClip == true &&
          (phase == SubmissionRecordingPhase.idle ||
              phase == SubmissionRecordingPhase.failed)) {
        phase = SubmissionRecordingPhase.attached;
      }
      notifyListeners();
      return;
    }
    AssignmentAttempt? canonical;
    AssignmentAttempt? legacy;
    for (final attempt in attempts) {
      if (attempt.assignmentId != assignment.id) continue;
      if (!attempt.isTeacherReviewSubmission) continue;
      if (attempt.isAbandonedTeacherReviewDraft) continue;
      if (attempt.isCanonicalTeacherReviewSubmission) {
        canonical = attempt;
      } else if (legacy == null ||
          (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
            legacy.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        legacy = attempt;
      }
    }
    final latest = canonical ?? legacy;
    if (_isStalePreSubmissionSnapshot(latest)) return;
    latestSubmission = latest;
    if (latest?.status == AssignmentAttemptStatus.submitted ||
        latest?.status == AssignmentAttemptStatus.checked ||
        latest?.status == AssignmentAttemptStatus.unsubmitting ||
        latest?.status == AssignmentAttemptStatus.approved ||
        latest?.status == AssignmentAttemptStatus.needsRetry) {
      if (phase == SubmissionRecordingPhase.idle ||
          phase == SubmissionRecordingPhase.failed) {
        phase = SubmissionRecordingPhase.submitted;
      }
    } else if (latest?.hasAttachedDraftClip == true &&
        (phase == SubmissionRecordingPhase.idle ||
            phase == SubmissionRecordingPhase.failed)) {
      phase = SubmissionRecordingPhase.attached;
    }
    notifyListeners();
  }

  /// Keeps a command-confirmed submission from being replaced by the initial
  /// cached Firestore snapshot, which can still describe the same attempt as
  /// `in_progress` immediately after its submission transition.
  bool _isStalePreSubmissionSnapshot(AssignmentAttempt? latest) {
    final confirmed = latestSubmission;
    return confirmed != null &&
        confirmed.status == AssignmentAttemptStatus.submitted &&
        latest != null &&
        latest.id == confirmed.id &&
        latest.status == AssignmentAttemptStatus.inProgress;
  }

  Future<SubmissionPlaybackFile?> openSubmittedPlayback({
    AssignmentAttempt? attempt,
  }) async {
    await releaseSubmittedPlayback();
    final submission = attempt ?? latestSubmission;
    if (submission == null ||
        !submission.hasPlayableVideo ||
        submission.videoExpired) {
      return null;
    }
    final playback = await submissions.openLocalPlayback(submission);
    if (_disposed) {
      await submissions.releaseLocalPlayback(playback);
      return null;
    }
    _submittedPlayback = playback;
    notifyListeners();
    return playback;
  }

  Future<void> releaseSubmittedPlayback() async {
    final playback = _submittedPlayback;
    _submittedPlayback = null;
    await submissions.releaseLocalPlayback(playback);
  }

  SubmissionPlaybackFile? get submittedPlayback => _submittedPlayback;

  void requestConsent() {
    if (!canRecord || _recordCommandInFlight) return;
    errorMessage = null;
    phase = SubmissionRecordingPhase.consent;
    notifyListeners();
  }

  void cancelConsent() {
    if (phase != SubmissionRecordingPhase.consent || _recordCommandInFlight) {
      return;
    }
    phase = SubmissionRecordingPhase.idle;
    notifyListeners();
  }

  Future<void> beginRecording() => _beginRecording(skipCountdown: false);

  /// Starts an Activity recording after the camera readiness countdown has
  /// already completed in [LivePracticeScreen]. Legacy submissions keep their
  /// own consent/countdown flow through [beginRecording].
  Future<void> beginActivityRecordingNow() =>
      _beginRecording(skipCountdown: true);

  Future<void> _beginRecording({required bool skipCountdown}) async {
    if (!_acquireRecordCommand()) return;
    errorMessage = null;
    try {
      if (!skipCountdown) {
        recordingCountdownSeconds = recordingCountdown.inSeconds;
        phase = SubmissionRecordingPhase.countdown;
        notifyListeners();
        while (recordingCountdownSeconds > 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (_disposed) return;
          recordingCountdownSeconds -= 1;
          notifyListeners();
        }
      }
      final ack = isTeacherActivity
          ? await websocket.sendStartSubmissionRecord(
              durationSeconds: recordingDurationSeconds,
            )
          : await websocket.sendStartSubmissionRecord();
      if (_disposed) return;
      if (!ack.accepted) {
        phase = SubmissionRecordingPhase.failed;
        errorMessage = ack.message ?? ack.errorCode ?? 'Recording failed.';
        return;
      }
      if (isTeacherActivity) {
        await refreshLatestSubmission();
        final reserved = latestSubmission;
        if (reserved?.activityAssessmentSnapshot == null) {
          phase = SubmissionRecordingPhase.failed;
          errorMessage =
              'Your Teacher Activity could not reserve an attempt. Try again.';
          await websocket.sendCancelSubmissionRecord();
          return;
        }
        try {
          await classroom.consumeTeacherActivityAttempt(
            traineeId: traineeId,
            attempt: reserved!,
          );
        } catch (_) {
          phase = SubmissionRecordingPhase.failed;
          errorMessage =
              'Your Teacher Activity is no longer available for recording.';
          await websocket.sendCancelSubmissionRecord();
          return;
        }
      }
      elapsedSeconds = 0;
      phase = SubmissionRecordingPhase.recording;
      _startRecordingMode();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds += 1;
        notifyListeners();
        if (elapsedSeconds >= recordingDurationSeconds) {
          unawaited(stopRecording());
        }
      });
    } catch (_) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = 'Recording failed. Check the backend and try again.';
    } finally {
      _releaseRecordCommand();
    }
  }

  Future<void> stopRecording() async {
    if (!_acquireRecordCommand()) return;
    _timer?.cancel();
    _timer = null;
    try {
      final ack = await websocket.sendStopSubmissionRecord();
      if (_disposed) return;
      if (!ack.accepted) {
        phase = SubmissionRecordingPhase.failed;
        errorMessage =
            ack.message ?? ack.errorCode ?? 'Could not stop recording.';
        return;
      }
      clip = SubmissionRecordResult.fromAck(ack);
      if (isTeacherActivity) {
        await _saveActivityClip();
      } else {
        phase = SubmissionRecordingPhase.preview;
      }
    } catch (_) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = 'Could not stop recording.';
    } finally {
      _endRecordingMode();
      _releaseRecordCommand();
    }
  }

  Future<void> retake({Future<void> Function()? releasePlayback}) async {
    if (!_acquireRecordCommand()) return;
    try {
      await abandonLocalClip(releasePlayback: releasePlayback);
      if (_disposed) return;
      clip = null;
      elapsedSeconds = 0;
      errorMessage = null;
      phase = SubmissionRecordingPhase.idle;
      _endRecordingMode();
    } finally {
      _releaseRecordCommand();
    }
  }

  /// Uploads the selected clip as private attached work. Turning it in is a
  /// separate confirmation on the assignment detail screen.
  Future<void> saveDraft() async {
    final current = clip;
    if (current == null) return;
    if (!_acquireRecordCommand()) return;
    phase = SubmissionRecordingPhase.submitting;
    errorMessage = null;
    try {
      await refreshLatestSubmission();
      final attached = await submissions.saveCanonicalLocalClipDraft(
        traineeId: traineeId,
        assignment: assignment,
        clip: current,
      );
      latestSubmission = attached;
      phase = SubmissionRecordingPhase.attached;
      notifyListeners();
      await abandonLocalClip();
      if (_disposed) return;
      clip = null;
      await openSubmittedPlayback(attempt: attached);
    } catch (error) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = error.toString();
    } finally {
      _releaseRecordCommand();
    }
  }

  /// Uploads and turns in a v2 Teacher Activity as one trainee action. The
  /// underlying repository operations remain separate for compatibility with
  /// the legacy private-draft flow.
  Future<void> _saveActivityClip() async {
    final current = clip;
    if (current == null) return;
    phase = SubmissionRecordingPhase.submitting;
    errorMessage = null;
    notifyListeners();
    try {
      await refreshLatestSubmission();
      final reserved = latestSubmission;
      if (reserved?.activityAssessmentSnapshot == null) {
        throw StateError('No reserved Teacher Activity attempt is available.');
      }
      final submitted = await submissions.submitTeacherActivityAttemptClip(
        traineeId: traineeId,
        assignment: assignment,
        attempt: reserved!,
        clip: current,
      );
      latestSubmission = submitted;
      phase = SubmissionRecordingPhase.submitted;
      await abandonLocalClip();
      if (_disposed) return;
      clip = null;
      await openSubmittedPlayback(attempt: submitted);
    } catch (error) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = error.toString();
    }
  }

  Future<void> retryActivitySubmission() async {
    final current = latestSubmission;
    if (!isTeacherActivity ||
        current?.activityAssessmentSnapshot == null ||
        clip == null) {
      return;
    }
    if (!_acquireRecordCommand()) return;
    try {
      await _saveActivityClip();
    } finally {
      _releaseRecordCommand();
    }
  }

  /// Compatibility entry point for callers that still use the old name.
  Future<void> submitToTeacher() => saveDraft();

  Future<void> abandonLocalClip({
    Future<void> Function()? releasePlayback,
  }) async {
    final path = clip?.localPath;
    clip = null;
    try {
      await websocket.sendCancelSubmissionRecord();
    } catch (_) {}
    if (path != null && path.isNotEmpty) {
      await deleteLocalClipAfterPlaybackRelease(
        path: path,
        releasePlayback: releasePlayback,
      );
    }
  }

  Future<void> releaseActivityAttempt() async {
    final attempt = latestSubmission;
    if (!isTeacherActivity ||
        attempt == null ||
        attempt.activityAssessmentSnapshot == null ||
        attempt.status != AssignmentAttemptStatus.inProgress) {
      return;
    }
    try {
      await classroom.abandonTeacherActivityAttempt(
        traineeId: traineeId,
        attempt: attempt,
      );
    } catch (_) {
      // Server state remains authoritative and the same attempt may be retried.
    }
  }

  Future<void> reserveActivityAttempt() async {
    if (!isTeacherActivity) return;
    final reserved = await classroom.reserveTeacherActivityAttempt(
      traineeId: traineeId,
      assignment: assignment,
      requestId:
          'activity-readiness-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    latestSubmission = reserved;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _endRecordingMode();
    unawaited(releaseSubmittedPlayback());
    unawaited(abandonLocalClip());
    super.dispose();
  }
}
