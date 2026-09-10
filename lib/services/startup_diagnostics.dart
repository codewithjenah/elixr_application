import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Schema version for client-observed startup diagnostic samples.
const int startupDiagnosticsSchemaVersion = 1;

const String startupStartClassCold = 'cold';
const String startupStartClassWarmCamera = 'warm_camera';
const String startupModelCacheSessionScoped = 'session_scoped';

const String startupDurationConnection = 'connection';
const String startupDurationPrepare = 'prepare';
const String startupDurationCameraOpen = 'camera_open';
const String startupDurationFirstUsableFrame = 'first_usable_frame';
const String startupDurationFirstJpegEncode = 'first_jpeg_encode';
const String startupDurationFirstJpegSend = 'first_jpeg_send';
const String startupDurationClientFirstPreview = 'client_first_preview';
const String startupDurationDetectorWarmup = 'detector_warmup';
const String startupDurationReadinessStable = 'readiness_stable';
const String startupDurationActivateAck = 'activate_ack';

const List<String> startupDurationKeys = <String>[
  startupDurationConnection,
  startupDurationPrepare,
  startupDurationCameraOpen,
  startupDurationFirstUsableFrame,
  startupDurationFirstJpegEncode,
  startupDurationFirstJpegSend,
  startupDurationClientFirstPreview,
  startupDurationDetectorWarmup,
  startupDurationReadinessStable,
  startupDurationActivateAck,
];

typedef MonotonicClock = Duration Function();

final Stopwatch _processStopwatch = Stopwatch()..start();

Duration systemMonotonicClock() => _processStopwatch.elapsed;

abstract class StartupDiagnosticSink {
  void write(Map<String, dynamic> record);
}

class MemoryStartupDiagnosticSink implements StartupDiagnosticSink {
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[];
  int writeCalls = 0;

  @override
  void write(Map<String, dynamic> record) {
    writeCalls += 1;
    records.add(Map<String, dynamic>.from(record));
  }
}

class RaisingStartupDiagnosticSink implements StartupDiagnosticSink {
  @override
  void write(Map<String, dynamic> record) {
    throw StateError(
      'startup diagnostics must not persist during the frame loop',
    );
  }
}

