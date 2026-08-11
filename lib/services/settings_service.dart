import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/movements.dart';
import '../data/models/camera_device.dart';

/// Result of attempting to persist local Settings JSON.
///
/// Validation failures are not represented here — callers validate first and
/// defensive service checks throw [ArgumentError].
enum SettingsWriteOutcome {
  /// Disk write succeeded and in-memory fields were committed.
  saved,

  /// Candidate matched current in-memory values; no write or notification.
  unchanged,

  /// Disk write failed; in-memory values were left unchanged.
  writeFailed,
}

class SettingsService extends ChangeNotifier {
  SettingsService({
    File? settingsFile,
    Future<void> Function(File file, String contents)? writeSettings,
  }) : _settingsFileOverride = settingsFile,
       _writeSettingsOverride = writeSettings;

  static const _fileName = 'settings.json';
  static const _cameraMirroredKey = 'camera_mirrored';
  static const _darkModeKey = 'dark_mode';
  static const _textScaleKey = 'text_scale';
  static const _highContrastKey = 'high_contrast';
  static const _cameraDeviceIdKey = 'camera_device_id';
  static const _cameraDisplayNameKey = 'camera_display_name';
  static const _justDanceMovementNamesKey = 'just_dance_movement_names';
  static const _justDanceIntervalSecondsKey = 'just_dance_interval_seconds';
  static const _selectedMusicTrackIdKey = 'selected_music_track_id';

  /// Legacy migration key. Retained only until mapped to a device id.
  static const _cameraIndexKey = 'camera_index';

  static const _defaultJustDanceIntervalSeconds = 25;
  static const _defaultTextScale = 1.0;

  /// Allowed Accessibility text-size multipliers.
  static const allowedTextScales = <double>[1.0, 1.15, 1.3];

  final File? _settingsFileOverride;
  final Future<void> Function(File file, String contents)?
  _writeSettingsOverride;

  bool _cameraMirrored = true;
  bool _darkMode = true;
  double _textScale = _defaultTextScale;
  bool _highContrast = false;
  String? _selectedCameraDeviceId;
  String? _selectedCameraDisplayName;
  List<String> _justDanceMovementNames = _defaultJustDanceMovementNames();
  int _justDanceIntervalSeconds = _defaultJustDanceIntervalSeconds;
  String? _selectedMusicTrackId;

  /// Pending legacy runtime index awaiting one-time migration.
  int? _legacyCameraIndex;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  bool get cameraMirrored => _cameraMirrored;
  bool get darkMode => _darkMode;

  /// App-wide text size multiplier. One of [allowedTextScales].
  double get textScale => _textScale;

  /// When true, high-contrast light/dark themes are used.
  bool get highContrast => _highContrast;

  /// Ordered Just Dance rotation setlist. Defaults to the full catalog.
  List<String> get justDanceMovementNames =>
      List.unmodifiable(_justDanceMovementNames);

  /// Seconds each movement stays on screen before auto-advancing.
  int get justDanceIntervalSeconds => _justDanceIntervalSeconds;

