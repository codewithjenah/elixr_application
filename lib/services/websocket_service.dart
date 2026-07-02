import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/app_constants.dart';
import '../data/models/practice_feedback.dart';

enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _feedbackController = StreamController<PracticeFeedback>.broadcast();

  WebSocketConnectionState _connectionState =
      WebSocketConnectionState.disconnected;
  String? _errorMessage;
  bool _sessionActive = false;

  WebSocketConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  bool get isConnected =>
      _connectionState == WebSocketConnectionState.connected;
  bool get sessionActive => _sessionActive;
  Stream<PracticeFeedback> get feedbackStream => _feedbackController.stream;

  Future<void> connect() async {
    if (_connectionState == WebSocketConnectionState.connecting ||
        _connectionState == WebSocketConnectionState.connected) {
      return;
    }

    _setState(WebSocketConnectionState.connecting);
    _errorMessage = null;

    try {
      final channel = WebSocketChannel.connect(Uri.parse(AppConstants.wsUrl));
      _channel = channel;

      await channel.ready.timeout(const Duration(seconds: 5));

      _subscription = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );

      _setState(WebSocketConnectionState.connected);
    } catch (e) {
      _errorMessage = 'Unable to connect to backend. Is it running?';
      _setState(WebSocketConnectionState.error);
      await _cleanupChannel();
    }
  }

  void sendStart({
    required String movement,
    required String difficulty,
    bool bottleDetectionEnabled = true,
  }) {
    if (!isConnected || _channel == null) return;

    _channel!.sink.add(jsonEncode({
      'action': 'start',
      'movement': movement,
      'difficulty': difficulty,
      'bottle_detection_enabled': bottleDetectionEnabled,
    }));
    _sessionActive = true;
    notifyListeners();
  }

  void sendStop() {
    if (_channel != null && isConnected) {
      _channel!.sink.add(jsonEncode({'action': 'stop'}));
    }
    _sessionActive = false;
    notifyListeners();
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final feedback = PracticeFeedback.fromJson(data);
      _feedbackController.add(feedback);
    } catch (_) {
      // Ignore malformed frames.
    }
  }

  void _onError(Object error) {
    _errorMessage = 'Connection lost.';
    _sessionActive = false;
    _setState(WebSocketConnectionState.error);
    _cleanupChannel();
  }

  void _onDone() {
    _sessionActive = false;
    if (_connectionState != WebSocketConnectionState.error) {
      _setState(WebSocketConnectionState.disconnected);
    }
    _cleanupChannel();
  }

  void _setState(WebSocketConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  Future<void> _cleanupChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> disconnect() async {
    sendStop();
    await _cleanupChannel();
    _setState(WebSocketConnectionState.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _feedbackController.close();
    super.dispose();
  }
}