bool startupDiagnosticsPersistenceEnabled({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final flag = (env['ELIXR_STARTUP_DIAGNOSTICS'] ?? '').trim().toLowerCase();
  if (flag == '0' || flag == 'false' || flag == 'no' || flag == 'off') {
    return false;
  }
  if (flag == '1' || flag == 'true' || flag == 'yes' || flag == 'on') {
    return true;
  }
  if ((env['FLUTTER_TEST'] ?? '').isNotEmpty) {
    return false;
  }
  return true;
}

Directory defaultStartupDiagnosticsDirectory({
  Map<String, String>? environment,
  Directory? current,
}) {
  final env = environment ?? Platform.environment;
  final override = (env['ELIXR_STARTUP_DIAGNOSTICS_DIR'] ?? '').trim();
  if (override.isNotEmpty) {
    return Directory(override);
  }
  final root = current ?? Directory.current;
  return Directory(
    '${root.path}${Platform.pathSeparator}logs'
    '${Platform.pathSeparator}startup_diagnostics',
  );
}

class JsonlStartupDiagnosticSink implements StartupDiagnosticSink {
  JsonlStartupDiagnosticSink({Directory? directory})
    : _directory = directory ?? defaultStartupDiagnosticsDirectory();

  final Directory _directory;

  @override
  void write(Map<String, dynamic> record) {
    _directory.createSync(recursive: true);
    final file = File(
      '${_directory.path}${Platform.pathSeparator}client_samples.jsonl',
    );
    file.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

String startupPilotDeviceId({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final override = (env['ELIXR_PILOT_DEVICE_ID'] ?? '').trim();
  if (override.isNotEmpty) {
    final end = override.length > 64 ? 64 : override.length;
    return override.substring(0, end);
  }
  try {
    return Platform.localHostname;
  } on Object {
    return 'unknown-device';
  }
}

Map<String, dynamic> collectClientEnvironmentMetadata({
  Map<String, String>? environment,
}) {
  return <String, dynamic>{
    'pilot_device_id': startupPilotDeviceId(environment: environment),
    'os_name': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'machine': Platform.localHostname,
    'dart': Platform.version.split(' ').first,
  };
}

Map<String, dynamic> cameraDiagnosticIdentity({
  required String? deviceId,
  required bool identityStable,
  String? displayName,
}) {
  if (deviceId == null || deviceId.isEmpty) {
    return <String, dynamic>{
      'camera_diagnostic_id': 'auto-select',
      'identity_stable': false,
      'camera_display_name': displayName,
    };
  }
  if (deviceId.startsWith('opencv:') || !identityStable) {
    return <String, dynamic>{
      'camera_diagnostic_id': deviceId.startsWith('opencv:')
          ? 'opencv_fallback'
          : 'unstable',
      'identity_stable': false,
      'camera_display_name': displayName,
    };
  }
  return <String, dynamic>{
    'camera_diagnostic_id': 'stable:${deviceId.hashCode.abs()}',
    'identity_stable': true,
    'camera_display_name': displayName,
  };
}

int? durationMs(Duration? start, Duration? end) {
  if (start == null || end == null) return null;
  final elapsed = end - start;
  if (elapsed.isNegative) return null;
  return elapsed.inMilliseconds;
}

double? startupPercentile(List<double> samples, double pct) {
  if (samples.isEmpty) return null;
  if (pct < 0 || pct > 100) {
    throw ArgumentError.value(pct, 'pct', 'must be in 0..100');
  }
  final ordered = List<double>.from(samples)..sort();
  var index = ((pct / 100.0) * (ordered.length - 1)).round();
  if (index < 0) index = 0;
  if (index >= ordered.length) index = ordered.length - 1;
  return ordered[index];
}

bool recordContainsImagePayload(Map<String, dynamic> record) {
  final keys = <String>{};
  void walk(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        keys.add(entry.key.toString().toLowerCase());
        walk(entry.value);
      }
    } else if (value is List) {
      for (final child in value) {
        walk(child);
      }
    }
  }

  walk(record);
  const forbidden = <String>{
    'frame_jpeg_base64',
    'evidence_jpeg_base64',
    'jpeg_bytes',
    'preview_bytes',
    'image_bytes',
  };
  return keys.intersection(forbidden).isNotEmpty;
}

/// Client-observed startup sample. Marks are recorded at most once per session.
class StartupDiagnosticsRecorder {
  StartupDiagnosticsRecorder({
    MonotonicClock? clock,
    StartupDiagnosticSink? sink,
    Map<String, String>? environment,
    bool? persist,
  }) : _clock = clock ?? systemMonotonicClock,
       _environmentOverride = environment {
    final enabled =
        persist ??
        startupDiagnosticsPersistenceEnabled(environment: environment);
    _sink = sink ?? (enabled ? JsonlStartupDiagnosticSink() : null);
  }

  final MonotonicClock _clock;
  final Map<String, String>? _environmentOverride;
  StartupDiagnosticSink? _sink;

  String? _sessionId;
  String? _sessionMode;
  String? _movement;
  Duration? _origin;
  Duration? _connectionStart;
  Duration? _connectionEnd;
  Duration? _prepareStart;
  Duration? _prepareEnd;
  Duration? _firstPreview;
  Duration? _readinessStart;
  Duration? _readinessStable;
  Duration? _activateStart;
  Duration? _activateEnd;
  String? _activateRequestId;
  String? _prepareRequestId;
  String? _failedMilestone;
  String? _errorCode;
  String _status = 'partial';
  Map<String, dynamic> _camera = <String, dynamic>{};
  Duration? _lastConnectionDuration;
  bool _wsAlreadyConnected = false;
  bool _finalized = false;
  int persistCalls = 0;
  final Map<String, int> _markAttempts = <String, int>{};

  @visibleForTesting
  String? get sessionId => _sessionId;

  Duration now() => _clock();

  int markAttempts(String name) => _markAttempts[name] ?? 0;

  void _attempt(String name) {
    _markAttempts[name] = markAttempts(name) + 1;
  }

  void rememberConnectionDuration(Duration duration) {
    _lastConnectionDuration = duration;
  }

  void beginAttempt({
    required String sessionId,
    String? sessionMode,
    String? movement,
  }) {
    if (_sessionId != null && _sessionId != sessionId && !_finalized) {
      finalize();
    }
    _sessionId = sessionId;
    _sessionMode = sessionMode;
    _movement = movement;
    _origin = _clock();
    _connectionStart = null;
    _connectionEnd = null;
    _prepareStart = null;
    _prepareEnd = null;
    _firstPreview = null;
    _readinessStart = null;
    _readinessStable = null;
    _activateStart = null;
    _activateEnd = null;
    _activateRequestId = null;
    _prepareRequestId = null;
    _failedMilestone = null;
    _errorCode = null;
    _status = 'partial';
    _camera = <String, dynamic>{};
    _finalized = false;
    persistCalls = 0;
    _markAttempts.clear();
    _wsAlreadyConnected = _lastConnectionDuration != null;
    if (_lastConnectionDuration != null) {
      _connectionStart = Duration.zero;
      _connectionEnd = _lastConnectionDuration;
    }
  }

  void annotate({
    String? sessionMode,
    String? movement,
    Map<String, dynamic>? camera,
  }) {
    if (sessionMode != null) _sessionMode = sessionMode;
    if (movement != null) _movement = movement;
    if (camera != null && _camera.isEmpty) {
      _camera = Map<String, dynamic>.from(camera);
    }
  }

  void markConnectStart() {
    _attempt('connection');
    if (_sessionId == null) {
      _connectionStart = _clock();
      _connectionEnd = null;
      return;
    }
    _connectionStart ??= _clock();
  }

  void markConnectEnd({required bool success, String? errorCode}) {
    if (_sessionId == null) {
      _connectionEnd = _clock();
    } else {
      _connectionEnd ??= _clock();
    }
    if (_connectionStart != null && _connectionEnd != null) {
      _lastConnectionDuration = _connectionEnd! - _connectionStart!;
    }
    if (!success) {
      fail('connection', errorCode ?? 'backend_unavailable');
    }
  }

  void markPrepareSent({required String sessionId, required String requestId}) {
    if (_sessionId != sessionId) return;
    _attempt('prepare');
    if (_prepareStart != null) return;
    _prepareStart = _clock();
    _prepareRequestId = requestId;
  }

  void markPrepareAck({
    required String sessionId,
    required String requestId,
    required bool accepted,
    String? errorCode,
  }) {
    if (_sessionId != sessionId) return;
    if (_prepareRequestId != null && _prepareRequestId != requestId) return;
    _attempt('prepare_ack');
    if (_prepareEnd != null) return;
    _prepareEnd = _clock();
    if (!accepted) {
      fail('prepare', errorCode ?? 'session_not_prepared');
    }
  }

  void markFirstPreview({required String sessionId}) {
    if (_sessionId != sessionId) return;
    _attempt('client_first_preview');
    _firstPreview ??= _clock();
  }

  void markBeginReadiness({required String sessionId}) {
    if (_sessionId != sessionId) return;
    _attempt('readiness_start');
    _readinessStart ??= _clock();
  }

  void markReadinessStable({required String sessionId}) {
    if (_sessionId != sessionId) return;
    _attempt('readiness_stable');
    _readinessStable ??= _clock();
  }

  void markActivateSent({
    required String sessionId,
    required String requestId,
  }) {
    if (_sessionId != sessionId) return;
    _attempt('activate');
    if (_activateStart != null) return;
    _activateStart = _clock();
    _activateRequestId = requestId;
  }

  void markActivateAck({
    required String sessionId,
    required String requestId,
    required bool accepted,
    String? errorCode,
  }) {
    if (_sessionId != sessionId) return;
    if (_activateRequestId != null && _activateRequestId != requestId) {
      return;
    }
    _attempt('activate_ack');
    if (_activateEnd != null) return;
    _activateEnd = _clock();
    if (!accepted) {
      fail('activate_ack', errorCode ?? 'session_not_prepared');
    }
  }

  void fail(String milestone, String errorCode) {
    _failedMilestone ??= milestone;
    _errorCode ??= errorCode;
    _status = 'failed';
  }

  Map<String, int?> durationsMs() {
    return <String, int?>{
      startupDurationConnection: _wsAlreadyConnected
          ? null
          : durationMs(_connectionStart, _connectionEnd),
      startupDurationPrepare: durationMs(_prepareStart, _prepareEnd),
      startupDurationCameraOpen: null,
      startupDurationFirstUsableFrame: null,
      startupDurationFirstJpegEncode: null,
      startupDurationFirstJpegSend: null,
      startupDurationClientFirstPreview: durationMs(_origin, _firstPreview),
      startupDurationDetectorWarmup: null,
      startupDurationReadinessStable: durationMs(
        _readinessStart,
        _readinessStable,
      ),
      startupDurationActivateAck: durationMs(_activateStart, _activateEnd),
    };
  }

  Map<String, dynamic> toRecord() {
    var status = _status;
    if (status != 'failed') {
      status = _firstPreview != null ? 'success' : 'partial';
    }
    return <String, dynamic>{
      'schema_version': startupDiagnosticsSchemaVersion,
      'observer': 'client',
      'session_id': _sessionId,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'start_class': startupStartClassCold,
      'camera_start_class': startupStartClassCold,
      'model_start_class': startupStartClassCold,
      'model_cache': startupModelCacheSessionScoped,
      'session_mode': _sessionMode,
      'movement': _movement,
      'status': status,
      'failed_milestone': _failedMilestone,
      'error_code': _errorCode,
      'ws_already_connected': _wsAlreadyConnected,
      'durations_ms': durationsMs(),
      'environment': collectClientEnvironmentMetadata(
        environment: _environmentOverride,
      ),
      'camera': _camera,
    };
  }

  Map<String, dynamic>? finalize({String? status}) {
    if (_sessionId == null) return null;
    if (_finalized) return toRecord();
    _finalized = true;
    if (status != null && _status != 'failed') {
      _status = status;
    }
    final record = toRecord();
    final sink = _sink;
    if (sink != null) {
      sink.write(record);
      persistCalls += 1;
    }
    return record;
  }

  void teardown({String? errorCode}) {
    if (_sessionId == null) return;
    if (_firstPreview == null && _status != 'failed') {
      fail('client_first_preview', errorCode ?? 'session_ended');
    }
    finalize();
    _sessionId = null;
  }
}
