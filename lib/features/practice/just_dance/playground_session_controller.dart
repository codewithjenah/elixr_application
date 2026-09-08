import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/movement.dart';

/// CV-assessed lifecycle for a user-selected Playground routine.
///
/// The controller deliberately does not perform WebSocket I/O. The screen owns
/// prepare/activate/stop commands and supplies the matching [generation] when
/// it reports their results. This makes late callbacks from an earlier
/// movement harmless.
enum PlaygroundSessionPhase {
  idle,
  preparingMovement,
  getReady,
  assessing,
  success,
  missed,
  transitioning,
  completed,
}

enum PlaygroundMovementStatus { success, missed }

@immutable
class PlaygroundMovementOutcome {
  const PlaygroundMovementOutcome({
    required this.movement,
    required this.status,
  });

  final Movement movement;
  final PlaygroundMovementStatus status;
}

class PlaygroundSessionController extends ChangeNotifier {
  PlaygroundSessionController({
    required List<Movement> movements,
    required this.assessmentDuration,
    this.getReadyDuration = const Duration(seconds: 3),
    this.tick = const Duration(milliseconds: 200),
  }) : _movements = List.unmodifiable(movements);

  List<Movement> _movements;
  final Duration assessmentDuration;
  final Duration getReadyDuration;
  final Duration tick;

  PlaygroundSessionPhase _phase = PlaygroundSessionPhase.idle;
  final List<PlaygroundMovementOutcome> _outcomes = [];
  Timer? _timer;
  int _index = 0;
  int _generation = 0;
  int _elapsedMs = 0;
  bool _activationDue = false;
  bool _paused = false;
  bool _disposed = false;

  PlaygroundSessionPhase get phase => _phase;
  Movement? get currentMovement =>
      _movements.isEmpty || _index >= _movements.length
      ? null
      : _movements[_index];
  Movement? get nextMovement =>
      _index + 1 < _movements.length ? _movements[_index + 1] : null;
  int get generation => _generation;
  bool get isPaused => _paused;
  bool get activationDue => _activationDue;
  bool get isComplete => _phase == PlaygroundSessionPhase.completed;
  bool get isAssessing => _phase == PlaygroundSessionPhase.assessing;
  List<PlaygroundMovementOutcome> get outcomes => List.unmodifiable(_outcomes);

