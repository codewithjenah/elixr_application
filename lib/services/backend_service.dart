import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// The active local backend endpoint used by HTTP and WebSocket clients.
///
/// Development keeps the historical fixed port so `backend/run.ps1` and
/// `flutter run -d windows` continue to work. A packaged backend receives a
/// free loopback port from [BackendService] at startup.
abstract final class BackendRuntime {
  static final Uri defaultHttpBaseUri = Uri.parse(
    AppConstants.backendHttpBaseUrl,
  );
  static final Uri defaultWsUri = Uri.parse(AppConstants.wsUrl);

  static Uri _httpBaseUri = defaultHttpBaseUri;
  static Uri _wsUri = defaultWsUri;
  static String? _startupError;

  static Uri get httpBaseUri => _httpBaseUri;
  static Uri get wsUri => _wsUri;
  static String? get startupError => _startupError;

  static void usePort(int port) {
    _httpBaseUri = Uri(scheme: 'http', host: '127.0.0.1', port: port);
    _wsUri = Uri(scheme: 'ws', host: '127.0.0.1', port: port, path: '/ws');
    _startupError = null;
  }

  static void setStartupError(String message) {
    _startupError = message;
  }

  static void reset() {
    _httpBaseUri = defaultHttpBaseUri;
    _wsUri = defaultWsUri;
    _startupError = null;
  }
}

/// Desktop hosts that can own a packaged backend sidecar.
enum BackendHostPlatform { windows, macos, unsupported }

BackendHostPlatform _currentHostPlatform() {
  if (Platform.isWindows) return BackendHostPlatform.windows;
  if (Platform.isMacOS) return BackendHostPlatform.macos;
  return BackendHostPlatform.unsupported;
}

/// Owns the optional packaged Python backend for this ELIXR process.
///
/// When no sidecar executable is found, this service is a no-op. That is the
/// development path: the existing manually started backend remains available
/// on `127.0.0.1:8000`. Only a process started by this instance is stopped.
///
/// A macOS release build is always distributed as an `.app` with its sidecar
/// inside, so a missing sidecar there is reported as a startup error rather
/// than silently pointing the client at a backend that does not exist.
class BackendService {
  BackendService({
    Duration? startupTimeout,
    this.healthTimeout = const Duration(milliseconds: 800),
    this.pollInterval = const Duration(milliseconds: 250),
    BackendHostPlatform? hostPlatform,
    String? resolvedExecutable,
    bool? requirePackagedBackend,
  }) : hostPlatform = hostPlatform ?? _currentHostPlatform(),
       _resolvedExecutable = resolvedExecutable,
       _requirePackagedBackend = requirePackagedBackend,
       startupTimeout =
           startupTimeout ??
           // First launch of a downloaded macOS app validates the signature
           // of every bundled native library before the sidecar can import
           // them; Windows keeps its existing budget.
           ((hostPlatform ?? _currentHostPlatform()) ==
                   BackendHostPlatform.macos
               ? const Duration(seconds: 45)
               : const Duration(seconds: 15));

  final Duration startupTimeout;
  final Duration healthTimeout;
  final Duration pollInterval;
  final BackendHostPlatform hostPlatform;
  final String? _resolvedExecutable;
  final bool? _requirePackagedBackend;

