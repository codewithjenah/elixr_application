class CameraDevice {
  const CameraDevice({required this.index, required this.displayName});

  final int index;
  final String displayName;

  factory CameraDevice.fromJson(Map<String, dynamic> json) {
    final index = json['index'];
    if (index is! int || index < 0) {
      throw const FormatException('Invalid camera index');
    }
    final name = json['display_name'];
    return CameraDevice(
      index: index,
      displayName: name is String && name.isNotEmpty ? name : 'Camera $index',
    );
  }
}

class CameraDiscoveryResult {
  const CameraDiscoveryResult({
    required this.cameras,
    required this.preferredIndex,
    required this.fallbackIndex,
    this.activeIndex,
  });

  final List<CameraDevice> cameras;
  final int preferredIndex;
  final int fallbackIndex;
  final int? activeIndex;

  factory CameraDiscoveryResult.fromJson(Map<String, dynamic> json) {
    final rawCameras = json['cameras'];
    if (rawCameras is! List) {
      throw const FormatException('Missing cameras list');
    }

    final cameras = <CameraDevice>[];
    for (final item in rawCameras) {
      if (item is Map<String, dynamic>) {
        cameras.add(CameraDevice.fromJson(item));
      } else if (item is Map) {
        cameras.add(CameraDevice.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    int requireInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      throw FormatException('Missing or invalid $key');
    }

    int? optionalInt(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    return CameraDiscoveryResult(
      cameras: cameras,
      preferredIndex: requireInt('preferred_index'),
      fallbackIndex: requireInt('fallback_index'),
      activeIndex: optionalInt('active_index'),
    );
  }
}
