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
    this.dueAt,
    this.createdAt,
    this.updatedAt,
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
  final AssessmentSpec? assessmentSpec;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == GroupAssignmentStatus.active;
  bool get isOfficial => origin == MovementOrigin.officialElixr;
  bool get isTeacherCreated => origin == MovementOrigin.teacherCreated;

  bool get isOverdue {
    final due = dueAt;
    if (due == null || !isActive) return false;
    return DateTime.now().toUtc().isAfter(due.toUtc());
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

    final officialName = _readBounded(
      map['official_movement_name'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
      allowEmpty: true,
    );
    if (origin == MovementOrigin.officialElixr) {
      if (officialName == null || officialName.isEmpty) return null;
      if (assessmentMode != AssessmentMode.officialGuided) return null;
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
      dueAt: TeacherRosterInvite.readDateTime(map['due_at']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
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
}
