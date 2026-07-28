import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../data/models/camera_device.dart';

enum CameraDiscoveryState { idle, loading, success, empty, error }

/// Distinguishes refresh failures for UI messaging and tests.
enum CameraDiscoveryErrorKind {
  none,
  backendUnreachable,
  scanTimeout,
  httpError,
  invalidResponse,
  unknown,
}

typedef CameraHttpGet = Future<String> Function(Uri uri);

class CameraDeviceService extends ChangeNotifier {
  CameraDeviceService({CameraHttpGet? httpGet, Uri? endpoint})
    : _httpGet = httpGet ?? _defaultHttpGet,
      _endpoint = endpoint ?? Uri.parse(AppConstants.backendHttpBaseUrl);

  final CameraHttpGet _httpGet;
  final Uri _endpoint;

  CameraDiscoveryState _state = CameraDiscoveryState.idle;
  List<CameraDevice> _cameras = const [];
  String? _activeDeviceId;
  int? _activeIndex;
  String? _errorMessage;
  CameraDiscoveryErrorKind _errorKind = CameraDiscoveryErrorKind.none;

  CameraDiscoveryState get state => _state;
  List<CameraDevice> get cameras => _cameras;
  String? get activeDeviceId => _activeDeviceId;
  int? get activeIndex => _activeIndex;
  String? get errorMessage => _errorMessage;
  CameraDiscoveryErrorKind get errorKind => _errorKind;
  bool get isLoading => _state == CameraDiscoveryState.loading;

  /// Labels for UI when duplicate friendly names exist.
  List<String> get distinguishableLabels =>
      distinguishableCameraLabels(_cameras);

  CameraDevice? findByDeviceId(String? deviceId) {
    if (deviceId == null) return null;
    for (final camera in _cameras) {
      if (camera.deviceId == deviceId) return camera;
    }
    return null;
  }

  /// Legacy migration helper: map an old runtime index to a discovered device.
  CameraDevice? findByRuntimeIndex(int? runtimeIndex) {
    if (runtimeIndex == null) return null;
    for (final camera in _cameras) {
      if (camera.runtimeIndex == runtimeIndex) return camera;
    }
    return null;
  }

  /// Refreshes the camera list.
  ///
  /// [forceRefresh] bypasses the backend's short-lived discovery cache. Use
  /// this for an explicit user-initiated refresh so a stale cached result
  /// (e.g. from before a camera was plugged in) is not returned unchanged.
  Future<void> refresh({bool forceRefresh = false}) async {
    if (_state == CameraDiscoveryState.loading) return;

    _state = CameraDiscoveryState.loading;
    _errorMessage = null;
    _errorKind = CameraDiscoveryErrorKind.none;
    notifyListeners();

    try {
      final body = await _httpGet(
        _endpoint.replace(
          path: '/cameras',
          queryParameters: forceRefresh ? {'force_refresh': 'true'} : null,
        ),
      );
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected cameras response');
      }

      final result = CameraDiscoveryResult.fromJson(decoded);
      _cameras = List.unmodifiable(result.cameras);
      _activeDeviceId = result.activeDeviceId;
      _activeIndex = result.activeIndex;

      if (_cameras.isEmpty) {
        _state = CameraDiscoveryState.empty;
      } else {
        _state = CameraDiscoveryState.success;
      }
    } on SocketException {
      _setError(
        CameraDiscoveryErrorKind.backendUnreachable,
        'Backend unavailable — start the Python server',
        preserveCameras: true,
      );
    } on TimeoutException {
      final backendOnline = await _checkBackendHealth();
      if (backendOnline) {
        _setError(
          CameraDiscoveryErrorKind.scanTimeout,
          'Backend online — camera scan took too long. Try refreshing again.',
          preserveCameras: true,
        );
      } else {
        _setError(
          CameraDiscoveryErrorKind.backendUnreachable,
          'Backend unavailable — start the Python server',
          preserveCameras: true,
        );
      }
    } on HttpException catch (error) {
      _setError(
        CameraDiscoveryErrorKind.httpError,
        'Camera list request failed (${error.message})',
        preserveCameras: true,
      );
    } on FormatException {
      _setError(
        CameraDiscoveryErrorKind.invalidResponse,
        'Backend returned an invalid camera list',
        preserveCameras: false,
      );
    } catch (error) {
      _setError(
        CameraDiscoveryErrorKind.unknown,
        'Camera discovery failed ($error)',
        preserveCameras: true,
      );
    }

    notifyListeners();
  }

  void _setError(
    CameraDiscoveryErrorKind kind,
    String message, {
    required bool preserveCameras,
  }) {
    _state = CameraDiscoveryState.error;
    _errorKind = kind;
    _errorMessage = message;
    if (!preserveCameras) {
      _cameras = const [];
      _activeDeviceId = null;
      _activeIndex = null;
    }
  }

  Future<bool> _checkBackendHealth() async {
    try {
      await _httpGet(_endpoint.replace(path: '/health'));
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on HttpException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _defaultHttpGet(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
