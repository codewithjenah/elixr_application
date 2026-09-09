import 'dart:async';

import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/assignment_review_state.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_controller.dart';
import 'package:elixr_application/features/practice/submission_recording_controller.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_assignment_composer.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _LifecycleAssignmentRepository
    extends InMemoryClassroomAssignmentRepository {
  _LifecycleAssignmentRepository({required InMemoryGroupRepository groups})
    : super(
        groupRepository: groups,
        generateId: () => 'activity-assignment',
        now: () => DateTime.utc(2026, 9, 9, 8),
      );

  int submitWrites = 0;
  int rubricReviewWrites = 0;
  bool blockRubricReview = false;
  final rubricReviewStarted = Completer<void>();
  final rubricReviewRelease = Completer<void>();

  @override
  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    submitWrites++;
    return super.markTeacherReviewSubmitted(
      traineeId: traineeId,
      attempt: attempt,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
  }

  @override
  Future<AssignmentAttempt> saveTeacherActivityRubricReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required Map<String, int> criterionScores,
    String? feedback,
  }) async {
    rubricReviewWrites++;
    if (blockRubricReview) {
      if (!rubricReviewStarted.isCompleted) rubricReviewStarted.complete();
      await rubricReviewRelease.future;
    }
    return super.saveTeacherActivityRubricReview(
      teacherId: teacherId,
      attempt: attempt,
      criterionScores: criterionScores,
      feedback: feedback,
    );
  }
}

class _GatedRecordingSocket extends WebSocketService {
  int startCalls = 0;
  int stopCalls = 0;
  final startAck = Completer<CommandAck>();
  final stopAck = Completer<CommandAck>();

  @override
  Future<CommandAck> sendStartSubmissionRecord({
    String? sessionId,
    int durationSeconds = 30,
  }) {
    startCalls++;
    return startAck.future;
  }

  @override
  Future<CommandAck> sendStopSubmissionRecord({String? sessionId}) {
    stopCalls++;
    return stopAck.future;
  }

  @override
  Future<CommandAck> sendCancelSubmissionRecord({String? sessionId}) async {
    return const CommandAck(
      protocolVersion: 1,
      requestId: 'cancel-recording',
      action: 'cancel_submission_record',
      accepted: true,
    );
  }
}

