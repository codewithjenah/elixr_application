class CameraDevice {
  const CameraDevice({
    required this.deviceId,
    required this.displayName,
    required this.runtimeIndex,
    this.isActive = false,
    this.identityStable = false,
  });

  final String deviceId;
  final String displayName;
  final int runtimeIndex;
  final bool isActive;
  final bool identityStable;

  factory CameraDevice.fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException('Invalid camera device_id');
    }

    final displayName = json['display_name'];
    if (displayName is! String || displayName.isEmpty) {
      throw const FormatException('Invalid camera display_name');
    }

    final runtimeIndex = _requireNonNegativeInt(
      json['runtime_index'] ?? json['index'],
      'runtime_index',
    );

    return CameraDevice(
      deviceId: deviceId,
      displayName: displayName,
      runtimeIndex: runtimeIndex,
      isActive: json['is_active'] == true,
      identityStable: json['identity_stable'] == true,
    );
  }
}

int _requireNonNegativeInt(Object? value, String key) {
  if (value is int) {
    if (value < 0) {
      throw FormatException('Invalid $key');
    }
    return value;
  }
  if (value is num) {
    final asInt = value.toInt();
    if (asInt < 0 || asInt.toDouble() != value.toDouble()) {
      throw FormatException('Invalid $key');
    }
    return asInt;
  }
  throw FormatException('Missing or invalid $key');
}

/// Make duplicate friendly names distinguishable without changing identity.
///
/// Example: two devices named "USB Camera" become
/// "USB Camera · Camera 0" and "USB Camera · Camera 1".
List<String> distinguishableCameraLabels(List<CameraDevice> cameras) {
  final counts = <String, int>{};
  for (final camera in cameras) {
    counts[camera.displayName] = (counts[camera.displayName] ?? 0) + 1;
  }

  return [
    for (final camera in cameras)
      counts[camera.displayName]! > 1
          ? '${camera.displayName} · Camera ${camera.runtimeIndex}'
          : camera.displayName,
  ];
}

class CameraDiscoveryResult {
  const CameraDiscoveryResult({
    required this.cameras,
    this.activeDeviceId,
    this.activeIndex,
    this.preferredIndex,
    this.fallbackIndex,
  });

  final List<CameraDevice> cameras;
  final String? activeDeviceId;
  final int? activeIndex;

  /// Legacy migration fields from older backends.
  final int? preferredIndex;
  final int? fallbackIndex;

  factory CameraDiscoveryResult.fromJson(Map<String, dynamic> json) {
    final rawCameras = json['cameras'];
    if (rawCameras is! List) {
      throw const FormatException('Missing cameras list');
    }

    int? optionalInt(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    String? optionalString(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      return null;
    }

    final cameras = <CameraDevice>[];
    for (final item in rawCameras) {
      final map = item is Map<String, dynamic>
          ? item
          : item is Map
          ? Map<String, dynamic>.from(item)
          : null;
      if (map == null) continue;
      cameras.add(CameraDevice.fromJson(map));
    }

    return CameraDiscoveryResult(
      cameras: cameras,
      activeDeviceId: optionalString('active_device_id'),
      activeIndex: optionalInt('active_index'),
      preferredIndex: optionalInt('preferred_index'),
      fallbackIndex: optionalInt('fallback_index'),
    );
  }
}
