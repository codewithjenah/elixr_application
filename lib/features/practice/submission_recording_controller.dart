import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/assignment_attempt.dart';
import '../../data/models/assignment_submission_limits.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/websocket_service.dart';

enum SubmissionRecordingPhase {
  idle,
  consent,
  recording,
  preview,
  submitting,
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
  });

  final WebSocketService websocket;
  final ClassroomAssignmentRepository classroom;
  final AssignmentSubmissionRepository submissions;
  final GroupAssignment assignment;
  final String traineeId;

  SubmissionRecordingPhase phase = SubmissionRecordingPhase.idle;
  SubmissionRecordResult? clip;
  String? errorMessage;
  int elapsedSeconds = 0;
  AssignmentAttempt? latestSubmission;
  Timer? _timer;
  bool _recordCommandInFlight = false;
  bool _disposed = false;
  SubmissionPlaybackFile? _submittedPlayback;

  bool get recordCommandInFlight => _recordCommandInFlight;

  bool get canRecord {
    final current = latestSubmission;
    if (current == null) return true;
    if (current.status == AssignmentAttemptStatus.submitted) return false;
    if (current.status == AssignmentAttemptStatus.approved) return false;
    return true;
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

  Future<void> refreshLatestSubmission() async {
    final attempts = await classroom
        .watchAttemptsForTrainee(traineeId: traineeId)
        .first;
    AssignmentAttempt? latest;
    for (final attempt in attempts) {
      if (attempt.assignmentId != assignment.id) continue;
      if (!attempt.isTeacherReviewSubmission) continue;
      if (attempt.isAbandonedTeacherReviewDraft) continue;
      if (latest == null ||
          (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
            latest.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        latest = attempt;
      }
    }
    latestSubmission = latest;
    if (latest?.status == AssignmentAttemptStatus.submitted ||
        latest?.status == AssignmentAttemptStatus.approved) {
      if (phase == SubmissionRecordingPhase.idle ||
          phase == SubmissionRecordingPhase.failed) {
        phase = SubmissionRecordingPhase.submitted;
      }
    }
    notifyListeners();
  }

  Future<SubmissionPlaybackFile?> openSubmittedPlayback() async {
    await releaseSubmittedPlayback();
    final attempt = latestSubmission;
    if (attempt == null || !attempt.hasPlayableVideo || attempt.videoExpired) {
      return null;
    }
    final playback = await submissions.openLocalPlayback(attempt);
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

  Future<void> beginRecording() async {
    if (!_acquireRecordCommand()) return;
    errorMessage = null;
    try {
      final ack = await websocket.sendStartSubmissionRecord();
      if (_disposed) return;
      if (!ack.accepted) {
        phase = SubmissionRecordingPhase.failed;
        errorMessage = ack.message ?? ack.errorCode ?? 'Recording failed.';
        return;
      }
      elapsedSeconds = 0;
      phase = SubmissionRecordingPhase.recording;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds += 1;
        notifyListeners();
        if (elapsedSeconds >= AssignmentSubmissionLimits.maxDurationSeconds) {
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
      phase = SubmissionRecordingPhase.preview;
    } catch (_) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = 'Could not stop recording.';
    } finally {
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
    } finally {
      _releaseRecordCommand();
    }
  }

  Future<void> submitToTeacher() async {
    final current = clip;
    if (current == null) return;
    if (!_acquireRecordCommand()) return;
    phase = SubmissionRecordingPhase.submitting;
    errorMessage = null;
    try {
      String? supersedesId;
      await refreshLatestSubmission();
      final previous = latestSubmission;
      if (previous != null &&
          previous.status == AssignmentAttemptStatus.needsRetry) {
        supersedesId = previous.id;
      }
      await submissions.submitLocalClip(
        traineeId: traineeId,
        assignment: assignment,
        clip: current,
        supersedesAttemptId: supersedesId,
      );
      await abandonLocalClip();
      if (_disposed) return;
      clip = null;
      phase = SubmissionRecordingPhase.submitted;
      await refreshLatestSubmission();
      await openSubmittedPlayback();
    } catch (error) {
      if (_disposed) return;
      phase = SubmissionRecordingPhase.failed;
      errorMessage = error.toString();
    } finally {
      _releaseRecordCommand();
    }
  }

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

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(releaseSubmittedPlayback());
    unawaited(abandonLocalClip());
    super.dispose();
  }
}