  /// `null` means shuffle across [musicTrackCatalog]; a non-null value pins
  /// session music to that track id (see `resolveTrack`).
  String? get selectedMusicTrackId => _selectedMusicTrackId;

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
        _textScale = _parseTextScale(data[_textScaleKey]);
        _highContrast = data[_highContrastKey] as bool? ?? false;
        _loadCameraSelection(data);
        _loadJustDanceSettings(data);
        _selectedMusicTrackId = _parseTrackId(data[_selectedMusicTrackIdKey]);
      }
    } catch (_) {
      // Keep defaults.
    }
    _initialized = true;
    notifyListeners();
  }

  Future<SettingsWriteOutcome> setCameraMirrored(bool value) {
    return _commitCandidate(
      cameraMirrored: value,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  Future<SettingsWriteOutcome> setDarkMode(bool value) {
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: value,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  /// Sets the Accessibility text-size multiplier.
  ///
  /// Throws [ArgumentError] when [value] is not one of [allowedTextScales].
  Future<SettingsWriteOutcome> setTextScale(double value) {
    if (!allowedTextScales.contains(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Text scale must be one of $allowedTextScales',
      );
    }
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: value,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  Future<SettingsWriteOutcome> setHighContrast(bool value) {
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: value,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  /// Sets the ordered Just Dance rotation setlist.
  ///
  /// Throws [ArgumentError] when [movementNames] is empty or contains no
  /// catalog movements after normalization.
  Future<SettingsWriteOutcome> setJustDanceSetlist(List<String> movementNames) {
    final normalized = _normalizeMovementNames(movementNames);
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: normalized,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  /// Throws [ArgumentError] when [seconds] is not positive.
  Future<SettingsWriteOutcome> setJustDanceIntervalSeconds(int seconds) {
    if (seconds <= 0) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'Live Practice interval must be positive',
      );
    }
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: seconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  Future<SettingsWriteOutcome> setSelectedMusicTrackId(String? id) {
    final normalized = _parseTrackId(id);
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: normalized,
    );
  }

  /// Atomically updates Live Practice setlist, interval, and music.
  ///
  /// Throws [ArgumentError] when normalization leaves no valid movements or
  /// [intervalSeconds] is not positive.
  Future<SettingsWriteOutcome> updateLivePracticePreferences({
    required List<String> movementNames,
    required int intervalSeconds,
    String? musicTrackId,
  }) {
    if (intervalSeconds <= 0) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'Live Practice interval must be positive',
      );
    }
    final normalizedMovements = _normalizeMovementNames(movementNames);
    final normalizedTrack = _parseTrackId(musicTrackId);
    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: _selectedCameraDeviceId,
      cameraDisplayName: _selectedCameraDisplayName,
      legacyCameraIndex: _legacyCameraIndex,
      justDanceMovementNames: normalizedMovements,
      justDanceIntervalSeconds: intervalSeconds,
      selectedMusicTrackId: normalizedTrack,
    );
  }

  Future<SettingsWriteOutcome> setSelectedCameraDevice(
    String? deviceId, {
    String? displayName,
  }) {
    final normalizedId = _parseDeviceId(deviceId);
    final normalizedName = displayName?.trim();
    final name = (normalizedName == null || normalizedName.isEmpty)
        ? null
        : normalizedName;

    return _commitCandidate(
      cameraMirrored: _cameraMirrored,
      darkMode: _darkMode,
      textScale: _textScale,
      highContrast: _highContrast,
      cameraDeviceId: normalizedId,
      cameraDisplayName: normalizedId == null ? null : name,
      legacyCameraIndex: null,
      justDanceMovementNames: _justDanceMovementNames,
      justDanceIntervalSeconds: _justDanceIntervalSeconds,
      selectedMusicTrackId: _selectedMusicTrackId,
    );
  }

  Future<SettingsWriteOutcome> clearCameraSelectionForAutoSelect() {
    return setSelectedCameraDevice(null);
  }

  /// Map a legacy persisted `camera_index` onto a discovered stable device.
  ///
  /// Returns `true` only when migration committed successfully (`saved`) or
  /// the in-memory selection already matches the intended device
  /// (`unchanged`). On `writeFailed`, returns `false` and retains the legacy
  /// index for a later retry.
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

    final outcome = await setSelectedCameraDevice(
      match.deviceId,
      displayName: match.displayName,
    );
    switch (outcome) {
      case SettingsWriteOutcome.saved:
        return true;
      case SettingsWriteOutcome.unchanged:
        return _selectedCameraDeviceId == match.deviceId &&
            _legacyCameraIndex == null;
      case SettingsWriteOutcome.writeFailed:
        return false;
    }
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

  /// Loads the Just Dance setlist/interval, dropping any persisted movement
  /// names that no longer exist in [movementCatalog]. Falls back to the full
  /// catalog default when nothing valid remains.
  void _loadJustDanceSettings(Map<String, dynamic> data) {
    final validNames = movementCatalog.map((m) => m.name).toSet();
    final raw = data[_justDanceMovementNamesKey];
    final persisted = raw is List
        ? _dedupePreservingOrder(
            raw.whereType<String>().where(validNames.contains),
          )
        : <String>[];
    _justDanceMovementNames = persisted.isEmpty
        ? _defaultJustDanceMovementNames()
        : List.unmodifiable(persisted);

    final interval = data[_justDanceIntervalSecondsKey];
    _justDanceIntervalSeconds = interval is int && interval > 0
        ? interval
        : _defaultJustDanceIntervalSeconds;
  }

  static List<String> _defaultJustDanceMovementNames() =>
      List.unmodifiable(movementCatalog.map((m) => m.name));

  static String? _parseTrackId(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  /// Parses a persisted text scale, falling back to the default when missing
  /// or not one of [allowedTextScales].
  static double _parseTextScale(Object? raw) {
    final value = switch (raw) {
      int v => v.toDouble(),
      double v => v,
      _ => null,
    };
    if (value == null) return _defaultTextScale;
    for (final allowed in allowedTextScales) {
      if (value == allowed) return allowed;
    }
    return _defaultTextScale;
  }

  /// Filters to catalog names, dedupes preserving order. Throws when empty.
  static List<String> _normalizeMovementNames(List<String> movementNames) {
    final validNames = movementCatalog.map((m) => m.name).toSet();
    final normalized = _dedupePreservingOrder(
      movementNames.where(validNames.contains),
    );
    if (normalized.isEmpty) {
      throw ArgumentError(
        'Live Practice setlist must contain at least one catalog movement',
      );
    }
    return List.unmodifiable(normalized);
  }

  static List<String> _dedupePreservingOrder(Iterable<String> names) {
    final seen = <String>{};
    final result = <String>[];
    for (final name in names) {
      if (seen.add(name)) {
        result.add(name);
      }
    }
    return result;
  }

  Future<SettingsWriteOutcome> _commitCandidate({
    required bool cameraMirrored,
    required bool darkMode,
    required double textScale,
    required bool highContrast,
    required String? cameraDeviceId,
    required String? cameraDisplayName,
    required int? legacyCameraIndex,
    required List<String> justDanceMovementNames,
    required int justDanceIntervalSeconds,
    required String? selectedMusicTrackId,
  }) async {
    if (_cameraMirrored == cameraMirrored &&
        _darkMode == darkMode &&
        _textScale == textScale &&
        _highContrast == highContrast &&
        _selectedCameraDeviceId == cameraDeviceId &&
        _selectedCameraDisplayName == cameraDisplayName &&
        _legacyCameraIndex == legacyCameraIndex &&
        listEquals(_justDanceMovementNames, justDanceMovementNames) &&
        _justDanceIntervalSeconds == justDanceIntervalSeconds &&
        _selectedMusicTrackId == selectedMusicTrackId) {
      return SettingsWriteOutcome.unchanged;
    }

    final payload = <String, dynamic>{
      _cameraMirroredKey: cameraMirrored,
      _darkModeKey: darkMode,
      _textScaleKey: textScale,
      _highContrastKey: highContrast,
      _cameraDeviceIdKey: cameraDeviceId,
      _cameraDisplayNameKey: cameraDisplayName,
      _justDanceMovementNamesKey: justDanceMovementNames,
      _justDanceIntervalSecondsKey: justDanceIntervalSeconds,
      _selectedMusicTrackIdKey: selectedMusicTrackId,
    };
    if (cameraDeviceId == null && legacyCameraIndex != null) {
      payload[_cameraIndexKey] = legacyCameraIndex;
    } else {
      payload[_cameraIndexKey] = null;
    }

    final wrote = await _writePayload(payload);
    if (!wrote) {
      return SettingsWriteOutcome.writeFailed;
    }

    _cameraMirrored = cameraMirrored;
    _darkMode = darkMode;
    _textScale = textScale;
    _highContrast = highContrast;
    _selectedCameraDeviceId = cameraDeviceId;
    _selectedCameraDisplayName = cameraDisplayName;
    _legacyCameraIndex = legacyCameraIndex;
    _justDanceMovementNames = List.unmodifiable(justDanceMovementNames);
    _justDanceIntervalSeconds = justDanceIntervalSeconds;
    _selectedMusicTrackId = selectedMusicTrackId;
    notifyListeners();
    return SettingsWriteOutcome.saved;
  }

  Future<bool> _writePayload(Map<String, dynamic> payload) async {
    try {
      final file = _settingsFile();
      await file.parent.create(recursive: true);
      final contents = jsonEncode(payload);
      final writer = _writeSettingsOverride;
      if (writer != null) {
        await writer(file, contents);
      } else {
        await file.writeAsString(contents);
      }
      return true;
    } catch (_) {
      return false;
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
