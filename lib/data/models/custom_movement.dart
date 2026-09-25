import 'package:elixr_core/models/teacher_roster_invite.dart';

import 'movement_template.dart';
import 'training_prop.dart';

enum CustomMovementOwnerRole {
  teacher('teacher'),
  trainee('trainee');

  const CustomMovementOwnerRole(this.wireValue);
  final String wireValue;

  static CustomMovementOwnerRole? tryParse(String? value) {
    for (final role in values) {
      if (role.wireValue == value) return role;
    }
    return null;
  }
}

enum CustomMovementStatus {
  active,
  archived;

  static CustomMovementStatus? tryParse(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

class CustomMovement {
  static const currentSchemaVersion = 1;
  static const nameMaxLength = 80;
  static const descriptionMaxLength = 1000;
  static const allowedDifficulties = {'Easy', 'Medium', 'Hard'};
  static const supportedProps = {TrainingProp.bottle, TrainingProp.shaker};

  const CustomMovement({
    required this.id,
    required this.ownerUid,
    required this.ownerRole,
    required this.name,
    required this.description,
    required this.difficulty,
    required this.propType,
    required this.status,
    required this.activeRevisionId,
    this.createdAt,
    this.updatedAt,
    this.referenceImageStoragePath,
    this.schemaVersion = currentSchemaVersion,
  });

  final String id;
  final String ownerUid;
  final CustomMovementOwnerRole ownerRole;
  final String name;
  final String description;
  final String difficulty;
  final TrainingProp propType;
  final CustomMovementStatus status;
  final String activeRevisionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? referenceImageStoragePath;
  final int schemaVersion;

  bool get isActive => status == CustomMovementStatus.active;
  bool isOwnedBy(String uid) => ownerUid == uid.trim();

  static CustomMovement? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final ownerUid = _id(map['owner_uid']);
    final ownerRole = CustomMovementOwnerRole.tryParse(
      map['owner_role'] is String ? map['owner_role'] as String : null,
    );
    final name = _bounded(map['name'], nameMaxLength);
    final description = _bounded(
      map['description'],
      descriptionMaxLength,
      allowEmpty: true,
    );
    final difficulty = map['difficulty'];
    final prop = TrainingProp.tryParseStrict(map['prop_type']);
    final status = CustomMovementStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    final revisionId = _id(map['active_revision_id']);
    final imageStoragePath = map['reference_image_storage_path'];
    final schemaVersion = map['schema_version'];
    if (ownerUid == null ||
        ownerRole == null ||
        name == null ||
        description == null ||
        difficulty is! String ||
        !allowedDifficulties.contains(difficulty) ||
        prop == null ||
        !supportedProps.contains(prop) ||
        status == null ||
        revisionId == null ||
        (imageStoragePath != null &&
            (imageStoragePath is! String ||
                !isValidReferenceImagePath(ownerUid, id, imageStoragePath))) ||
        schemaVersion != currentSchemaVersion) {
      return null;
    }
    return CustomMovement(
      id: id,
      ownerUid: ownerUid,
      ownerRole: ownerRole,
      name: name,
      description: description,
      difficulty: difficulty,
      propType: prop,
      status: status,
      activeRevisionId: revisionId,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      referenceImageStoragePath: imageStoragePath as String?,
    );
  }

  static String referenceImagePath(
    String ownerUid,
    String movementId,
    String revisionId,
  ) =>
      'users/$ownerUid/custom_movement_references/${movementId}_$revisionId.jpg';

  static bool isValidReferenceImagePath(
    String ownerUid,
    String movementId,
    String path,
  ) {
    final prefix = 'users/$ownerUid/custom_movement_references/${movementId}_';
    final suffix = path.startsWith(prefix) ? path.substring(prefix.length) : '';
    return suffix.endsWith('.jpg') &&
        suffix.length > '.jpg'.length &&
        !suffix.contains('/');
  }

  static String? validateMetadata({
    required String name,
    required String description,
    required String difficulty,
  }) {
    if (_bounded(name, nameMaxLength) == null) {
      return 'Enter a movement name (maximum $nameMaxLength characters).';
    }
    if (_bounded(description, descriptionMaxLength, allowEmpty: true) == null) {
      return 'Description must be at most $descriptionMaxLength characters.';
    }
    if (!allowedDifficulties.contains(difficulty)) {
      return 'Choose a valid difficulty.';
    }
    return null;
  }

  static String? _id(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.length > 128 ? null : trimmed;
  }

  static String? _bounded(
    Object? value,
    int maxLength, {
    bool allowEmpty = false,
  }) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if ((!allowEmpty && trimmed.isEmpty) || trimmed.length > maxLength) {
      return null;
    }
    return trimmed;
  }
}

