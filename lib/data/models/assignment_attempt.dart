import 'package:elixr_core/models/rubric_assessment.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'assessment_mode.dart';
import 'movement_origin.dart';
import 'training_prop.dart';

enum AssignmentAttemptKind {
  practicePointer('practice_pointer'),
  teacherReviewDraft('teacher_review_draft');

  const AssignmentAttemptKind(this.wireValue);

  final String wireValue;

  static AssignmentAttemptKind? tryParse(String? value) {
    if (value == null) return null;
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

enum AssignmentAttemptStatus {
  draft('draft'),
  inProgress('in_progress'),
  submitted('submitted');

  const AssignmentAttemptStatus(this.wireValue);

  final String wireValue;

  static AssignmentAttemptStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

/// Classroom attempt at `assignment_attempts/{attemptId}`.
///
/// `awards_global_xp` is always false. Official pointers copy sanitized
/// Assessment V2 fields from the source session so the assigning Teacher can
/// see results without Progress Access or a public profile.
class AssignmentAttempt {
  const AssignmentAttempt({
    required this.id,
    required this.traineeId,
    required this.teacherId,
    required this.groupId,
    required this.assignmentId,
    required this.movementId,
    required this.revisionId,
    required this.origin,
    required this.assessmentMode,
    required this.attemptKind,
    required this.status,
    this.awardsGlobalXp = false,
    this.sourceSessionId,
    this.rubric,
    this.durationSeconds,
    this.propType,
    this.completedAt,
    this.createdAt,
  });

  final String id;
  final String traineeId;
  final String teacherId;
  final String groupId;
  final String assignmentId;
  final String movementId;
  final String revisionId;
  final MovementOrigin origin;
  final AssessmentMode assessmentMode;
  final AssignmentAttemptKind attemptKind;
  final AssignmentAttemptStatus status;
  final bool awardsGlobalXp;
  final String? sourceSessionId;
  final RubricAssessment? rubric;
  final int? durationSeconds;
  final TrainingProp? propType;
  final DateTime? completedAt;
  final DateTime? createdAt;

  int? get rubricTotal => rubric?.total;
  PerformanceLevel? get performanceLevel => rubric?.performanceLevel;

  Map<String, dynamic> toCreateMap({required Object createdAt}) {
    final map = <String, dynamic>{
      'trainee_id': traineeId,
      'teacher_id': teacherId,
      'group_id': groupId,
      'assignment_id': assignmentId,
      'movement_id': movementId,
      'revision_id': revisionId,
      'origin': origin.wireValue,
      'assessment_mode': assessmentMode.wireValue,
      'attempt_kind': attemptKind.wireValue,
      'status': status.wireValue,
      'awards_global_xp': false,
      'created_at': createdAt,
    };
    if (sourceSessionId != null) {
      map['source_session_id'] = sourceSessionId;
    }
    if (rubric != null) {
      map.addAll(rubric!.toFirestoreFields());
    }
    if (durationSeconds != null) {
      map['duration_seconds'] = durationSeconds;
    }
    if (propType != null) {
      map['prop_type'] = propType!.protocolValue;
    }
    if (completedAt != null) {
      map['completed_at'] = completedAt;
    }
    return map;
  }

  static AssignmentAttempt? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final traineeId = _readId(map['trainee_id']);
    final teacherId = _readId(map['teacher_id']);
    final groupId = _readId(map['group_id']);
    final assignmentId = _readId(map['assignment_id']);
    final movementId = _readId(map['movement_id']);
    final revisionId = _readId(map['revision_id']);
    final origin = MovementOrigin.tryParse(
      map['origin'] is String ? map['origin'] as String : null,
    );
    final assessmentMode = AssessmentMode.tryParse(
      map['assessment_mode'] is String
          ? map['assessment_mode'] as String
          : null,
    );
    final attemptKind = AssignmentAttemptKind.tryParse(
      map['attempt_kind'] is String ? map['attempt_kind'] as String : null,
    );
    final status = AssignmentAttemptStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    if (traineeId == null ||
        teacherId == null ||
        groupId == null ||
        assignmentId == null ||
        movementId == null ||
        revisionId == null ||
        origin == null ||
        assessmentMode == null ||
        attemptKind == null ||
        status == null) {
      return null;
    }
    if (map['awards_global_xp'] != false) return null;

    final sourceSessionId = _readId(map['source_session_id']);
    if (attemptKind == AssignmentAttemptKind.practicePointer) {
      if (sourceSessionId == null) return null;
      if (origin != MovementOrigin.officialElixr) return null;
      if (status != AssignmentAttemptStatus.submitted) return null;
    } else if (sourceSessionId != null) {
      return null;
    }

    return AssignmentAttempt(
      id: id,
      traineeId: traineeId,
      teacherId: teacherId,
      groupId: groupId,
      assignmentId: assignmentId,
      movementId: movementId,
      revisionId: revisionId,
      origin: origin,
      assessmentMode: assessmentMode,
      attemptKind: attemptKind,
      status: status,
      awardsGlobalXp: false,
      sourceSessionId: sourceSessionId,
      rubric: RubricAssessment.tryFromFirestore(map),
      durationSeconds: _readInt(map['duration_seconds']),
      propType: map.containsKey('prop_type')
          ? TrainingProp.tryParseStrict(map['prop_type'])
          : null,
      completedAt: TeacherRosterInvite.readDateTime(map['completed_at']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
    );
  }

  static String? _readId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }
}
