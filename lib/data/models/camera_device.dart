class CameraDevice {
  const CameraDevice({required this.index, required this.displayName});

  final int index;
  final String displayName;

  factory CameraDevice.fromJson(
    Map<String, dynamic> json, {
    int? preferredIndex,
    int? fallbackIndex,
  }) {
    final index = json['index'];
    if (index is! int || index < 0) {
      throw const FormatException('Invalid camera index');
    }
    return CameraDevice(
      index: index,
      displayName: cameraDisplayName(
        index,
        preferredIndex: preferredIndex,
        fallbackIndex: fallbackIndex,
      ),
    );
  }
}

/// Friendly camera labels. Underlying selection remains the numeric index.
///
/// - preferred backend index → "Default camera"
/// - fallback backend index → "Webcam"
/// - any other index → "Webcam N"
String cameraDisplayName(int index, {int? preferredIndex, int? fallbackIndex}) {
  if (preferredIndex != null && index == preferredIndex) {
    return 'Default camera';
  }
  if (fallbackIndex != null && index == fallbackIndex) {
    return 'Webcam';
  }
  return 'Webcam $index';
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

    final preferredIndex = requireInt('preferred_index');
    final fallbackIndex = requireInt('fallback_index');

    final cameras = <CameraDevice>[];
    for (final item in rawCameras) {
      final map = item is Map<String, dynamic>
          ? item
          : item is Map
          ? Map<String, dynamic>.from(item)
          : null;
      if (map == null) continue;
      cameras.add(
        CameraDevice.fromJson(
          map,
          preferredIndex: preferredIndex,
          fallbackIndex: fallbackIndex,
        ),
      );
    }

    return CameraDiscoveryResult(
      cameras: cameras,
      preferredIndex: preferredIndex,
      fallbackIndex: fallbackIndex,
      activeIndex: optionalInt('active_index'),
    );
  }
}