class CustomMovementRevision {
  const CustomMovementRevision({
    required this.id,
    required this.movementId,
    required this.ownerUid,
    required this.ownerRole,
    required this.template,
    this.createdAt,
    this.schemaVersion = CustomMovement.currentSchemaVersion,
  });

  final String id;
  final String movementId;
  final String ownerUid;
  final CustomMovementOwnerRole ownerRole;
  final MovementTemplate template;
  final DateTime? createdAt;
  final int schemaVersion;

  static CustomMovementRevision? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final movementId = CustomMovement._id(map['movement_id']);
    final ownerUid = CustomMovement._id(map['owner_uid']);
    final ownerRole = CustomMovementOwnerRole.tryParse(
      map['owner_role'] is String ? map['owner_role'] as String : null,
    );
    final template = MovementTemplate.tryFrom(map['template']);
    if (movementId == null ||
        ownerUid == null ||
        ownerRole == null ||
        template == null ||
        !template.isReady ||
        map['schema_version'] != CustomMovement.currentSchemaVersion) {
      return null;
    }
    return CustomMovementRevision(
      id: id,
      movementId: movementId,
      ownerUid: ownerUid,
      ownerRole: ownerRole,
      template: template,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
    );
  }
}

class CustomMovementResult {
  const CustomMovementResult({
    required this.id,
    required this.ownerUid,
    required this.movementId,
    required this.revisionId,
    required this.totalScore,
    required this.componentScores,
    required this.feedback,
    this.createdAt,
  });

  final String id;
  final String ownerUid;
  final String movementId;
  final String revisionId;
  final double totalScore;
  final Map<String, double> componentScores;
  final List<String> feedback;
  final DateTime? createdAt;

  static CustomMovementResult? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final ownerUid = CustomMovement._id(map['owner_uid']);
    final movementId = CustomMovement._id(map['movement_id']);
    final revisionId = CustomMovement._id(map['revision_id']);
    final totalScore = map['total_score'];
    final rawScores = map['component_scores'];
    final rawFeedback = map['feedback'];
    if (ownerUid == null ||
        movementId == null ||
        revisionId == null ||
        totalScore is! num ||
        !totalScore.isFinite ||
        totalScore < 0 ||
        totalScore > 100 ||
        rawScores is! Map ||
        rawFeedback is! List ||
        map['result_type'] != 'personal_practice') {
      return null;
    }
    final scores = <String, double>{};
    for (final entry in rawScores.entries) {
      if (entry.key is! String ||
          entry.value is! num ||
          !(entry.value as num).isFinite) {
        return null;
      }
      scores[entry.key as String] = (entry.value as num).toDouble();
    }
    if (rawFeedback.any((value) => value is! String)) return null;
    return CustomMovementResult(
      id: id,
      ownerUid: ownerUid,
      movementId: movementId,
      revisionId: revisionId,
      totalScore: totalScore.toDouble(),
      componentScores: Map.unmodifiable(scores),
      feedback: List.unmodifiable(rawFeedback.cast<String>().take(8)),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
    );
  }
}