void main() {
  test(
    'Teacher Activity lifecycle is targeted, single-submit, and checked once',
    () async {
      final groups = InMemoryGroupRepository();
      final movements = InMemoryTeacherMovementRepository(
        generateId: () => 'teacher-movement',
        now: () => DateTime.utc(2026, 9, 9, 8),
      );
      final assignments = _LifecycleAssignmentRepository(groups: groups);
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 9, 9, 8, 30),
      );
      final socket = _GatedRecordingSocket();

      const group = ElixrGroup(
        id: 'classroom',
        teacherId: 'teacher',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      );
      groups.seedGroup(group);
      for (final trainee in const [
        ('trainee-a', 'Ada Lovelace'),
        ('trainee-b', 'Alan Turing'),
      ]) {
        groups.seedMembership(
          GroupMembership(
            id: GroupMembership.documentId(
              groupId: group.id,
              traineeId: trainee.$1,
            ),
            groupId: group.id,
            teacherId: group.teacherId,
            traineeId: trainee.$1,
            traineeDisplayName: trainee.$2,
            teacherDisplayName: 'Grace Hopper',
            status: GroupMembershipStatus.approved,
          ),
        );
      }

      final assessment = TeacherActivityAssessmentConfig.newActivityDefaults();
      final movement = await movements.createMovement(
        teacherId: 'teacher',
        title: 'Bottle Control Activity',
        instructions: 'Keep the bottle controlled from setup to finish.',
        requiredProp: TrainingProp.bottle,
        assessment: assessment,
      );
      final assignment =
          await TeacherAssignmentCreationService(
            teacherId: 'teacher',
            teacherDisplayName: 'Grace Hopper',
            assignmentRepository: assignments,
            movementRepository: movements,
            groupRepository: groups,
          ).create(
            group: group,
            teacherCreatedMovement: movement,
            audience: AssignmentAudience.individualStudent(const ['trainee-a']),
            activityAssessment: assessment,
            attemptPolicy: const AssignmentAttemptPolicy.finite(2),
            maxScore: assessment.rubric.maximumScore,
          );

      final assignedToA = AssignedMovementsController(
        traineeId: 'trainee-a',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      final assignedToB = AssignedMovementsController(
        traineeId: 'trainee-b',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      await assignedToA.start();
      await assignedToB.start();
      expect(assignedToA.items.single.assignment.id, assignment.id);
      expect(assignedToB.items, isEmpty);

      final detailForA = AssignmentDetailController(
        assignmentId: assignment.id,
        traineeId: 'trainee-a',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      final detailForB = AssignmentDetailController(
        assignmentId: assignment.id,
        traineeId: 'trainee-b',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      await detailForA.start();
      await detailForB.start();
      expect(detailForA.authorized, isTrue);
      expect(detailForB.authorized, isFalse);
      expect(assignments.attempts, isEmpty);

      final teacherClasswork = TeacherClassworkController(
        teacherId: 'teacher',
        teacherDisplayName: 'Grace Hopper',
        groupId: group.id,
        groupRepository: groups,
        assignmentRepository: assignments,
        now: () => DateTime.utc(2026, 9, 9, 9),
      );
      await teacherClasswork.start();

      final reserved = await assignments.reserveTeacherActivityAttempt(
        traineeId: 'trainee-a',
        assignment: assignment,
        requestId: 'open-activity-once',
      );
      final duplicateReservation = await assignments
          .reserveTeacherActivityAttempt(
            traineeId: 'trainee-a',
            assignment: assignment,
            requestId: 'open-activity-once',
          );
      expect(duplicateReservation.id, reserved.id);
      expect(
        assignments.teacherActivityConsumedCount(
          assignmentId: assignment.id,
          traineeId: 'trainee-a',
        ),
        0,
      );
      expect(assignments.attempts, hasLength(1));

      final recording = SubmissionRecordingController(
        websocket: socket,
        classroom: assignments,
        submissions: submissions,
        assignment: assignment,
        traineeId: 'trainee-a',
        recordingCountdown: Duration.zero,
      )..latestSubmission = reserved;

      final firstStart = recording.beginActivityRecordingNow();
      final duplicateStart = recording.beginActivityRecordingNow();
      socket.startAck.complete(
        const CommandAck(
          protocolVersion: 1,
          requestId: 'start-recording',
          action: 'start_submission_record',
          accepted: true,
          sessionId: 'recording-session',
        ),
      );
      await Future.wait([firstStart, duplicateStart]);
      expect(socket.startCalls, 1);
      expect(
        assignments.teacherActivityConsumedCount(
          assignmentId: assignment.id,
          traineeId: 'trainee-a',
        ),
        1,
      );

      final firstStop = recording.stopRecording();
      final duplicateStop = recording.stopRecording();
      socket.stopAck.complete(
        const CommandAck(
          protocolVersion: 1,
          requestId: 'stop-recording',
          action: 'stop_submission_record',
          accepted: true,
          sessionId: 'recording-session',
          localFilePath: r'C:\Temp\elixr-submission.mp4',
          videoDurationMs: 5000,
          videoSizeBytes: 2048,
          contentType: 'video/mp4',
        ),
      );
      await Future.wait([firstStop, duplicateStop]);
      await pumpEventQueue();

      expect(socket.stopCalls, 1);
      expect(assignments.submitWrites, 1);
      expect(assignments.attempts, hasLength(1));
      final submitted = (await assignments.getAttempt(attemptId: reserved.id))!;
      expect(submitted.status, AssignmentAttemptStatus.submitted);
      expect(submitted.activityAssessmentSnapshot?.toMap(), assessment.toMap());
      expect(
        teacherClasswork.pendingReviewAttemptsFor(assignment.id).single.id,
        submitted.id,
      );
      expect(
        teacherClasswork.rosterEntriesFor(assignment.id).single.reviewState,
        AssignmentReviewState.toReview,
      );

      final scores = {
        for (final criterion
            in submitted.activityAssessmentSnapshot!.rubric.criteria)
          criterion.id: criterion.maximumPoints,
      };
      assignments.blockRubricReview = true;
      final firstSave = teacherClasswork.saveTeacherActivityRubricReviewAndNext(
        attempt: submitted,
        assignment: assignment,
        criterionScores: scores,
        feedback: 'Controlled and complete.',
      );
      await assignments.rubricReviewStarted.future;
      final duplicateSave = teacherClasswork
          .saveTeacherActivityRubricReviewAndNext(
            attempt: submitted,
            assignment: assignment,
            criterionScores: scores,
            feedback: 'Controlled and complete.',
          );
      assignments.rubricReviewRelease.complete();
      expect(await firstSave, isTrue);
      expect(await duplicateSave, isFalse);
      await pumpEventQueue();

      expect(assignments.rubricReviewWrites, 1);
      final checked = (await assignments.getAttempt(attemptId: submitted.id))!;
      expect(checked.status, AssignmentAttemptStatus.checked);
      expect(checked.criterionScores, scores);
      expect(checked.activityAssessmentSnapshot?.toMap(), assessment.toMap());
      expect(teacherClasswork.pendingReviewAttemptsFor(assignment.id), isEmpty);
      expect(
        teacherClasswork.rosterEntriesFor(assignment.id).single.reviewState,
        AssignmentReviewState.checked,
      );
      expect(
        detailForA.latestClipSubmission?.status,
        AssignmentAttemptStatus.checked,
      );
      expect(detailForA.latestClipSubmission?.criterionScores, scores);

      recording.dispose();
      socket.dispose();
      teacherClasswork.dispose();
      detailForA.dispose();
      detailForB.dispose();
      assignedToA.dispose();
      assignedToB.dispose();
      assignments.dispose();
      movements.dispose();
      groups.dispose();
    },
  );
}
