import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/models/camera_device.dart';

class SettingsService extends ChangeNotifier {
  SettingsService({File? settingsFile}) : _settingsFileOverride = settingsFile;

  static const _fileName = 'settings.json';
  static const _cameraMirroredKey = 'camera_mirrored';
  static const _darkModeKey = 'dark_mode';
  static const _cameraDeviceIdKey = 'camera_device_id';
  static const _cameraDisplayNameKey = 'camera_display_name';

  /// Legacy migration key. Retained only until mapped to a device id.
  static const _cameraIndexKey = 'camera_index';

  final File? _settingsFileOverride;

  bool _cameraMirrored = true;
  bool _darkMode = true;
  String? _selectedCameraDeviceId;
  String? _selectedCameraDisplayName;

  /// Pending legacy runtime index awaiting one-time migration.
  int? _legacyCameraIndex;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get cameraMirrored => _cameraMirrored;
  bool get darkMode => _darkMode;

  /// `null` means Auto-select; a non-null value is an explicit device id.
  String? get selectedCameraDeviceId => _selectedCameraDeviceId;

  /// Cached UI label for the selected device. Not used for identity.
  String? get selectedCameraDisplayName => _selectedCameraDisplayName;

  /// Whether a legacy `camera_index` still needs migration after discovery.
  bool get hasPendingLegacyCameraMigration =>
      _selectedCameraDeviceId == null && _legacyCameraIndex != null;

  /// Legacy runtime index retained until discovery migrates it to a device id.
  ///
  /// Practice may send this temporarily when device id migration has not run
  /// yet. Null means Auto-select or already migrated.
  int? get pendingLegacyCameraIndex => _legacyCameraIndex;

  Future<void> initialize() async {
    try {
      final file = _settingsFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cameraMirrored = data[_cameraMirroredKey] as bool? ?? true;
        _darkMode = data[_darkModeKey] as bool? ?? true;
        _loadCameraSelection(data);
      }
    } catch (_) {
      // Keep defaults.
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setCameraMirrored(bool value) async {
    if (_cameraMirrored == value) return;
    _cameraMirrored = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSelectedCameraDevice(
    String? deviceId, {
    String? displayName,
  }) async {
    final normalizedId = _parseDeviceId(deviceId);
    final normalizedName = displayName?.trim();
    final name = (normalizedName == null || normalizedName.isEmpty)
        ? null
        : normalizedName;

    if (_selectedCameraDeviceId == normalizedId &&
        _selectedCameraDisplayName == name &&
        _legacyCameraIndex == null) {
      return;
    }

    _selectedCameraDeviceId = normalizedId;
    _selectedCameraDisplayName = normalizedId == null ? null : name;
    _legacyCameraIndex = null;
    notifyListeners();
    await _save();
  }

  Future<void> clearCameraSelectionForAutoSelect() async {
    await setSelectedCameraDevice(null);
  }

  /// Map a legacy persisted `camera_index` onto a discovered stable device.
  ///
  /// Does nothing when already migrated, when there is no legacy index, or
  /// when the legacy index cannot be matched. Never silently picks another
  /// device.
  Future<bool> migrateLegacyCameraIndex(List<CameraDevice> discovered) async {
    if (_selectedCameraDeviceId != null) return false;
    final legacyIndex = _legacyCameraIndex;
    if (legacyIndex == null) return false;

    CameraDevice? match;
    for (final camera in discovered) {
      if (camera.runtimeIndex == legacyIndex) {
        match = camera;
        break;
      }
    }
    if (match == null) return false;

    await setSelectedCameraDevice(
      match.deviceId,
      displayName: match.displayName,
    );
    return true;
  }

  /// Reloads camera selection from disk so practice starts use the saved value
  /// even after hot reload left in-memory settings stale.
  Future<String?> loadSelectedCameraDeviceId() async {
    try {
      final file = _settingsFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _loadCameraSelection(data);
      }
    } catch (_) {
      // Keep the in-memory value.
    }
    return _selectedCameraDeviceId;
  }

  void _loadCameraSelection(Map<String, dynamic> data) {
    final deviceId = _parseDeviceId(data[_cameraDeviceIdKey]);
    if (deviceId != null) {
      _selectedCameraDeviceId = deviceId;
      final name = data[_cameraDisplayNameKey];
      _selectedCameraDisplayName = name is String && name.trim().isNotEmpty
          ? name.trim()
          : null;
      _legacyCameraIndex = null;
      return;
    }

    _selectedCameraDeviceId = null;
    _selectedCameraDisplayName = null;
    _legacyCameraIndex = _parseCameraIndex(data[_cameraIndexKey]);
  }

  Future<void> _save() async {
    try {
      final file = _settingsFile();
      await file.parent.create(recursive: true);
      final payload = <String, dynamic>{
        _cameraMirroredKey: _cameraMirrored,
        _darkModeKey: _darkMode,
        _cameraDeviceIdKey: _selectedCameraDeviceId,
        _cameraDisplayNameKey: _selectedCameraDisplayName,
      };
      // Keep legacy key only while migration is still pending.
      if (_selectedCameraDeviceId == null && _legacyCameraIndex != null) {
        payload[_cameraIndexKey] = _legacyCameraIndex;
      } else {
        payload[_cameraIndexKey] = null;
      }
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {
      // Ignore write failures.
    }
  }

  File _settingsFile() {
    final override = _settingsFileOverride;
    if (override != null) {
      return override;
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        return File('$appData\\Elixr\\$_fileName');
      }
    }
    return File(_fileName);
  }

  static String? _parseDeviceId(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  /// Legacy `camera_index` parser for one-time migration.
  static int? _parseCameraIndex(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return null;
    if (raw is int) {
      return raw < 0 ? null : raw;
    }
    if (raw is num) {
      if (raw is double && raw != raw.roundToDouble()) return null;
      final asInt = raw.toInt();
      return asInt < 0 ? null : asInt;
    }
    return null;
  }
}
