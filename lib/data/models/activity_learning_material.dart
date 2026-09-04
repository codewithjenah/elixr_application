enum ActivityLearningMaterialType { pdf, image, video, link }

extension ActivityLearningMaterialTypeWire on ActivityLearningMaterialType {
  String get wireValue => name;

  static ActivityLearningMaterialType? tryParse(Object? value) {
    if (value is! String) return null;
    for (final type in ActivityLearningMaterialType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

/// Canonical material metadata returned only from the server-authoritative
/// material API. [storagePath] is an authenticated Firebase Storage path, not
/// a public or tokenized download URL.
class ActivityLearningMaterial {
  const ActivityLearningMaterial({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.displayName,
    this.detectedContentType,
    this.sizeBytes,
    this.storagePath,
    this.externalUrl,
  });

  final String id;
  final String assignmentId;
  final ActivityLearningMaterialType type;
  final String displayName;
  final String? detectedContentType;
  final int? sizeBytes;
  final String? storagePath;
  final Uri? externalUrl;

  static ActivityLearningMaterial? tryFromMap(Map<String, dynamic> map) {
    final id = map['material_id'];
    final assignmentId = map['assignment_id'];
    final type = ActivityLearningMaterialTypeWire.tryParse(map['type']);
    final displayName = map['display_name'];
    if (id is! String ||
        id.trim().isEmpty ||
        assignmentId is! String ||
        assignmentId.trim().isEmpty ||
        type == null ||
        displayName is! String ||
        displayName.trim().isEmpty) {
      return null;
    }
    final storagePath = map['storage_path'];
    final rawUrl = map['external_url'];
    Uri? url;
    if (rawUrl != null) {
      if (rawUrl is! String) {
        return null;
      }
      url = Uri.tryParse(rawUrl);
      if (url == null ||
          !url.hasAuthority ||
          (url.scheme != 'http' && url.scheme != 'https')) {
        return null;
      }
    }
    if (type == ActivityLearningMaterialType.link && url == null) {
      return null;
    }
    if (type != ActivityLearningMaterialType.link &&
        (storagePath is! String || storagePath.trim().isEmpty)) {
      return null;
    }
    return ActivityLearningMaterial(
      id: id.trim(),
      assignmentId: assignmentId.trim(),
      type: type,
      displayName: displayName.trim(),
      detectedContentType: map['detected_content_type'] as String?,
      sizeBytes: map['size_bytes'] as int?,
      storagePath: storagePath is String ? storagePath : null,
      externalUrl: url,
    );
  }
}

/// The exact one-time staging capability returned by the server. It is not a
/// final material and must never be treated as readable metadata.
class ActivityMaterialUpload {
  const ActivityMaterialUpload({
    required this.uploadId,
    required this.materialId,
    required this.stagingPath,
    required this.declaredContentType,
    required this.expiresAt,
  });

  final String uploadId;
  final String materialId;
  final String stagingPath;
  final String declaredContentType;
  final DateTime expiresAt;

  static ActivityMaterialUpload? tryFromMap(Map<String, dynamic> map) {
    final uploadId = map['upload_id'];
    final materialId = map['material_id'];
    final stagingPath = map['staging_path'];
    final contentType = map['declared_content_type'];
    final expiresAt = map['expires_at'];
    if (uploadId is! String ||
        materialId is! String ||
        stagingPath is! String ||
        contentType is! String ||
        expiresAt is! String) {
      return null;
    }
    final parsedExpiry = DateTime.tryParse(expiresAt);
    if (parsedExpiry == null ||
        uploadId.isEmpty ||
        materialId.isEmpty ||
        stagingPath.isEmpty ||
        contentType.isEmpty) {
      return null;
    }
    return ActivityMaterialUpload(
      uploadId: uploadId,
      materialId: materialId,
      stagingPath: stagingPath,
      declaredContentType: contentType,
      expiresAt: parsedExpiry.toUtc(),
    );
  }
}