  /// Packaged sidecar locations for [hostPlatform], in lookup order.
  ///
  /// These must match the packaging scripts exactly:
  /// - Windows (`scripts/build_pilot.ps1`): `<app dir>\backend\elixr_backend.exe`
  /// - macOS (`scripts/build_macos_release.sh`):
  ///   `ELIXR.app/Contents/Resources/backend/elixr_backend`, resolved from the
  ///   runner executable at `ELIXR.app/Contents/MacOS/ELIXR`.
  static List<String> packagedBackendCandidates({
    required BackendHostPlatform hostPlatform,
    required String resolvedExecutable,
  }) {
    switch (hostPlatform) {
      case BackendHostPlatform.windows:
        final appDir = _parentPath(resolvedExecutable, r'\');
        return <String>[
          '$appDir\\backend\\elixr_backend.exe',
          '$appDir\\elixr_backend.exe',
        ];
      case BackendHostPlatform.macos:
        final macOsDir = _parentPath(resolvedExecutable, '/');
        final contentsDir = _parentPath(macOsDir, '/');
        return <String>['$contentsDir/Resources/backend/elixr_backend'];
      case BackendHostPlatform.unsupported:
        return const <String>[];
    }
  }

  static String _parentPath(String path, String separator) {
    var trimmed = path;
    while (trimmed.length > 1 && trimmed.endsWith(separator)) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    // Windows paths may also use forward slashes.
    final index = separator == r'\'
        ? trimmed.lastIndexOf(RegExp(r'[\\/]'))
        : trimmed.lastIndexOf(separator);
    if (index <= 0) return index == 0 ? separator : '.';
    return trimmed.substring(0, index);
  }

  Process? _process;
  Future<void>? _startFuture;
  bool _startAttempted = false;
  bool _stopping = false;

  bool get managesPackagedBackend => _process != null;

  Future<void> start() {
    if (_startAttempted) return _startFuture ?? Future<void>.value();
    _startAttempted = true;
    final future = _startInternal();
    _startFuture = future;
    return future;
  }

  Future<void> _startInternal() async {
    if (hostPlatform == BackendHostPlatform.unsupported) return;

    final executable = _findPackagedExecutable();
    if (executable == null) {
      BackendRuntime.reset();
      final requirePackaged =
          _requirePackagedBackend ??
          (hostPlatform == BackendHostPlatform.macos && kReleaseMode);
      if (requirePackaged) {
        BackendRuntime.setStartupError(
          'The ELIXR vision backend is missing from this installation. '
          'Reinstall ELIXR from the latest download.',
        );
      }
      return;
    }

    try {
      final port = await _findFreePort();
      BackendRuntime.usePort(port);

      final environment = Map<String, String>.from(Platform.environment)
        // A developer's shell must not redirect the installed sidecar to
        // repository-local model paths or Python modules.
        ..remove('YOLO_MODEL_PATH')
        ..remove('YOLO_ONNX_MODEL_PATH')
        ..remove('PYTHONPATH')
        ..remove('PYTHONHOME');

      final process = await Process.start(
        executable.path,
        <String>[
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '--parent-pid',
          '$pid',
        ],
        workingDirectory: executable.parent.path,
        environment: environment,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _process = process;
      unawaited(_discard(process.stdout));
      unawaited(_discard(process.stderr));
      unawaited(_observeExit(process));

      await _waitForHealth(port);
    } on Object {
      BackendRuntime.setStartupError(
        'The ELIXR vision backend could not start. '
        'Restart ELIXR or reinstall the pilot package.',
      );
      await _stopProcess();
    }
  }

  Future<void> _observeExit(Process process) async {
    try {
      await process.exitCode;
      if (identical(_process, process) && !_stopping) {
        _process = null;
        BackendRuntime.setStartupError(
          'The ELIXR vision backend stopped unexpectedly. '
          'Restart ELIXR to try again.',
        );
      }
    } on Object {
      // The process is already being torn down; there is nothing to surface.
    }
  }

  Future<void> _waitForHealth(int port) async {
    final deadline = DateTime.now().add(startupTimeout);
    final endpoint = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: '/health',
    );

    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) {
        throw StateError('The backend process exited before readiness.');
      }
      if (await _healthCheck(endpoint)) return;
      await Future<void>.delayed(pollInterval);
    }
    throw TimeoutException('The backend health check timed out.');
  }

  Future<bool> _healthCheck(Uri endpoint) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(endpoint).timeout(healthTimeout);
      final response = await request.close().timeout(healthTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(healthTimeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> && decoded['status'] == 'ok';
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  File? _findPackagedExecutable() {
    final candidates = packagedBackendCandidates(
      hostPlatform: hostPlatform,
      resolvedExecutable: _resolvedExecutable ?? Platform.resolvedExecutable,
    );
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    return null;
  }

  Future<void> _stopProcess() async {
    final process = _process;
    _process = null;
    if (process == null) return;

    _stopping = true;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on Object {
      process.kill(ProcessSignal.sigkill);
    } finally {
      _stopping = false;
    }
  }

  Future<void> _discard(Stream<List<int>> stream) async {
    try {
      await stream.drain<void>();
    } on Object {
      // Console-free child output is intentionally discarded.
    }
  }

  /// Requests backend termination during Flutter engine teardown.
  ///
  /// Killing the owned process happens before the first async suspension;
  /// waiting for exit is best-effort because Flutter's dispose API is sync.
  void dispose() {
    _stopping = true;
    unawaited(_stopProcess());
    BackendRuntime.reset();
  }
}
