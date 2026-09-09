import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'assessment_mode.dart';
import 'teacher_movement_revision_spec.dart';
import 'teacher_reviewed_movement_spec.dart';

enum TeacherMovementStatus {
  active,
  archived;

  static TeacherMovementStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

class TeacherMovement {
  static const currentSchemaVersion = 1;

  const TeacherMovement({
    required this.id,
    required this.teacherId,
    required this.title,
    required this.status,
    required this.currentRevisionId,
    this.createdAt,
    this.updatedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  final String id;
  final String teacherId;
  final String title;
  final TeacherMovementStatus status;
  final String currentRevisionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int schemaVersion;

  bool get isActive => status == TeacherMovementStatus.active;

  static TeacherMovement? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final teacherId = _readId(map['teacher_id']);
    final title = _readBounded(
      map['title'],
      maxLength: TeacherReviewedMovementSpec.titleMaxLength,
    );
    final status = TeacherMovementStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    final currentRevisionId = _readId(map['current_revision_id']);
    if (teacherId == null ||
        title == null ||
        status == null ||
        currentRevisionId == null) {
      return null;
    }
    return TeacherMovement(
      id: id,
      teacherId: teacherId,
      title: title,
      status: status,
      currentRevisionId: currentRevisionId,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      schemaVersion: _readInt(map['schema_version']) ?? currentSchemaVersion,
    );
  }

  static String? _readId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  static String? _readBounded(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }
}

class TeacherMovementRevision {
  const TeacherMovementRevision({
    required this.id,
    required this.movementId,
    required this.teacherId,
    required this.assessmentMode,
    required this.spec,
    this.schemaVersion = TeacherReviewedMovementSpec.currentSchemaVersion,
    this.createdAt,
  });

  final String id;
  final String movementId;
  final String teacherId;
  final AssessmentMode assessmentMode;
  final TeacherMovementRevisionSpec spec;
  final int schemaVersion;
  final DateTime? createdAt;

  /// True only for a historical revision that must not be edited, assigned,
  /// archived, or executed.
  bool get isRetiredTemplate => assessmentMode == AssessmentMode.templateScored;

  static TeacherMovementRevision? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final movementId = TeacherMovement._readId(map['movement_id']);
    final teacherId = TeacherMovement._readId(map['teacher_id']);
    final mode = AssessmentMode.tryParse(
      map['assessment_mode'] is String
          ? map['assessment_mode'] as String
          : null,
    );
    final spec = _tryParseSpec(mode, map['spec']);
    final schemaVersion = TeacherMovement._readInt(map['schema_version']);
    if (movementId == null ||
        teacherId == null ||
        mode == null ||
        spec == null ||
        (schemaVersion != TeacherReviewedMovementSpec.currentSchemaVersion &&
            schemaVersion != TeacherReviewedMovementSpec.legacySchemaVersion)) {
      return null;
    }
    return TeacherMovementRevision(
      id: id,
      movementId: movementId,
      teacherId: teacherId,
      assessmentMode: mode,
      spec: spec,
      schemaVersion: schemaVersion!,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
    );
  }

  static TeacherMovementRevisionSpec? _tryParseSpec(
    AssessmentMode? mode,
    Object? raw,
  ) {
    if (mode == null) return null;
    return switch (mode) {
      AssessmentMode.teacherReviewed => TeacherReviewedMovementSpec.tryFrom(
        raw,
      ),
      AssessmentMode.templateScored => TemplateScoredRevisionSpec.tryFrom(raw),
      AssessmentMode.officialGuided => null,
    };
  }
}
