import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/assignment_review_state.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingAttemptStreamRepository
    extends InMemoryClassroomAssignmentRepository {
  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return Stream<List<AssignmentAttempt>>.error(
      StateError('attempt stream unavailable'),
    );
  }
}

class _BlockingAssignmentUpdateRepository
    extends InMemoryClassroomAssignmentRepository {
  final started = Completer<void>();
  final release = Completer<void>();
  var updateCalls = 0;

  @override
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
    String? topic,
  }) async {
    updateCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.updateAssignmentSettings(
      teacherId: teacherId,
      assignmentId: assignmentId,
      dueAt: dueAt,
      maxScore: maxScore,
      topic: topic,
    );
  }
}

class _BlockingReviewRepository extends InMemoryClassroomAssignmentRepository {
  final started = Completer<void>();
  final release = Completer<void>();
  var saveCalls = 0;

  @override
  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  }) async {
    saveCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.saveTeacherReview(
      teacherId: teacherId,
      attempt: attempt,
      assignment: assignment,
      gradeScore: gradeScore,
      feedback: feedback,
      reviewedAt: reviewedAt,
    );
  }
}

class _FailingReviewRepository extends InMemoryClassroomAssignmentRepository {
  @override
  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  }) => throw StateError('save failed');
}

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;

  setUp(() {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
  });

  tearDown(() {
    groups.dispose();
    assignments.dispose();
  });

  TeacherClassworkController create({String? fixedTraineeId}) {
    return TeacherClassworkController(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      groupId: 'g1',
      groupRepository: groups,
      assignmentRepository: assignments,
      fixedTraineeId: fixedTraineeId,
      now: () => DateTime.utc(2026, 9, 2),
    );
  }

  GroupMembership member(
    String traineeId, {
    GroupMembershipStatus status = GroupMembershipStatus.approved,
  }) {
    return GroupMembership(
      id: GroupMembership.documentId(groupId: 'g1', traineeId: traineeId),
      groupId: 'g1',
      teacherId: 'teacher',
      traineeId: traineeId,
      traineeDisplayName: traineeId,
      teacherDisplayName: 'Grace Hopper',
      status: status,
    );
  }

  const assignment = GroupAssignment(
    id: 'a1',
    teacherId: 'teacher',
    groupId: 'g1',
    movementId: 'm1',
    revisionId: 'r1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Tin Balance',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    maxScore: 100,
  );

  AssignmentAttempt submitted(String traineeId) => AssignmentAttempt(
    id: 'submission-$traineeId',
    traineeId: traineeId,
    teacherId: 'teacher',
    groupId: 'g1',
    assignmentId: 'a1',
    movementId: 'm1',
    revisionId: 'r1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.submitted,
    submittedAt: DateTime.utc(2026, 8, 30),
    videoStoragePath:
        'assignment_submissions/teacher/g1/a1/$traineeId/submission-$traineeId.mp4',
    videoContentType: 'video/mp4',
    videoSizeBytes: 2048,
    videoDurationMs: 4000,
    videoExpiresAt: DateTime.utc(2026, 9, 30),
  );

  AssignmentAttempt canonicalSubmitted(
    String traineeId, {
    DateTime? submittedAt,
  }) => AssignmentAttempt(
    id: assignmentAttemptIdForCanonicalTeacherReviewSubmission(
      assignmentId: 'a1',
      traineeId: traineeId,
    ),
    traineeId: traineeId,
    teacherId: 'teacher',
    groupId: 'g1',
    assignmentId: 'a1',
    movementId: 'm1',
    revisionId: 'r1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.submitted,
    submittedAt: submittedAt ?? DateTime.utc(2026, 8, 30),
    videoStoragePath:
        'assignment_submissions/teacher/g1/a1/$traineeId/canonical.mp4',
    videoExpiresAt: DateTime.utc(2026, 10, 1),
  );

  test('filters assignments and roster to the opened classroom', () async {
    groups.seedMembership(member('ada'));
    groups.seedMembership(
      member('pending', status: GroupMembershipStatus.pending),
    );
    assignments.seedAssignment(assignment);
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'other',
        teacherId: 'teacher',
        groupId: 'g2',
        movementId: 'm1',
        revisionId: 'r1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Other work',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'Other',
        maxScore: 100,
      ),
    );
    assignments.seedAttempt(submitted('ada'));
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.assignments.map((item) => item.id), ['a1']);
    expect(controller.approvedMemberships.map((item) => item.traineeId), [
      'ada',
    ]);
    final counts = controller.rosterCountsFor('a1');
    expect(counts.turnedIn, 1);
    expect(counts.awaitingCheck, 1);
    expect(counts.notTurnedIn, 0);
  });

  test('latest visible work is selected per student', () async {
    groups.seedMembership(member('ada'));
    groups.seedMembership(member('alan'));
    assignments.seedAssignment(assignment);
    assignments.seedAttempt(submitted('ada'));
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(
      controller
          .latestVisibleAttemptFor(assignmentId: 'a1', traineeId: 'ada')
          ?.id,
      'submission-ada',
    );
    expect(
      controller.latestVisibleAttemptFor(assignmentId: 'a1', traineeId: 'alan'),
      isNull,
    );
  });

  test('roster states partition only the targeted approved audience', () async {
    groups.seedMembership(member('ada'));
    groups.seedMembership(member('alan'));
    groups.seedMembership(member('outside'));
    assignments.seedAssignment(
      assignment.copyWith(
        audience: AssignmentAudience.selectedStudents(const ['ada', 'alan']),
      ),
    );
    assignments.seedAttempt(canonicalSubmitted('ada'));
    final checked = canonicalSubmitted('alan').copyWith(
      status: AssignmentAttemptStatus.checked,
      gradeScore: 90,
      gradeMaxScore: 100,
      checkedAt: DateTime.utc(2026, 9, 1),
      reviewRevision: 1,
    );
    assignments.seedAttempt(checked);
    assignments.seedAttempt(canonicalSubmitted('outside'));
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);

    final entries = controller.rosterEntriesFor('a1');
    expect(entries.map((entry) => entry.membership.traineeId), ['ada', 'alan']);
    expect(entries.map((entry) => entry.reviewState), [
      AssignmentReviewState.toReview,
      AssignmentReviewState.checked,
    ]);
    final counts = controller.rosterCountsFor('a1');
    expect(counts.awaitingCheck, 1);
    expect(counts.checked, 1);
    expect(counts.notTurnedIn, 0);
  });

  test(
    'Save & Next checks current work before selecting the oldest pending',
    () async {
      groups.seedMembership(member('ada'));
      groups.seedMembership(member('alan'));
      groups.seedMembership(member('grace'));
      assignments.seedAssignment(assignment);
      final current = canonicalSubmitted(
        'ada',
        submittedAt: DateTime.utc(2026, 9, 1, 10),
      );
      assignments.seedAttempt(current);
      assignments.seedAttempt(
        canonicalSubmitted('alan', submittedAt: DateTime.utc(2026, 9, 1, 12)),
      );
      assignments.seedAttempt(
        canonicalSubmitted('grace', submittedAt: DateTime.utc(2026, 9, 1, 11)),
      );
      final controller = create();
      addTearDown(controller.dispose);
      await controller.start();
      await Future<void>.delayed(Duration.zero);
      await controller.selectAssignment('a1');
      await controller.selectTrainee('ada');

      expect(
        await controller.saveReviewAndNext(
          attempt: current,
          assignment: assignment,
          gradeScore: 91,
        ),
        isTrue,
      );
      expect(
        (await assignments.getAttempt(attemptId: current.id))?.status,
        AssignmentAttemptStatus.checked,
      );
      expect(controller.selectedTraineeId, 'grace');
      expect(
        controller
            .pendingReviewAttemptsFor('a1')
            .map((attempt) => attempt.traineeId),
        ['grace', 'alan'],
      );
    },
  );

  test(
    'Save & Next does not advance on failure or duplicate a busy write',
    () async {
      groups.seedMembership(member('ada'));
      groups.seedMembership(member('alan'));

      assignments.dispose();
      final failing = _FailingReviewRepository();
      assignments = failing;
      assignments.seedAssignment(assignment);
      final failedCurrent = canonicalSubmitted('ada');
      assignments.seedAttempt(failedCurrent);
      assignments.seedAttempt(canonicalSubmitted('alan'));
      var controller = create();
      await controller.start();
      await Future<void>.delayed(Duration.zero);
      await controller.selectAssignment('a1');
      await controller.selectTrainee('ada');
      expect(
        await controller.saveReviewAndNext(
          attempt: failedCurrent,
          assignment: assignment,
          gradeScore: 80,
        ),
        isFalse,
      );
      expect(controller.selectedTraineeId, 'ada');
      controller.dispose();

      assignments.dispose();
      final blocking = _BlockingReviewRepository();
      assignments = blocking;
      assignments.seedAssignment(assignment);
      final current = canonicalSubmitted('ada');
      assignments.seedAttempt(current);
      assignments.seedAttempt(canonicalSubmitted('alan'));
      controller = create();
      addTearDown(controller.dispose);
      await controller.start();
      await Future<void>.delayed(Duration.zero);
      await controller.selectAssignment('a1');
      await controller.selectTrainee('ada');

      final first = controller.saveReviewAndNext(
        attempt: current,
        assignment: assignment,
        gradeScore: 80,
      );
      await blocking.started.future;
      expect(
        await controller.saveReviewAndNext(
          attempt: current,
          assignment: assignment,
          gradeScore: 80,
        ),
        isFalse,
      );
      expect(blocking.saveCalls, 1);
      expect(controller.selectedTraineeId, 'ada');
      blocking.release.complete();
      expect(await first, isTrue);
      expect(controller.selectedTraineeId, 'alan');
    },
  );

  test('fixed student must have approved membership', () async {
    groups.seedMembership(member('ada', status: GroupMembershipStatus.pending));
    assignments.seedAssignment(assignment);
    assignments.seedAttempt(submitted('ada'));
    final controller = create(fixedTraineeId: 'ada');
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.unauthorized, isTrue);
    expect(controller.fixedStudentAuthorized, isFalse);
    expect(controller.assignments, isEmpty);
    expect(controller.attemptsFor('a1'), isEmpty);
  });

  test(
    'route-selected trainee survives provisional membership data and clears after confirmed removal',
    () async {
      assignments.seedAssignment(assignment);
      final memberships = ValueNotifier<List<GroupMembership>>(const []);
      var membershipsReady = false;
      final controller = TeacherClassworkController(
        teacherId: 'teacher',
        teacherDisplayName: 'Grace Hopper',
        groupId: 'g1',
        groupRepository: groups,
        assignmentRepository: assignments,
        initialAssignmentId: 'a1',
        initialTraineeId: 'ada',
        approvedMembershipsProvider: () => memberships.value,
        approvedMembershipsListenable: memberships,
        approvedMembershipsReady: () => membershipsReady,
      );
      addTearDown(controller.dispose);
      addTearDown(memberships.dispose);

      await controller.start();
      expect(controller.selectedAssignmentId, 'a1');
      expect(controller.selectedTraineeId, 'ada');

      membershipsReady = true;
      memberships.value = [member('ada')];
      await Future<void>.delayed(Duration.zero);
      expect(controller.selectedTraineeId, 'ada');

      memberships.value = const [];
      await Future<void>.delayed(Duration.zero);
      expect(controller.selectedTraineeId, isNull);
    },
  );

  test('submitted teacher-reviewed work can be graded', () async {
    groups.seedMembership(member('ada'));
    assignments.seedAssignment(assignment);
    assignments.seedAttempt(submitted('ada'));
    final controller = create(fixedTraineeId: 'ada');
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);
    final attempt = controller.latestVisibleAttemptFor(
      assignmentId: 'a1',
      traineeId: 'ada',
    )!;
    await controller.saveReview(
      attempt: attempt,
      assignment: assignment,
      gradeScore: 88,
      feedback: 'Controlled finish.',
    );

    final checked = await assignments.getAttempt(attemptId: attempt.id);
    expect(checked?.status, AssignmentAttemptStatus.checked);
    expect(checked?.gradeScore, 88);
    expect(checked?.reviewFeedback, 'Controlled finish.');
  });

  test('changing selection releases the local playback file', () async {
    groups.seedMembership(member('ada'));
    assignments.seedAssignment(assignment);
    final attempt = submitted('ada');
    assignments.seedAttempt(attempt);
    final cache = await Directory.systemTemp.createTemp('classwork-cache-');
    addTearDown(() async {
      if (await cache.exists()) await cache.delete(recursive: true);
    });
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      reviewCacheDirectory: cache,
    );
    final controller = TeacherClassworkController(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      groupId: 'g1',
      groupRepository: groups,
      assignmentRepository: assignments,
      submissionRepository: submissions,
      initialAssignmentId: 'a1',
      initialTraineeId: 'ada',
    );
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);

    final playback = await controller.openLocalPlayback(attempt);
    expect(playback, isNotNull);
    expect(await File(playback!.localPath).exists(), isTrue);
    await controller.selectTrainee(null);
    expect(await File(playback.localPath).exists(), isFalse);
  });

  test('result sending remains idempotent for a checked revision', () async {
    groups.seedMembership(member('ada'));
    assignments.seedAssignment(assignment);
    assignments.seedAttempt(submitted('ada'));
    final chat = InMemoryChatRepository();
    addTearDown(chat.dispose);
    final controller = TeacherClassworkController(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      groupId: 'g1',
      groupRepository: groups,
      assignmentRepository: assignments,
      chatRepository: chat,
      fixedTraineeId: 'ada',
    );
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);
    final ready = controller.latestVisibleAttemptFor(
      assignmentId: 'a1',
      traineeId: 'ada',
    )!;
    await controller.saveReview(
      attempt: ready,
      assignment: assignment,
      gradeScore: 90,
    );
    final checked = controller.latestVisibleAttemptFor(
      assignmentId: 'a1',
      traineeId: 'ada',
    )!;
    await controller.sendReviewResult(attempt: checked, assignment: assignment);
    final sent = controller.latestVisibleAttemptFor(
      assignmentId: 'a1',
      traineeId: 'ada',
    )!;
    await controller.sendReviewResult(attempt: sent, assignment: assignment);

    expect(sent.resultSentForCurrentRevision, isTrue);
    expect(chat.messages.values, hasLength(1));
  });

  test('attempt stream failure exposes unavailable status', () async {
    assignments.dispose();
    assignments = _FailingAttemptStreamRepository();
    groups.seedMembership(member('ada'));
    assignments.seedAssignment(assignment);
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.hasAttemptLoadError('a1'), isTrue);
    expect(
      controller.errorMessage,
      'Some classwork status could not be loaded. Try again.',
    );
  });

  test(
    'assignment edits report not saved while another write is busy',
    () async {
      assignments.dispose();
      final blockingAssignments = _BlockingAssignmentUpdateRepository();
      assignments = blockingAssignments;
      assignments.seedAssignment(assignment);
      final controller = create();
      addTearDown(controller.dispose);
      await controller.start();
      await Future<void>.delayed(Duration.zero);

      final firstSave = controller.updateAssignmentSettings(
        assignment,
        dueAt: DateTime.utc(2026, 9, 15),
      );
      await blockingAssignments.started.future;

      final secondSaved = await controller.updateAssignmentSettings(
        assignment,
        dueAt: DateTime.utc(2026, 9, 16),
      );
      expect(secondSaved, isFalse);
      expect(blockingAssignments.updateCalls, 1);
      expect(
        controller.errorMessage,
        'Another classwork action is still saving. Wait and try again.',
      );

      blockingAssignments.release.complete();
      expect(await firstSave, isTrue);
      expect(controller.errorMessage, isNull);
    },
  );
}
