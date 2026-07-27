import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SettingsService extends ChangeNotifier {
  SettingsService({File? settingsFile}) : _settingsFileOverride = settingsFile;

  static const _fileName = 'settings.json';
  static const _cameraMirroredKey = 'camera_mirrored';
  static const _darkModeKey = 'dark_mode';
  static const _cameraIndexKey = 'camera_index';

  final File? _settingsFileOverride;

  bool _cameraMirrored = true;
  bool _darkMode = true;
  int? _selectedCameraIndex;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get cameraMirrored => _cameraMirrored;
  bool get darkMode => _darkMode;

  /// `null` means Auto-select; a non-null value is an explicit camera index.
  int? get selectedCameraIndex => _selectedCameraIndex;

  Future<void> initialize() async {
    try {
      final file = _settingsFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cameraMirrored = data[_cameraMirroredKey] as bool? ?? true;
        _darkMode = data[_darkModeKey] as bool? ?? true;
        _selectedCameraIndex = _parseCameraIndex(data[_cameraIndexKey]);
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

  Future<void> setSelectedCameraIndex(int? value) async {
    final normalized = value == null ? null : _parseCameraIndex(value);
    if (_selectedCameraIndex == normalized) return;
    _selectedCameraIndex = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = _settingsFile();
      await file.parent.create(recursive: true);
      final payload = <String, dynamic>{
        _cameraMirroredKey: _cameraMirrored,
        _darkModeKey: _darkMode,
      };
      if (_selectedCameraIndex != null) {
        payload[_cameraIndexKey] = _selectedCameraIndex;
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