  double get progress {
    final duration = _phase == PlaygroundSessionPhase.getReady
        ? getReadyDuration
        : assessmentDuration;
    if (duration.inMilliseconds <= 0) return 0;
    return (_elapsedMs / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Starts a new routine and returns the generation to use for prepare I/O.
  int? start() {
    if (_disposed) return null;
    _cancelTimer();
    _outcomes.clear();
    _index = 0;
    _elapsedMs = 0;
    _activationDue = false;
    _paused = false;
    if (_movements.isEmpty) {
      _phase = PlaygroundSessionPhase.completed;
      _generation++;
      notifyListeners();
      return null;
    }
    return _enterPreparing();
  }

  /// Replaces the selected setlist only when no routine is in progress.
  void updateSetlist(List<Movement> movements) {
    if (_disposed ||
        (_phase != PlaygroundSessionPhase.idle &&
            _phase != PlaygroundSessionPhase.completed)) {
      return;
    }
    _movements = List.unmodifiable(movements);
    _index = 0;
    notifyListeners();
  }

  bool markMovementPrepared(int generation) {
    if (!_matches(generation) ||
        _phase != PlaygroundSessionPhase.preparingMovement) {
      return false;
    }
    _phase = PlaygroundSessionPhase.getReady;
    _elapsedMs = 0;
    _activationDue = false;
    _startTimer();
    notifyListeners();
    return true;
  }

  bool markAssessing(int generation) {
    if (!_matches(generation) ||
        _phase != PlaygroundSessionPhase.getReady ||
        !_activationDue ||
        _paused) {
      return false;
    }
    _phase = PlaygroundSessionPhase.assessing;
    _elapsedMs = 0;
    _activationDue = false;
    _startTimer();
    notifyListeners();
    return true;
  }

  /// Completes only the active generation after official backend confirmation.
  bool markSuccessful(int generation) =>
      _finish(generation, PlaygroundMovementStatus.success);

  /// A timeout or manual Next records a miss; it never records a success.
  bool markMissed(int generation) =>
      _finish(generation, PlaygroundMovementStatus.missed);

  bool requestNext() {
    if (_disposed || _paused || currentMovement == null) return false;
    return _finish(_generation, PlaygroundMovementStatus.missed);
  }

  /// Moves a completed/missed movement into the next safe prepare generation.
  /// Returns null once the final movement has completed.
  int? beginNextMovement() {
    if (_disposed ||
        (_phase != PlaygroundSessionPhase.success &&
            _phase != PlaygroundSessionPhase.missed)) {
      return null;
    }
    _phase = PlaygroundSessionPhase.transitioning;
    notifyListeners();
    if (_index + 1 >= _movements.length) {
      _phase = PlaygroundSessionPhase.completed;
      _generation++;
      notifyListeners();
      return null;
    }
    _index++;
    return _enterPreparing();
  }

  void pause() {
    if (_disposed ||
        _paused ||
        isComplete ||
        _phase == PlaygroundSessionPhase.idle) {
      return;
    }
    _paused = true;
    _cancelTimer();
    notifyListeners();
  }

  void resume() {
    if (_disposed ||
        !_paused ||
        isComplete ||
        _phase == PlaygroundSessionPhase.idle) {
      return;
    }
    _paused = false;
    if ((_phase == PlaygroundSessionPhase.getReady && !_activationDue) ||
        _phase == PlaygroundSessionPhase.assessing) {
      _startTimer();
    }
    notifyListeners();
  }

  void cancelToIdle() {
    if (_disposed) return;
    _cancelTimer();
    _generation++;
    _phase = PlaygroundSessionPhase.idle;
    _elapsedMs = 0;
    _activationDue = false;
    _paused = false;
    notifyListeners();
  }

  bool _finish(int generation, PlaygroundMovementStatus status) {
    if (!_matches(generation) ||
        _phase != PlaygroundSessionPhase.assessing ||
        _paused) {
      return false;
    }
    final movement = currentMovement;
    if (movement == null) return false;
    _cancelTimer();
    _elapsedMs = assessmentDuration.inMilliseconds;
    _outcomes.add(
      PlaygroundMovementOutcome(movement: movement, status: status),
    );
    _phase = status == PlaygroundMovementStatus.success
        ? PlaygroundSessionPhase.success
        : PlaygroundSessionPhase.missed;
    notifyListeners();
    return true;
  }

  int _enterPreparing() {
    _cancelTimer();
    _generation++;
    _phase = PlaygroundSessionPhase.preparingMovement;
    _elapsedMs = 0;
    _activationDue = false;
    notifyListeners();
    return _generation;
  }

  bool _matches(int generation) => !_disposed && generation == _generation;

  void _startTimer() {
    _cancelTimer();
    if (_paused) return;
    _timer = Timer.periodic(tick, (_) {
      if (_disposed || _paused) return;
      final duration = _phase == PlaygroundSessionPhase.getReady
          ? getReadyDuration
          : _phase == PlaygroundSessionPhase.assessing
          ? assessmentDuration
          : null;
      if (duration == null) return;
      _elapsedMs += tick.inMilliseconds;
      if (_elapsedMs < duration.inMilliseconds) {
        notifyListeners();
      } else if (_phase == PlaygroundSessionPhase.getReady) {
        _elapsedMs = duration.inMilliseconds;
        _activationDue = true;
        _cancelTimer();
        notifyListeners();
      } else {
        markMissed(_generation);
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  bool get hasTimer => _timer != null;

  @override
  void dispose() {
    _disposed = true;
    _cancelTimer();
    super.dispose();
  }
}
