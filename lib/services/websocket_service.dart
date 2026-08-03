import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/app_constants.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/training_prop.dart';
import '../data/models/ws_protocol.dart';

enum WebSocketConnectionState { disconnected, connecting, connected, error }

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class WebSocketService extends ChangeNotifier {
  WebSocketService({
    WebSocketChannelFactory? channelFactory,
    this.commandTimeout = const Duration(seconds: 15),
    this.prepareTimeout = const Duration(seconds: 25),
    WsMessageDecoder decoder = const WsMessageDecoder(),
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect,
       _decoder = decoder;

  final WebSocketChannelFactory _channelFactory;
  final WsMessageDecoder _decoder;
  final Duration commandTimeout;
  final Duration prepareTimeout;

  WebSocketChannel? _channel;
  StreamSink<dynamic>? _outboundSink;
  StreamSubscription<dynamic>? _subscription;
  final _feedbackController = StreamController<PracticeFeedback>.broadcast();
  final _protocolErrorController =
      StreamController<ProtocolErrorMessage>.broadcast();

  WebSocketConnectionState _connectionState =
      WebSocketConnectionState.disconnected;
  String? _errorMessage;
  bool _sessionPrepared = false;
  bool _sessionActive = false;
  String? _currentSessionId;
  ProtocolErrorMessage? _lastProtocolError;
  int _protocolErrorCount = 0;
  bool _disposing = false;
  bool _disposed = false;

  final Map<String, _PendingCommand> _pending = {};
  int _idCounter = 0;

  /// Shared in-flight stop for the same [sessionId] (idempotent coalescing).
  Future<CommandAck>? _inFlightStop;
  String? _inFlightStopSessionId;

  /// Stops for a different session wait here until earlier stops settle.
  final List<_QueuedStopRequest> _queuedStops = [];
  bool _stopQueueDrainScheduled = false;
  bool _stopQueueDraining = false;

  static const int _maxTrackedProtocolErrors = 20;
  static const int _maxIdLength = 128;

  WebSocketConnectionState get connectionState => _connectionState;
  String? get errorMessage => _errorMessage;
  bool get isConnected =>
      _connectionState == WebSocketConnectionState.connected;

  /// Camera session prepared (preview may stream). Not the same as training.
  bool get sessionPrepared => _sessionPrepared;

  /// Movement evaluation / scoring is active after accepted activate/start.
  bool get sessionActive => _sessionActive;

  /// Practice-attempt identity for the current prepare/activate lifecycle.
  String? get currentSessionId => _currentSessionId;

  ProtocolErrorMessage? get lastProtocolError => _lastProtocolError;
  int get protocolErrorCount => _protocolErrorCount;

  Stream<PracticeFeedback> get feedbackStream => _feedbackController.stream;
  Stream<ProtocolErrorMessage> get protocolErrorStream =>
      _protocolErrorController.stream;

  @visibleForTesting
  bool get hasPendingCommands => _pending.isNotEmpty;

  @visibleForTesting
  int get pendingCommandCount => _pending.length;

  Future<void> connect() async {
    if (_connectionState == WebSocketConnectionState.connecting ||
        _connectionState == WebSocketConnectionState.connected) {
      return;
    }

    _setState(WebSocketConnectionState.connecting);
    _errorMessage = null;

    try {
      final channel = _channelFactory(Uri.parse(AppConstants.wsUrl));
      _channel = channel;
      _outboundSink = channel.sink;

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

  /// Starts a new practice attempt identity. Call before [sendPrepare] when
  /// the UI needs the session id up front; otherwise prepare allocates one.
  String beginPracticeAttempt() {
    final sessionId = _nextId('session');
    _currentSessionId = sessionId;
    _sessionPrepared = false;
    _sessionActive = false;
    if (!_disposing) notifyListeners();
    return sessionId;
  }

  Future<CommandAck> sendPrepare({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    String? sessionId,
  }) {
    final resolvedSessionId =
        sessionId ?? _currentSessionId ?? beginPracticeAttempt();
    _currentSessionId = resolvedSessionId;

    return _sendTrackedCommand(
      action: 'prepare',
      timeout: prepareTimeout,
      sessionId: resolvedSessionId,
      payload: buildPreparePayload(
        movement: movement,
        difficulty: difficulty,
        prop: prop,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: legacyCameraIndex,
        sessionId: resolvedSessionId,
        requestId: _nextId('req'),
      ),
    );
  }

  Future<CommandAck> sendActivate({String? sessionId}) {
    final resolvedSessionId = sessionId ?? _currentSessionId;
    if (resolvedSessionId == null || resolvedSessionId.isEmpty) {
      return Future.error(
        StateError('Cannot activate without a current session_id'),
      );
    }

    return _sendTrackedCommand(
      action: 'activate',
      timeout: commandTimeout,
      sessionId: resolvedSessionId,
      payload: buildActivatePayload(
        sessionId: resolvedSessionId,
        requestId: _nextId('req'),
      ),
    );
  }

  /// Legacy start: prepare + immediate activation on the backend.
  Future<CommandAck> sendStart({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    String? sessionId,
  }) {
    final resolvedSessionId =
        sessionId ?? _currentSessionId ?? beginPracticeAttempt();
    _currentSessionId = resolvedSessionId;

    return _sendTrackedCommand(
      action: 'start',
      timeout: prepareTimeout,
      sessionId: resolvedSessionId,
      payload: buildStartPayload(
        movement: movement,
        difficulty: difficulty,
        prop: prop,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: legacyCameraIndex,
        sessionId: resolvedSessionId,
        requestId: _nextId('req'),
      ),
    );
  }

  /// Idempotent stop for the current (or explicit) practice session.
  ///
  /// Concurrent callers for the same session share one wire command and one
  /// completion future. Stops for different sessions are serialized: a later
  /// session waits for the in-flight stop to settle before sending its own
  /// payload. Clears [currentSessionId] immediately so a new attempt can
  /// allocate a fresh identity before the stop acknowledgment arrives.
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    final resolvedSessionId = sessionId ?? _currentSessionId;
    if (resolvedSessionId == null || resolvedSessionId.isEmpty) {
      _clearSessionFlags();
      return Future.value(_noopStopAck);
    }

    if (_inFlightStop != null && _inFlightStopSessionId == resolvedSessionId) {
      return _inFlightStop!;
    }

    for (final pending in _pending.values) {
      if (pending.action == 'stop' && pending.sessionId == resolvedSessionId) {
        _inFlightStop = pending.completer.future;
        _inFlightStopSessionId = resolvedSessionId;
        return _inFlightStop!;
      }
    }

    for (final queued in _queuedStops) {
      if (queued.sessionId == resolvedSessionId) {
        return queued.completer.future;
      }
    }

    if (_mustQueueStopBehindExistingWork(resolvedSessionId)) {
      _clearCurrentSessionIfStopping(resolvedSessionId);
      final completer = Completer<CommandAck>();
      _queuedStops.add(
        _QueuedStopRequest(sessionId: resolvedSessionId, completer: completer),
      );
      _scheduleStopQueueDrain();
      return completer.future;
    }

    _clearCurrentSessionIfStopping(resolvedSessionId);
    return _startStop(resolvedSessionId);
  }

  /// Non-empty queue or a different-session in-flight stop blocks new stops.
  bool _mustQueueStopBehindExistingWork(String sessionId) {
    if (_queuedStops.isNotEmpty) {
      return true;
    }
    return _hasDifferentSessionStopInFlight(sessionId);
  }

  /// Clears current-session identity on the first stop request for that session.
  void _clearCurrentSessionIfStopping(String resolvedSessionId) {
    if (_currentSessionId != resolvedSessionId) {
      return;
    }
    _currentSessionId = null;
    _sessionPrepared = false;
    _sessionActive = false;
    if (!_disposing) notifyListeners();
  }

  bool _hasDifferentSessionStopInFlight(String sessionId) {
    if (_inFlightStop != null && _inFlightStopSessionId != sessionId) {
      return true;
    }
    for (final pending in _pending.values) {
      if (pending.action == 'stop' && pending.sessionId != sessionId) {
        return true;
      }
    }
    return false;
  }

  Future<CommandAck> _startStop(String resolvedSessionId) {
    final future =
        _sendTrackedCommand(
          action: 'stop',
          timeout: commandTimeout,
          sessionId: resolvedSessionId,
          payload: buildStopPayload(
            sessionId: resolvedSessionId,
            requestId: _nextId('req'),
          ),
        ).whenComplete(() {
          if (_inFlightStopSessionId == resolvedSessionId) {
            _inFlightStop = null;
            _inFlightStopSessionId = null;
          }
          _scheduleStopQueueDrain();
        });

    _inFlightStop = future;
    _inFlightStopSessionId = resolvedSessionId;
    return future;
  }

  void _scheduleStopQueueDrain() {
    if (_stopQueueDrainScheduled) return;
    _stopQueueDrainScheduled = true;
    scheduleMicrotask(() {
      _stopQueueDrainScheduled = false;
      unawaited(_drainStopQueue());
    });
  }

  Future<void> _drainStopQueue() async {
    if (_stopQueueDraining) return;
    _stopQueueDraining = true;
    try {
      await _drainStopQueueBody();
    } finally {
      _stopQueueDraining = false;
    }
  }

  Future<void> _drainStopQueueBody() async {
    while (_queuedStops.isNotEmpty) {
      if (!isConnected || _outboundSink == null) {
        _failQueuedStops(CommandDisconnectedException('', 'stop'));
        return;
      }

      final next = _queuedStops.first;

      if (_inFlightStop != null && _inFlightStopSessionId == next.sessionId) {
        _queuedStops.removeAt(0);
        try {
          final ack = await _inFlightStop!;
          if (!next.completer.isCompleted) {
            next.completer.complete(ack);
          }
        } catch (error, stackTrace) {
          if (!next.completer.isCompleted) {
            next.completer.completeError(error, stackTrace);
          }
        }
        continue;
      }

      if (_hasDifferentSessionStopInFlight(next.sessionId)) {
        return;
      }

      _queuedStops.removeAt(0);
      try {
        final ack = await _startStop(next.sessionId);
        if (!next.completer.isCompleted) {
          next.completer.complete(ack);
        }
      } catch (error, stackTrace) {
        if (!next.completer.isCompleted) {
          next.completer.completeError(error, stackTrace);
        }
      }
    }
  }

  void _failQueuedStops(Object error) {
    while (_queuedStops.isNotEmpty) {
      final queued = _queuedStops.removeAt(0);
      if (!queued.completer.isCompleted) {
        queued.completer.completeError(error);
      }
    }
  }

  /// Legacy alias; prefer [stopPracticeSession] for practice teardown.
  Future<CommandAck> sendStop({String? sessionId}) =>
      stopPracticeSession(sessionId: sessionId);

  static const CommandAck _noopStopAck = CommandAck(
    protocolVersion: wsProtocolVersion,
    requestId: '',
    action: 'stop',
    accepted: true,
    sessionState: 'idle',
  );

  /// Builds the WebSocket prepare payload. Exposed for unit tests.
  @visibleForTesting
  static Map<String, dynamic> buildPreparePayload({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    required String sessionId,
    required String requestId,
  }) {
    return _buildSessionPayload(
      action: 'prepare',
      movement: movement,
      difficulty: difficulty,
      prop: prop,
      cameraDeviceId: cameraDeviceId,
      legacyCameraIndex: legacyCameraIndex,
      sessionId: sessionId,
      requestId: requestId,
    );
  }

  /// Builds the WebSocket activate payload. Exposed for unit tests.
  @visibleForTesting
  static Map<String, dynamic> buildActivatePayload({
    required String sessionId,
    required String requestId,
  }) {
    return <String, dynamic>{
      'protocol_version': wsProtocolVersion,
      'request_id': requestId,
      'session_id': sessionId,
      'action': 'activate',
    };
  }

  /// Builds the WebSocket start payload. Exposed for unit tests.
  @visibleForTesting
  static Map<String, dynamic> buildStartPayload({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    required String sessionId,
    required String requestId,
  }) {
    return _buildSessionPayload(
      action: 'start',
      movement: movement,
      difficulty: difficulty,
      prop: prop,
      cameraDeviceId: cameraDeviceId,
      legacyCameraIndex: legacyCameraIndex,
      sessionId: sessionId,
      requestId: requestId,
    );
  }

  /// Builds the WebSocket stop payload. Exposed for unit tests.
  @visibleForTesting
  static Map<String, dynamic> buildStopPayload({
    required String sessionId,
    required String requestId,
  }) {
    return <String, dynamic>{
      'protocol_version': wsProtocolVersion,
      'request_id': requestId,
      'session_id': sessionId,
      'action': 'stop',
    };
  }

  static Map<String, dynamic> _buildSessionPayload({
    required String action,
    required String movement,
    required String difficulty,
    required TrainingProp prop,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    required String sessionId,
    required String requestId,
  }) {
    final payload = <String, dynamic>{
      'protocol_version': wsProtocolVersion,
      'request_id': requestId,
      'session_id': sessionId,
      'action': action,
      'movement': movement,
      'difficulty': difficulty,
      'prop_type': prop.protocolValue,
      'bottle_detection_enabled': true,
    };

    // Prefer stable device identity. Only while a one-time settings migration
    // is still pending, fall back to the legacy runtime index.
    if (cameraDeviceId != null || legacyCameraIndex == null) {
      payload['camera_device_id'] = cameraDeviceId;
    } else {
      payload['camera_index'] = legacyCameraIndex;
    }
    return payload;
  }

  Future<CommandAck> _sendTrackedCommand({
    required String action,
    required Duration timeout,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) {
    if (!isConnected || _outboundSink == null) {
      return Future.error(StateError('WebSocket is not connected'));
    }

    final requestId = payload['request_id'] as String;
    if (_pending.containsKey(requestId)) {
      return Future.error(StateError('Duplicate request_id $requestId'));
    }

    // Deterministic duplicate-action handling: one in-flight command per action.
    for (final pending in _pending.values) {
      if (pending.action == action) {
        if (action == 'stop' && pending.sessionId == sessionId) {
          return pending.completer.future;
        }
        if (action != 'stop') {
          return Future.error(
            StateError('A $action command is already pending'),
          );
        }
        // Different-session stops are serialized by [stopPracticeSession].
        return Future.error(
          StateError(
            'A stop for session ${pending.sessionId} is already pending',
          ),
        );
      }
    }

    final completer = Completer<CommandAck>();
    final timer = Timer(timeout, () {
      final pending = _pending.remove(requestId);
      if (pending == null || pending.completer.isCompleted) return;
      _recordProtocolError(
        ProtocolErrorMessage(
          protocolVersion: wsProtocolVersion,
          requestId: requestId,
          sessionId: sessionId,
          errorCode: 'command_timeout',
          message: 'Timed out waiting for $action acknowledgment.',
        ),
      );
      pending.completer.completeError(
        CommandTimeoutException(requestId, action),
      );
    });

    _pending[requestId] = _PendingCommand(
      action: action,
      sessionId: sessionId,
      completer: completer,
      timer: timer,
    );

    try {
      _outboundSink!.add(jsonEncode(payload));
    } catch (error) {
      _failPending(requestId, error);
    }

    // Intentionally do not mutate sessionPrepared / sessionActive here.
    return completer.future;
  }

  void _onMessage(dynamic message) {
    final decoded = _decoder.decode(message);
    switch (decoded) {
      case WsFeedbackMessage(:final feedback):
        _handleFeedback(feedback);
      case WsCommandAckMessage(:final ack):
        _handleAck(ack);
      case WsProtocolErrorInbound(:final error):
        _recordProtocolError(error);
      case WsUnknownMessage(:final messageType):
        _recordProtocolError(
          ProtocolErrorMessage(
            protocolVersion: wsProtocolVersion,
            errorCode: 'unknown_message_type',
            message: 'Unknown message_type: ${messageType ?? '(null)'}',
          ),
        );
      case WsMalformedMessage(:final reason):
        _recordProtocolError(
          ProtocolErrorMessage(
            protocolVersion: wsProtocolVersion,
            errorCode: 'invalid_json',
            message: reason,
          ),
        );
    }
  }

  void _handleFeedback(PracticeFeedback feedback) {
    final feedbackSessionId = feedback.sessionId;
    if (feedbackSessionId != null) {
      if (_currentSessionId == null || feedbackSessionId != _currentSessionId) {
        // Stale feedback from an older attempt or after stop cleared identity.
        return;
      }
    }

    if (feedbackSessionId != null && feedback.sessionState != null) {
      _reconcileFromSessionState(feedback.sessionState!);
    }

    if (!_feedbackController.isClosed) {
      _feedbackController.add(feedback);
    }
  }

  void _handleAck(CommandAck ack) {
    final pending = _pending.remove(ack.requestId);
    pending?.timer.cancel();

    if (pending != null) {
      final actionMismatch = ack.action != pending.action;
      final sessionMismatch =
          ack.sessionId != null && ack.sessionId != pending.sessionId;

      if (actionMismatch) {
        _recordProtocolError(
          ProtocolErrorMessage(
            protocolVersion: ack.protocolVersion,
            requestId: ack.requestId,
            sessionId: ack.sessionId,
            errorCode: 'ack_action_mismatch',
            message:
                'Acknowledgment action "${ack.action}" does not match pending '
                '${pending.action}.',
          ),
        );
      }
      if (sessionMismatch) {
        _recordProtocolError(
          ProtocolErrorMessage(
            protocolVersion: ack.protocolVersion,
            requestId: ack.requestId,
            sessionId: ack.sessionId,
            errorCode: 'ack_session_mismatch',
            message:
                'Acknowledgment session_id "${ack.sessionId}" does not match '
                'pending ${pending.sessionId}.',
          ),
        );
      }

      if (actionMismatch || sessionMismatch) {
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            CommandAckMismatchException(
              requestId: ack.requestId,
              pendingAction: pending.action,
              pendingSessionId: pending.sessionId,
              ackAction: ack.action,
              ackSessionId: ack.sessionId,
              actionMismatch: actionMismatch,
              sessionMismatch: sessionMismatch,
            ),
          );
        }
        return;
      }

      final mayApplyLifecycle = _ackMatchesCurrentSession(ack, pending);

      if (mayApplyLifecycle) {
        if (ack.accepted) {
          _applyAcceptedAck(ack, pendingSessionId: pending.sessionId);
        } else if (ack.sessionState != null) {
          _reconcileFromSessionState(ack.sessionState!);
        }
      }

      if (!pending.completer.isCompleted) {
        pending.completer.complete(ack);
      }
      return;
    }

    if (ack.errorCode != null) {
      // Unsolicited rejection still surfaces as protocol observability.
      _recordProtocolError(
        ProtocolErrorMessage(
          protocolVersion: ack.protocolVersion,
          requestId: ack.requestId,
          sessionId: ack.sessionId,
          errorCode: ack.errorCode!,
          message: ack.message ?? ack.errorCode!,
        ),
      );
    }
  }

  bool _ackMatchesCurrentSession(CommandAck ack, _PendingCommand pending) {
    if (ack.sessionId == null) {
      return true;
    }
    if (ack.action == 'stop') {
      // Stop may clear [currentSessionId] before the ack arrives.
      return ack.sessionId == pending.sessionId;
    }
    return _currentSessionId == null || ack.sessionId == _currentSessionId;
  }

  void _applyAcceptedAck(CommandAck ack, {String? pendingSessionId}) {
    switch (ack.action) {
      case 'prepare':
        if (ack.sessionState == 'preparing' || ack.sessionState == null) {
          _sessionPrepared = true;
          _sessionActive = false;
          if (ack.sessionId != null) {
            _currentSessionId = ack.sessionId;
          }
        } else {
          _reconcileFromSessionState(ack.sessionState!);
        }
      case 'activate':
      case 'start':
        _sessionPrepared = true;
        _sessionActive = true;
        if (ack.sessionId != null) {
          _currentSessionId = ack.sessionId;
        }
      case 'stop':
        final stopSessionId = ack.sessionId ?? pendingSessionId;
        if (stopSessionId == null ||
            _currentSessionId == null ||
            stopSessionId == _currentSessionId) {
          _sessionPrepared = false;
          _sessionActive = false;
          if (stopSessionId != null && _currentSessionId == stopSessionId) {
            _currentSessionId = null;
          }
        }
      default:
        if (ack.sessionState != null) {
          _reconcileFromSessionState(ack.sessionState!);
        }
    }
    if (!_disposing) notifyListeners();
  }

  void _reconcileFromSessionState(String sessionState) {
    final previousPrepared = _sessionPrepared;
    final previousActive = _sessionActive;
    switch (sessionState) {
      case 'preparing':
        _sessionPrepared = true;
        _sessionActive = false;
      case 'active':
        _sessionPrepared = true;
        _sessionActive = true;
      case 'idle':
      case 'unavailable':
        _sessionPrepared = false;
        _sessionActive = false;
      default:
        return;
    }
    if ((previousPrepared != _sessionPrepared ||
            previousActive != _sessionActive) &&
        !_disposing) {
      notifyListeners();
    }
  }

  void _recordProtocolError(ProtocolErrorMessage error) {
    _lastProtocolError = error;
    if (_protocolErrorCount < _maxTrackedProtocolErrors * 1000) {
      _protocolErrorCount++;
    }
    if (kDebugMode) {
      debugPrint(
        'WebSocket protocol error: ${error.errorCode} — ${error.message}',
      );
    }
    if (!_protocolErrorController.isClosed) {
      _protocolErrorController.add(error);
    }
    if (!_disposing) notifyListeners();
  }

  void _failPending(String requestId, Object error) {
    final pending = _pending.remove(requestId);
    pending?.timer.cancel();
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error);
    }
  }

  void _failAllPending(Object error) {
    final pending = Map<String, _PendingCommand>.from(_pending);
    _pending.clear();
    for (final entry in pending.values) {
      entry.timer.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(error);
      }
    }
    _inFlightStop = null;
    _inFlightStopSessionId = null;
    _failQueuedStops(error);
  }

  void _clearSessionFlags({bool notify = true}) {
    _sessionPrepared = false;
    _sessionActive = false;
    if (notify && !_disposing) notifyListeners();
  }

  void _onError(Object error) {
    _errorMessage = 'Connection lost.';
    _clearSessionFlags(notify: false);
    _currentSessionId = null;
    _failAllPending(CommandDisconnectedException('', 'connection_error'));
    _setState(WebSocketConnectionState.error);
    _cleanupChannel();
  }

  void _onDone() {
    _clearSessionFlags(notify: false);
    _currentSessionId = null;
    _failAllPending(CommandDisconnectedException('', 'connection_closed'));
    if (_connectionState != WebSocketConnectionState.error) {
      _setState(WebSocketConnectionState.disconnected);
    }
    _cleanupChannel();
  }

  void _setState(WebSocketConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_disposing) notifyListeners();
  }

  Future<void> _cleanupChannel() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _outboundSink = null;
  }

  Future<void> disconnect() async {
    try {
      if (_currentSessionId != null && isConnected) {
        await stopPracticeSession().timeout(commandTimeout);
      }
    } on CommandTimeoutException {
      // Best-effort stop during disconnect.
    } on CommandAckMismatchException {
      // Stop ack did not match; session identity was already cleared.
    } on CommandDisconnectedException {
      // Socket may already be closing.
    }
    _failAllPending(CommandDisconnectedException('', 'disconnect'));
    _clearSessionFlags(notify: false);
    _currentSessionId = null;
    await _cleanupChannel();
    _setState(WebSocketConnectionState.disconnected);
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    final raw = '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
    if (raw.length <= _maxIdLength) return raw;
    return raw.substring(0, _maxIdLength);
  }

  @visibleForTesting
  void debugHandleRawMessage(dynamic message) => _onMessage(message);

  /// Test harness: attach an in-memory duplex transport without a real socket.
  @visibleForTesting
  void debugAttachTransport({
    required Stream<dynamic> inbound,
    required StreamSink<dynamic> outbound,
  }) {
    _outboundSink = outbound;
    _connectionState = WebSocketConnectionState.connected;
    _subscription = inbound.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposing = true;
    _failAllPending(CommandDisconnectedException('', 'dispose'));
    final sessionId = _currentSessionId;
    _sessionPrepared = false;
    _sessionActive = false;
    _currentSessionId = null;
    if (_outboundSink != null &&
        _connectionState == WebSocketConnectionState.connected) {
      try {
        if (sessionId != null) {
          _outboundSink!.add(
            jsonEncode(
              buildStopPayload(sessionId: sessionId, requestId: _nextId('req')),
            ),
          );
        } else {
          // Legacy best-effort stop if identity was already cleared.
          _outboundSink!.add(jsonEncode({'action': 'stop'}));
        }
      } catch (_) {
        // Ignore: socket may already be closing.
      }
    }
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _outboundSink = null;
    _connectionState = WebSocketConnectionState.disconnected;
    if (!_feedbackController.isClosed) {
      _feedbackController.close();
    }
    if (!_protocolErrorController.isClosed) {
      _protocolErrorController.close();
    }
    super.dispose();
  }
}

class _PendingCommand {
  _PendingCommand({
    required this.action,
    required this.sessionId,
    required this.completer,
    required this.timer,
  });

  final String action;
  final String sessionId;
  final Completer<CommandAck> completer;
  final Timer timer;
}

class _QueuedStopRequest {
  _QueuedStopRequest({required this.sessionId, required this.completer});

  final String sessionId;
  final Completer<CommandAck> completer;
}
