import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/models/elixr_group.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/movement_origin.dart';
import '../models/teacher_movement.dart';
import '../models/training_prop.dart';

abstract class ClassroomAssignmentRepository {
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  });

  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    DateTime? dueAt,
  });

  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Future<GroupAssignment?> getAssignment({required String assignmentId});

  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  });

  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  });

  Future<AssignmentAttempt?> getAttempt({required String attemptId});

  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  });
}

void ensureTeacherOwnsActiveGroup({
  required String teacherId,
  required ElixrGroup group,
}) {
  if (group.teacherId != teacherId) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
  if (!group.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
}

Map<String, dynamic> officialAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required String officialMovementName,
  required String displayInstructions,
  DateTime? dueAt,
  required Object createdAt,
  required Object updatedAt,
}) {
  final identity = officialElixrIdentityForName(officialMovementName);
  if (identity == null) {
    throw ClassroomException(
      ClassroomError.unofficial,
      'Not an official ELIXR movement.',
    );
  }
  return {
    'teacher_id': teacherId,
    'group_id': group.id,
    'movement_id': identity.movementId,
    'revision_id': identity.revisionId,
    'origin': MovementOrigin.officialElixr.wireValue,
    'assessment_mode': AssessmentMode.officialGuided.wireValue,
    'status': GroupAssignmentStatus.active.name,
    'official_movement_name': identity.catalogName,
    'display_title': identity.catalogName,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (displayInstructions.trim().isNotEmpty)
      'display_instructions': displayInstructions.trim(),
    'due_at': ?dueAt,
  };
}

Map<String, dynamic> teacherCreatedAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required TeacherMovement movement,
  required TeacherMovementRevision revision,
  DateTime? dueAt,
  required Object createdAt,
  required Object updatedAt,
}) {
  if (movement.teacherId != teacherId || revision.teacherId != teacherId) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
  if (revision.movementId != movement.id) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!movement.isActive) {
    throw const ClassroomException(ClassroomError.archived);
  }
  if (revision.id != movement.currentRevisionId) {
    throw const ClassroomException(
      ClassroomError.identityMismatch,
      'Assign the current revision of this movement.',
    );
  }
  return {
    'teacher_id': teacherId,
    'group_id': group.id,
    'movement_id': movement.id,
    'revision_id': revision.id,
    'origin': MovementOrigin.teacherCreated.wireValue,
    'assessment_mode': revision.assessmentMode.wireValue,
    'status': GroupAssignmentStatus.active.name,
    'display_title': movement.title,
    'display_instructions': revision.spec.instructions,
    'display_safety_guidance': ?revision.spec.safetyGuidance,
    'allowed_prop': revision.spec.requiredProp.protocolValue,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'due_at': ?dueAt,
  };
}

AssignmentAttempt teacherCreatedDraftAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  DateTime? createdAt,
}) {
  if (!assignment.isTeacherCreated) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!assignment.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
  return AssignmentAttempt(
    id: assignmentAttemptIdForTeacherCreatedDraft(
      assignmentId: assignment.id,
      traineeId: traineeId,
    ),
    traineeId: traineeId,
    teacherId: assignment.teacherId,
    groupId: assignment.groupId,
    assignmentId: assignment.id,
    movementId: assignment.movementId,
    revisionId: assignment.revisionId,
    origin: MovementOrigin.teacherCreated,
    assessmentMode: assignment.assessmentMode,
    attemptKind: AssignmentAttemptKind.teacherReviewDraft,
    status: AssignmentAttemptStatus.inProgress,
    createdAt: createdAt,
  );
}

TrainingProp? assignmentAllowedProp(GroupAssignment assignment) {
  return assignment.allowedProp;
}
