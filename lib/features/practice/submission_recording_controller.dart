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

  Future<void> refreshLatestSubmission() async {
    final attempts = await classroom
        .watchAttemptsForTrainee(traineeId: traineeId)
        .first;
    AssignmentAttempt? latest;
    for (final attempt in attempts) {
      if (attempt.assignmentId != assignment.id) continue;
      if (!attempt.isTeacherReviewSubmission) continue;
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

  void requestConsent() {
    if (!canRecord) return;
    errorMessage = null;
    phase = SubmissionRecordingPhase.consent;
    notifyListeners();
  }

  void cancelConsent() {
    if (phase != SubmissionRecordingPhase.consent) return;
    phase = SubmissionRecordingPhase.idle;
    notifyListeners();
  }

  Future<void> beginRecording() async {
    errorMessage = null;
    try {
      final ack = await websocket.sendStartSubmissionRecord();
      if (!ack.accepted) {
        phase = SubmissionRecordingPhase.failed;
        errorMessage = ack.message ?? ack.errorCode ?? 'Recording failed.';
        notifyListeners();
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
      notifyListeners();
    } catch (_) {
      phase = SubmissionRecordingPhase.failed;
      errorMessage = 'Recording failed. Check the backend and try again.';
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    _timer?.cancel();
    _timer = null;
    try {
      final ack = await websocket.sendStopSubmissionRecord();
      if (!ack.accepted) {
        phase = SubmissionRecordingPhase.failed;
        errorMessage =
            ack.message ?? ack.errorCode ?? 'Could not stop recording.';
        notifyListeners();
        return;
      }
      clip = SubmissionRecordResult.fromAck(ack);
      phase = SubmissionRecordingPhase.preview;
      notifyListeners();
    } catch (_) {
      phase = SubmissionRecordingPhase.failed;
      errorMessage = 'Could not stop recording.';
      notifyListeners();
    }
  }

  Future<void> retake() async {
    await abandonLocalClip();
    clip = null;
    elapsedSeconds = 0;
    phase = SubmissionRecordingPhase.idle;
    notifyListeners();
  }

  Future<void> submitToTeacher() async {
    final current = clip;
    if (current == null) return;
    phase = SubmissionRecordingPhase.submitting;
    errorMessage = null;
    notifyListeners();
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
      clip = null;
      phase = SubmissionRecordingPhase.submitted;
      await refreshLatestSubmission();
    } catch (error) {
      phase = SubmissionRecordingPhase.failed;
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> abandonLocalClip() async {
    final path = clip?.localPath;
    clip = null;
    try {
      await websocket.sendCancelSubmissionRecord();
    } catch (_) {}
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      } on FileSystemException {
        // Backend cancel also removes the temp file.
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(abandonLocalClip());
    super.dispose();
  }
}
