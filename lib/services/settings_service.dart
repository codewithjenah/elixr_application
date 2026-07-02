import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SettingsService extends ChangeNotifier {
  static const _fileName = 'settings.json';
  static const _cameraMirroredKey = 'camera_mirrored';
  static const _bottleDetectionEnabledKey = 'bottle_detection_enabled';
  static const _darkModeKey = 'dark_mode';

  bool _cameraMirrored = true;
  bool _bottleDetectionEnabled = true;
  bool _darkMode = true;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get cameraMirrored => _cameraMirrored;
  bool get bottleDetectionEnabled => _bottleDetectionEnabled;
  bool get darkMode => _darkMode;

  Future<void> initialize() async {
    try {
      final file = _settingsFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cameraMirrored = data[_cameraMirroredKey] as bool? ?? true;
        _bottleDetectionEnabled =
            data[_bottleDetectionEnabledKey] as bool? ?? true;
        _darkMode = data[_darkModeKey] as bool? ?? true;
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

  Future<void> setBottleDetectionEnabled(bool value) async {
    if (_bottleDetectionEnabled == value) return;
    _bottleDetectionEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          _cameraMirroredKey: _cameraMirrored,
          _bottleDetectionEnabledKey: _bottleDetectionEnabled,
          _darkModeKey: _darkMode,
        }),
      );
    } catch (_) {
      // Ignore write failures.
    }
  }

  File _settingsFile() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        return File('$appData\\Elixr\\$_fileName');
      }
    }
    return File(_fileName);
  }
}
