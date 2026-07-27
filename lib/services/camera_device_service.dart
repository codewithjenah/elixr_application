import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../data/models/camera_device.dart';

enum CameraDiscoveryState { idle, loading, success, empty, error }

typedef CameraHttpGet = Future<String> Function(Uri uri);

class CameraDeviceService extends ChangeNotifier {
  CameraDeviceService({CameraHttpGet? httpGet, Uri? endpoint})
    : _httpGet = httpGet ?? _defaultHttpGet,
      _endpoint = endpoint ?? Uri.parse(AppConstants.backendHttpBaseUrl);

  final CameraHttpGet _httpGet;
  final Uri _endpoint;

  CameraDiscoveryState _state = CameraDiscoveryState.idle;
  List<CameraDevice> _cameras = const [];
  int? _preferredIndex;
  int? _fallbackIndex;
  int? _activeIndex;
  String? _errorMessage;

  CameraDiscoveryState get state => _state;
  List<CameraDevice> get cameras => _cameras;
  int? get preferredIndex => _preferredIndex;
  int? get fallbackIndex => _fallbackIndex;
  int? get activeIndex => _activeIndex;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == CameraDiscoveryState.loading;

  Future<void> refresh() async {
    if (_state == CameraDiscoveryState.loading) return;

    _state = CameraDiscoveryState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = await _httpGet(_endpoint.replace(path: '/cameras'));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected cameras response');
      }

      final result = CameraDiscoveryResult.fromJson(decoded);
      _cameras = List.unmodifiable(result.cameras);
      _preferredIndex = result.preferredIndex;
      _fallbackIndex = result.fallbackIndex;
      _activeIndex = result.activeIndex;

      if (_cameras.isEmpty) {
        _state = CameraDiscoveryState.empty;
      } else {
        _state = CameraDiscoveryState.success;
      }
    } on SocketException {
      _cameras = const [];
      _state = CameraDiscoveryState.error;
      _errorMessage = 'Backend unavailable — start the Python server';
    } on TimeoutException {
      _cameras = const [];
      _state = CameraDiscoveryState.error;
      _errorMessage = 'Backend unavailable — start the Python server';
    } on FormatException {
      _cameras = const [];
      _state = CameraDiscoveryState.error;
      _errorMessage = 'Backend returned an invalid camera list';
    } catch (_) {
      _cameras = const [];
      _state = CameraDiscoveryState.error;
      _errorMessage = 'Backend unavailable — start the Python server';
    }

    notifyListeners();
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
