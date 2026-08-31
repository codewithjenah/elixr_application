import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'assessment_mode.dart';
import 'assessment_spec.dart';
import 'movement_origin.dart';
import 'teacher_reviewed_movement_spec.dart';
import 'training_prop.dart';

enum GroupAssignmentStatus {
  active,
  archived;

  static GroupAssignmentStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Persistent audience for a classroom assignment.
///
/// New canonical writes include only `audience_type`. Target identities live
/// in the private `assignment_recipients` projection; pre-audience documents
/// remain classroom-wide for compatibility.
enum AssignmentAudienceType {
  entireClass('entire_class'),
  selectedStudents('selected_students'),
  individualStudent('individual_student');

  const AssignmentAudienceType(this.wireValue);

  final String wireValue;

  static AssignmentAudienceType? tryParse(String? value) {
    for (final type in values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

class AssignmentAudience {
  const AssignmentAudience.entireClass()
    : type = AssignmentAudienceType.entireClass,
      targetTraineeIds = const [];

  AssignmentAudience.selectedStudents(Iterable<String> targetTraineeIds)
    : this._(AssignmentAudienceType.selectedStudents, targetTraineeIds);

  AssignmentAudience.individualStudent(Iterable<String> targetTraineeIds)
    : this._(AssignmentAudienceType.individualStudent, targetTraineeIds);

  AssignmentAudience._(
    this.type,
    Iterable<String> targetTraineeIds, {
    bool allowUnresolved = false,
  }) : targetTraineeIds = List.unmodifiable(
         targetTraineeIds.map(_requireTraineeId),
       ) {
    final targets = this.targetTraineeIds;
    if (targets.toSet().length != targets.length ||
        ((type == AssignmentAudienceType.selectedStudents ||
                type == AssignmentAudienceType.individualStudent) &&
            targets.isEmpty &&
            !allowUnresolved) ||
        (type == AssignmentAudienceType.individualStudent &&
            targets.isNotEmpty &&
            targets.length != 1)) {
      throw ArgumentError.value(
        targetTraineeIds,
        'targetTraineeIds',
        'Target IDs do not match the assignment audience.',
      );
    }
  }

  final AssignmentAudienceType type;
  final List<String> targetTraineeIds;

  /// Targeted canonical documents are intentionally unresolved until the
  /// authorized caller hydrates recipient IDs from the private projection.
  bool get isResolved => isEntireClass || targetTraineeIds.isNotEmpty;

  bool get isEntireClass => type == AssignmentAudienceType.entireClass;

  bool isAvailableToTrainee(String traineeId) =>
      isEntireClass ||
      (isResolved && targetTraineeIds.contains(traineeId.trim()));

  Map<String, dynamic> toMap() => {'audience_type': type.wireValue};

  static AssignmentAudience? tryFromMap(Map<String, dynamic> map) {
    final hasType = map.containsKey('audience_type');
    // Embedded target lists were an undeployed, capped design. Do not revive
    // them or leak them from a canonical assignment document.
    if (map.containsKey('target_trainee_ids')) return null;
    if (!hasType) return const AssignmentAudience.entireClass();
    final type = AssignmentAudienceType.tryParse(
      map['audience_type'] is String ? map['audience_type'] as String : null,
    );
    if (type == null) return null;
    try {
      return switch (type) {
        AssignmentAudienceType.entireClass =>
          const AssignmentAudience.entireClass(),
        AssignmentAudienceType.selectedStudents => AssignmentAudience._(
          AssignmentAudienceType.selectedStudents,
          const [],
          allowUnresolved: true,
        ),
        AssignmentAudienceType.individualStudent => AssignmentAudience._(
          AssignmentAudienceType.individualStudent,
          const [],
          allowUnresolved: true,
        ),
      };
    } on ArgumentError {
      return null;
    }
  }

  AssignmentAudience withRecipientIds(Iterable<String> recipientIds) =>
      switch (type) {
        AssignmentAudienceType.entireClass =>
          const AssignmentAudience.entireClass(),
        AssignmentAudienceType.selectedStudents =>
          AssignmentAudience.selectedStudents(recipientIds),
        AssignmentAudienceType.individualStudent =>
          AssignmentAudience.individualStudent(recipientIds),
      };

  static String _requireTraineeId(String value) {
    final normalized = _tryTraineeId(value);
    if (normalized == null) {
      throw ArgumentError.value(
        value,
        'targetTraineeIds',
        'Invalid trainee ID.',
      );
    }
    return normalized;
  }

  static String? _tryTraineeId(String value) {
    final normalized = value.trim();
    return normalized.isEmpty || normalized.length > 128 ? null : normalized;
  }
}

/// Classroom assignment at `group_assignments/{assignmentId}`.
///
/// Trainees read this document (including the display snapshot) instead of
/// private Teacher movement/revision collections.
class GroupAssignment {
  const GroupAssignment({
    required this.id,
    required this.teacherId,
    required this.groupId,
    required this.movementId,
    required this.revisionId,
    required this.origin,
    required this.assessmentMode,
    required this.status,
    required this.displayTitle,
    required this.teacherDisplayName,
    required this.groupName,
    this.officialMovementName,
    this.displayInstructions,
    this.displaySafetyGuidance,
    this.allowedProp,
    this.assessmentSpec,
    this.maxScore,
    this.gradingLocked = false,
    this.gradingLockedAt,
    this.dueAt,
    this.createdAt,
    this.updatedAt,
    this.audience = const AssignmentAudience.entireClass(),
  });

  final String id;
  final String teacherId;
  final String groupId;
  final String movementId;
  final String revisionId;
  final MovementOrigin origin;
  final AssessmentMode assessmentMode;
  final GroupAssignmentStatus status;
  final String displayTitle;
  final String teacherDisplayName;
  final String groupName;
  final String? officialMovementName;
  final String? displayInstructions;
  final String? displaySafetyGuidance;
  final TrainingProp? allowedProp;

  /// Historical `assessment_spec` payload, parsed only for retired records.
  final AssessmentSpec? assessmentSpec;

  /// Maximum score for a Teacher-created recorded assignment.
  ///
  /// Older assignment documents did not persist a maximum. They are exposed
  /// as `/100` for compatibility, while all new Teacher-created assignments
  /// write the explicit field.
  final int? maxScore;
  final bool gradingLocked;
  final DateTime? gradingLockedAt;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AssignmentAudience audience;

  bool get isActive => status == GroupAssignmentStatus.active;
  bool get isOfficial => origin == MovementOrigin.officialElixr;
  bool get isTeacherCreated => origin == MovementOrigin.teacherCreated;
  bool get isRetiredTemplate => assessmentMode == AssessmentMode.templateScored;
  bool isAvailableToTrainee(String traineeId) =>
      audience.isAvailableToTrainee(traineeId);

  bool get isOverdue {
    final due = dueAt;
    if (due == null || !isActive) return false;
    return DateTime.now().toUtc().isAfter(due.toUtc());
  }

  GroupAssignment copyWith({
    GroupAssignmentStatus? status,
    int? maxScore,
    bool? gradingLocked,
    DateTime? gradingLockedAt,
    DateTime? dueAt,
    bool clearGradingLockedAt = false,
    bool clearDueAt = false,
    AssignmentAudience? audience,
  }) {
    return GroupAssignment(
      id: id,
      teacherId: teacherId,
      groupId: groupId,
      movementId: movementId,
      revisionId: revisionId,
      origin: origin,
      assessmentMode: assessmentMode,
      status: status ?? this.status,
      displayTitle: displayTitle,
      teacherDisplayName: teacherDisplayName,
      groupName: groupName,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions,
      displaySafetyGuidance: displaySafetyGuidance,
      allowedProp: allowedProp,
      assessmentSpec: assessmentSpec,
      maxScore: maxScore ?? this.maxScore,
      gradingLocked: gradingLocked ?? this.gradingLocked,
      gradingLockedAt: clearGradingLockedAt
          ? null
          : (gradingLockedAt ?? this.gradingLockedAt),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      createdAt: createdAt,
      updatedAt: updatedAt,
      audience: audience ?? this.audience,
    );
  }

  static GroupAssignment? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final teacherId = _readId(map['teacher_id']);
    final groupId = _readId(map['group_id']);
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
    final status = GroupAssignmentStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    final displayTitle = _readBounded(
      map['display_title'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
    );
    final teacherDisplayName = _readBounded(
      map['teacher_display_name'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
    );
    final groupName = _readBounded(
      map['group_name'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
    );
    if (teacherId == null ||
        groupId == null ||
        movementId == null ||
        revisionId == null ||
        origin == null ||
        assessmentMode == null ||
        status == null ||
        displayTitle == null ||
        teacherDisplayName == null ||
        groupName == null) {
      return null;
    }

    final audience = AssignmentAudience.tryFromMap(map);
    if (audience == null) return null;

    final officialName = _readBounded(
      map['official_movement_name'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
      allowEmpty: true,
    );
    if (origin == MovementOrigin.officialElixr) {
      if (officialName == null || officialName.isEmpty) return null;
      if (assessmentMode != AssessmentMode.officialGuided) return null;
      if (map.keys.any(
        (key) =>
            key == 'max_score' ||
            key == 'grading_locked' ||
            key == 'grading_locked_at',
      )) {
        return null;
      }
    } else {
      if (officialName != null) return null;
      if (assessmentMode != AssessmentMode.teacherReviewed &&
          assessmentMode != AssessmentMode.templateScored) {
        return null;
      }
    }

    TrainingProp? allowedProp;
    if (map.containsKey('allowed_prop')) {
      allowedProp = TrainingProp.tryParseStrict(map['allowed_prop']);
      if (allowedProp == null) return null;
    }

    AssessmentSpec? assessmentSpec;
    final hasAssessmentSpec = map.containsKey('assessment_spec');
    if (origin == MovementOrigin.officialElixr ||
        assessmentMode == AssessmentMode.teacherReviewed) {
      if (hasAssessmentSpec) return null;
    } else if (assessmentMode == AssessmentMode.templateScored) {
      if (!hasAssessmentSpec) return null;
      assessmentSpec = AssessmentSpec.tryFrom(map['assessment_spec']);
      if (assessmentSpec == null || !assessmentSpec.isCanonicalWristStallV1) {
        return null;
      }
      if (allowedProp != TrainingProp.bottle) return null;
      if (assessmentSpec.prop != AssessmentProp.bottle) return null;
    }

    int? maxScore;
    var gradingLocked = false;
    DateTime? gradingLockedAt;
    if (origin == MovementOrigin.teacherCreated &&
        assessmentMode == AssessmentMode.teacherReviewed) {
      if (map.containsKey('max_score')) {
        maxScore = _readScore(map['max_score']);
        if (maxScore == null) return null;
      } else {
        // Compatibility for Phase 5/6 records created before grading became
        // an explicit assignment-level contract.
        maxScore = 100;
      }
      if (map.containsKey('grading_locked')) {
        if (map['grading_locked'] is! bool) return null;
        gradingLocked = map['grading_locked'] as bool;
      }
      if (map.containsKey('grading_locked_at')) {
        gradingLockedAt = TeacherRosterInvite.readDateTime(
          map['grading_locked_at'],
        );
        if (gradingLockedAt == null || !gradingLocked) return null;
      }
    } else if (map.keys.any(
      (key) =>
          key == 'max_score' ||
          key == 'grading_locked' ||
          key == 'grading_locked_at',
    )) {
      return null;
    }

    return GroupAssignment(
      id: id,
      teacherId: teacherId,
      groupId: groupId,
      movementId: movementId,
      revisionId: revisionId,
      origin: origin,
      assessmentMode: assessmentMode,
      status: status,
      displayTitle: displayTitle,
      teacherDisplayName: teacherDisplayName,
      groupName: groupName,
      officialMovementName: officialName,
      displayInstructions: _readBounded(
        map['display_instructions'],
        maxLength: TeacherReviewedMovementSpec.instructionsMaxLength,
        allowEmpty: true,
      ),
      displaySafetyGuidance: _readBounded(
        map['display_safety_guidance'],
        maxLength: TeacherReviewedMovementSpec.safetyGuidanceMaxLength,
        allowEmpty: true,
      ),
      allowedProp: allowedProp,
      assessmentSpec: assessmentSpec,
      maxScore: maxScore,
      gradingLocked: gradingLocked,
      gradingLockedAt: gradingLockedAt,
      dueAt: TeacherRosterInvite.readDateTime(map['due_at']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      audience: audience,
    );
  }

  static String? _readId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  static String? _readBounded(
    Object? value, {
    required int maxLength,
    bool allowEmpty = false,
  }) {
    if (value == null) return allowEmpty ? null : null;
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return allowEmpty ? null : null;
    if (trimmed.length > maxLength) return null;
    return trimmed;
  }

  static int? _readScore(Object? value) {
    if (value is! int || value < 1 || value > 100) return null;
    return value;
  }
}
