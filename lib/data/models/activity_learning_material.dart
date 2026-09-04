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
    final detectedContentType = map['detected_content_type'];
    final sizeBytes = map['size_bytes'];
    if (detectedContentType != null && detectedContentType is! String ||
        sizeBytes != null && sizeBytes is! int) {
      return null;
    }
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
      detectedContentType: detectedContentType as String?,
      sizeBytes: sizeBytes as int?,
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

enum ActivityMaterialUploadState { staging, validating, ready, rejected, deleting }

extension ActivityMaterialUploadStateWire on ActivityMaterialUploadState {
  String get wireValue => name;

  static ActivityMaterialUploadState? tryParse(Object? value) {
    if (value is! String) return null;
    for (final state in ActivityMaterialUploadState.values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

enum ActivityMaterialUploadRejectionReason {
  invalidSize,
  invalidContent,
  expired,
  materialUnavailable,
  uploadFailed,
}

extension ActivityMaterialUploadRejectionReasonWire
    on ActivityMaterialUploadRejectionReason {
  String get wireValue => switch (this) {
    ActivityMaterialUploadRejectionReason.invalidSize => 'invalid_size',
    ActivityMaterialUploadRejectionReason.invalidContent => 'invalid_content',
    ActivityMaterialUploadRejectionReason.expired => 'expired',
    ActivityMaterialUploadRejectionReason.materialUnavailable =>
      'material_unavailable',
    ActivityMaterialUploadRejectionReason.uploadFailed => 'upload_failed',
  };

  /// The server is allowed to add internal reasons. Clients never surface an
  /// unknown value directly; it becomes the generic safe UI state instead.
  static ActivityMaterialUploadRejectionReason parseSafe(Object? value) {
    if (value is String) {
      for (final reason in ActivityMaterialUploadRejectionReason.values) {
        if (reason.wireValue == value) return reason;
      }
    }
    return ActivityMaterialUploadRejectionReason.uploadFailed;
  }
}

/// Authoritative lifecycle state returned by Functions after a staged upload.
/// It deliberately carries neither a staging path nor server diagnostic data.
class ActivityMaterialUploadStatus {
  const ActivityMaterialUploadStatus({
    required this.uploadId,
    required this.materialId,
    required this.state,
    this.rejectionReason,
    this.material,
  });

  final String uploadId;
  final String materialId;
  final ActivityMaterialUploadState state;
  final ActivityMaterialUploadRejectionReason? rejectionReason;
  final ActivityLearningMaterial? material;

  static ActivityMaterialUploadStatus? tryFromMap(Map<String, dynamic> map) {
    final uploadId = map['upload_id'];
    final materialId = map['material_id'];
    final state = ActivityMaterialUploadStateWire.tryParse(map['state']);
    if (uploadId is! String || uploadId.isEmpty || materialId is! String ||
        materialId.isEmpty || state == null) {
      return null;
    }
    if (state == ActivityMaterialUploadState.ready) {
      final rawMaterial = map['material'];
      if (rawMaterial is! Map) return null;
      final material = ActivityLearningMaterial.tryFromMap(
        Map<String, dynamic>.from(rawMaterial),
      );
      if (material == null || material.id != materialId) return null;
      return ActivityMaterialUploadStatus(
        uploadId: uploadId,
        materialId: materialId,
        state: state,
        material: material,
      );
    }
    if (state == ActivityMaterialUploadState.rejected) {
      if (map['rejection_reason'] is! String) return null;
      return ActivityMaterialUploadStatus(
        uploadId: uploadId,
        materialId: materialId,
        state: state,
        rejectionReason: ActivityMaterialUploadRejectionReasonWire.parseSafe(
          map['rejection_reason'],
        ),
      );
    }
    return ActivityMaterialUploadStatus(
      uploadId: uploadId,
      materialId: materialId,
      state: state,
    );
  }
}
