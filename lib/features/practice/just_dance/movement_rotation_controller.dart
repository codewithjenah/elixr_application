import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/movement.dart';

/// Drives a "Just Dance"-style rotation through a user-built movement
/// setlist as a purely visual prompt during a live camera session.
///
/// This never scores, gates, or locks anything — it only tracks which
/// movement to display and how far through the current interval the
/// rotation is. Mirrors the lightweight `Timer`-driven style of
/// `PracticeRunController`.
class MovementRotationController extends ChangeNotifier {
  MovementRotationController({
    required List<Movement> movements,
    required int intervalSeconds,
    Duration tick = const Duration(milliseconds: 200),
  }) : _movements = List.unmodifiable(movements),
       _intervalSeconds = intervalSeconds,
       _tick = tick;

  List<Movement> _movements;
  int _intervalSeconds;
  final Duration _tick;

  int _index = 0;
  int _elapsedMs = 0;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  Movement? get currentMovement =>
      _movements.isEmpty ? null : _movements[_index];

  /// Preview of the movement that will show after the next auto-advance.
  Movement? get nextMovement => _movements.length < 2
      ? null
      : _movements[(_index + 1) % _movements.length];

  /// 0.0 (just started) to 1.0 (about to auto-advance).
  double get progress {
    final totalMs = _intervalSeconds * 1000;
    if (totalMs <= 0) return 0;
    return (_elapsedMs / totalMs).clamp(0.0, 1.0);
  }

  bool get isRunning => _running;

  /// Replaces the setlist and/or interval in place, e.g. after the user
  /// edits their setlist mid-session. Restarts from the first movement so
  /// the displayed index always stays valid for the new list.
  void updateSetlist(List<Movement> movements, {int? intervalSeconds}) {
    if (_disposed) return;
    final wasRunning = _running;
    _movements = List.unmodifiable(movements);
    if (intervalSeconds != null) _intervalSeconds = intervalSeconds;
    _index = 0;
    _elapsedMs = 0;
    if (_movements.isEmpty) {
      _stopTimer();
      _running = false;
    } else if (wasRunning) {
      _startTimer();
    }
    notifyListeners();
  }

  void start() {
    if (_disposed || _movements.isEmpty) return;
    _index = 0;
    _elapsedMs = 0;
    _running = true;
    _startTimer();
    notifyListeners();
  }

  void pause() {
    if (_disposed || !_running) return;
    _running = false;
    _stopTimer();
    notifyListeners();
  }

  void resume() {
    if (_disposed || _running || _movements.isEmpty) return;
    _running = true;
    _startTimer();
    notifyListeners();
  }

  void skipNext() {
    if (_disposed || _movements.length < 2) return;
    _advance();
  }

  void skipPrevious() {
    if (_disposed || _movements.length < 2) return;
    _elapsedMs = 0;
    _index = (_index - 1 + _movements.length) % _movements.length;
    notifyListeners();
  }

  void stop() {
    if (_disposed) return;
    _running = false;
    _stopTimer();
    _index = 0;
    _elapsedMs = 0;
    notifyListeners();
  }

  void _advance() {
    _elapsedMs = 0;
    _index = (_index + 1) % _movements.length;
    notifyListeners();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(_tick, (_) {
      if (_disposed || !_running) return;
      _elapsedMs += _tick.inMilliseconds;
      final totalMs = _intervalSeconds * 1000;
      if (totalMs > 0 && _elapsedMs >= totalMs) {
        _advance();
      } else {
        notifyListeners();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  bool get hasTimer => _timer != null;

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
