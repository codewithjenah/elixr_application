import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/constants/movements.dart';
import '../../../data/models/recognition_event.dart';
import '../../../data/models/training_prop.dart';
import 'freestyle_models.dart';

/// Build the single-prop run pool from the existing personal-ready variants.
List<EndlessTarget> endlessPoolFromReady(
  List<({String movement, TrainingProp prop})> ready,
  TrainingProp selectedProp,
) => [
  for (final variant in ready)
    for (final movement in movementCatalog)
      if (movement.name == variant.movement &&
          variant.prop == selectedProp &&
          movement.requiredPropCount == 1 &&
          movement.supportedProps.contains(selectedProp))
        EndlessTarget(
          movement: movement.name,
          prop: selectedProp,
          difficulty: movement.difficulty,
        ),
  if (ready.any((variant) => variant.prop == selectedProp))
    EndlessTarget(
      movement: 'Toss & Catch',
      prop: selectedProp,
      difficulty: 'Medium',
    ),
];

/// I/O-free Endless session. The screen owns WebSocket commands
/// and reports results with the matching [generation].
class FreestyleSessionController extends ChangeNotifier {
  FreestyleSessionController({int Function(int)? randomIndex})
    : _randomIndex = randomIndex ?? Random().nextInt;

  final int Function(int) _randomIndex;
  FreestyleSessionPhase _phase = FreestyleSessionPhase.idle;
  FreestyleSessionStats _stats = const FreestyleSessionStats();
  final Set<String> _seenEventIds = {};
  final Set<String> _uniqueMovements = {};
  int _generation = 0;
  bool _disposed = false;
  String? _liveLabel;
  RecognitionQuality? _liveQuality;
  RecognitionState _liveState = RecognitionState.searching;
  TrainingProp? _detectedProp;
  String? _errorMessage;
  List<EndlessTarget> _pool = const [];
  final List<EndlessTarget> _queue = [];
  Timer? _targetTimer;
  Timer? _advanceTimer;
  int _targetGeneration = 0;
  int _remainingSeconds = 0;
  bool _targetReady = false;
  bool _pendingAdvance = false;
  RecognitionQuality? _successQuality;

  FreestyleSessionPhase get phase => _phase;
  int get generation => _generation;
  FreestyleSessionStats get stats => _stats;
  String? get liveLabel => _liveLabel;
  RecognitionQuality? get liveQuality => _liveQuality;
  RecognitionState get liveState => _liveState;
  TrainingProp? get detectedProp => _detectedProp;
  String? get errorMessage => _errorMessage;
  EndlessTarget? get currentTarget => _queue.isEmpty ? null : _queue.first;
  List<EndlessTarget> get upcomingTargets => _queue.skip(1).take(2).toList();
  int get targetGeneration => _targetGeneration;
  int get remainingSeconds => _remainingSeconds;
  bool get targetReady => _targetReady;
  RecognitionQuality? get successQuality => _successQuality;
  bool get isPaused => _phase == FreestyleSessionPhase.paused;
  bool get isComplete => _phase == FreestyleSessionPhase.completed;
  bool get isActive =>
      _phase == FreestyleSessionPhase.active ||
      _phase == FreestyleSessionPhase.paused;
  bool get hasWorkToLose => switch (_phase) {
    FreestyleSessionPhase.idle ||
    FreestyleSessionPhase.completed ||
    FreestyleSessionPhase.error => false,
    _ => true,
  };

  int? start({List<EndlessTarget>? pool}) {
    if (_disposed) return null;
    _cancelTimers();
    _pool = List.unmodifiable(pool ?? const []);
    _queue.clear();
    if (_pool.isNotEmpty) {
      _fillQueue();
      _targetGeneration = 1;
      _remainingSeconds = currentTarget!.seconds;
    }
    _targetReady = false;
    _pendingAdvance = false;
    _successQuality = null;
    _seenEventIds.clear();
    _uniqueMovements.clear();
    _stats = FreestyleSessionStats(
      props: _pool.isEmpty ? const {} : {_pool.first.prop},
    );
    _liveLabel = null;
    _liveQuality = null;
    _liveState = RecognitionState.searching;
    _detectedProp = null;
    _errorMessage = null;
    _generation++;
    _phase = FreestyleSessionPhase.preparing;
    notifyListeners();
    return _generation;
  }

  bool markPrepared(int generation) {
    if (!_matches(generation) || _phase != FreestyleSessionPhase.preparing) {
      return false;
    }
    _phase = FreestyleSessionPhase.ready;
    notifyListeners();
    return true;
  }

  bool markActive(int generation) {
    if (!_matches(generation) || _phase != FreestyleSessionPhase.ready) {
      return false;
    }
    _phase = FreestyleSessionPhase.active;
    notifyListeners();
    return true;
  }

  bool pause(int generation) {
    if (!_matches(generation) || _phase != FreestyleSessionPhase.active) {
      return false;
    }
    _phase = FreestyleSessionPhase.paused;
    _targetTimer?.cancel();
    _advanceTimer?.cancel();
    _liveState = RecognitionState.paused;
    notifyListeners();
    return true;
  }

  bool resume(int generation) {
    if (!_matches(generation) || _phase != FreestyleSessionPhase.paused) {
      return false;
    }
    _phase = FreestyleSessionPhase.active;
    if (_pendingAdvance) {
      _advanceTarget();
    } else if (_targetReady) {
      _startTargetTimer();
    }
    if (_liveState == RecognitionState.paused) {
      _liveState = _liveLabel == null
          ? RecognitionState.searching
          : RecognitionState.confirmed;
    }
    notifyListeners();
    return true;
  }

  bool applyLiveState({
    required int generation,
    RecognitionState? state,
    String? recognizedDisplay,
    TrainingProp? detectedProp,
  }) {
    if (!_matches(generation)) return false;
    if (_phase == FreestyleSessionPhase.paused) return false;
    if (_phase != FreestyleSessionPhase.active &&
        _phase != FreestyleSessionPhase.ready) {
      return false;
    }
    var changed = false;
    if (state != null &&
        state != RecognitionState.unknown &&
        state != _liveState) {
      _liveState = state;
      changed = true;
    }
    if (state == RecognitionState.searching ||
        state == RecognitionState.candidate) {
      if (_liveLabel != null || _liveQuality != null) {
        _liveLabel = null;
        _liveQuality = null;
        changed = true;
      }
    } else if (recognizedDisplay != null &&
        recognizedDisplay.isNotEmpty &&
        recognizedDisplay != _liveLabel) {
      _liveLabel = recognizedDisplay;
      changed = true;
    }
    if (detectedProp != _detectedProp) {
      _detectedProp = detectedProp;
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  bool applyEvent(int generation, RecognitionEvent event) {
    if (!_matches(generation)) return false;
    if (_phase == FreestyleSessionPhase.paused) return false;
    if (_phase != FreestyleSessionPhase.active &&
        _phase != FreestyleSessionPhase.ready) {
      return false;
    }
    if (event.eventId.isEmpty || !_seenEventIds.add(event.eventId)) {
      return false;
    }
    if (_pool.isNotEmpty) {
      final target = currentTarget;
      if (!_targetReady ||
          target == null ||
          event.targetGeneration != _targetGeneration ||
          event.propType != target.prop ||
          !(target.isTossCatch
              ? event.kind == RecognitionKind.flip
              : event.kind == RecognitionKind.movement &&
                    event.movement == target.movement)) {
        return false;
      }
      _targetReady = false;
      _pendingAdvance = true;
      _targetTimer?.cancel();
      _successQuality = event.quality;
      _advanceTimer?.cancel();
      final completedGeneration = _targetGeneration;
      _advanceTimer = Timer(const Duration(milliseconds: 450), () {
        if (_matches(generation) &&
            _targetGeneration == completedGeneration &&
            _phase == FreestyleSessionPhase.active) {
          _advanceTarget();
        }
      });
    }
    if (event.kind == RecognitionKind.unknown) return false;

    var combo = _stats.combo;
    var best = _stats.bestCombo;
    if (event.breaksCombo) {
      combo = 0;
    } else if (event.countsForCombo) {
      combo += 1;
      if (combo > best) best = combo;
    }

    var movements = _stats.movementsRecognized;
    var unique = _stats.uniqueUnlockedMovements;
    var flips = _stats.flips;
    var advanced = _stats.advancedTechniques;
    var perfect = _stats.perfect;
    var great = _stats.great;
    var nice = _stats.nice;
    final props = Set<TrainingProp>.of(_stats.props);
    final feed = List<FreestyleFeedEntry>.of(_stats.feed);

    if (event.kind == RecognitionKind.movement) {
      movements += 1;
      final name = event.movement;
      if (name != null && _uniqueMovements.add(name)) {
        unique = _uniqueMovements.length;
      }
    } else if (event.kind == RecognitionKind.flip) {
      flips += 1;
      if (_pool.isNotEmpty && _uniqueMovements.add('Toss & Catch')) {
        unique = _uniqueMovements.length;
      }
    } else if (event.kind == RecognitionKind.advancedTechnique) {
      advanced += 1;
    }

    if (event.countsForCombo) {
      switch (event.quality) {
        case RecognitionQuality.perfect:
          perfect += 1;
        case RecognitionQuality.great:
          great += 1;
        case RecognitionQuality.nice:
          nice += 1;
        case null:
          break;
      }
    }

    if (event.propType != null &&
        event.propType != TrainingProp.bottleAndShaker) {
      props.add(event.propType!);
    } else if (event.propType == TrainingProp.bottleAndShaker) {
      props.add(TrainingProp.bottle);
      props.add(TrainingProp.shaker);
    }

    if (event.kind != RecognitionKind.failedAction &&
        event.displayLabel.isNotEmpty) {
      feed.insert(
        0,
        FreestyleFeedEntry(
          displayLabel: event.displayLabel,
          quality: event.quality,
          kind: event.kind,
        ),
      );
      if (feed.length > 8) {
        feed.removeLast();
      }
      _liveLabel = event.displayLabel;
      _liveQuality = event.quality;
      _liveState = RecognitionState.confirmed;
    }

    _stats = FreestyleSessionStats(
      movementsRecognized: movements,
      uniqueUnlockedMovements: unique,
      flips: flips,
      advancedTechniques: advanced,
      perfect: perfect,
      great: great,
      nice: nice,
      bestCombo: best,
      combo: combo,
      missed: _stats.missed,
      runScore:
          _stats.runScore +
          switch (event.quality) {
            RecognitionQuality.perfect => 3,
            RecognitionQuality.great => 2,
            RecognitionQuality.nice => 1,
            null => 0,
          },
      props: props,
      feed: List.unmodifiable(feed),
    );
    notifyListeners();
    return true;
  }

  bool beginEnding(int generation) {
    if (!_matches(generation) || !isActive) return false;
    _cancelTimers();
    _phase = FreestyleSessionPhase.ending;
    notifyListeners();
    return true;
  }

  bool markCompleted(int generation) {
    if (!_matches(generation) ||
        (_phase != FreestyleSessionPhase.ending &&
            _phase != FreestyleSessionPhase.active &&
            _phase != FreestyleSessionPhase.paused)) {
      return false;
    }
    _phase = FreestyleSessionPhase.completed;
    notifyListeners();
    return true;
  }

  bool fail(int generation, String message) {
    if (!_matches(generation)) return false;
    if (_phase == FreestyleSessionPhase.idle ||
        _phase == FreestyleSessionPhase.completed) {
      return false;
    }
    _errorMessage = message;
    _phase = FreestyleSessionPhase.error;
    notifyListeners();
    return true;
  }

  void cancelToIdle() {
    if (_disposed) return;
    _cancelTimers();
    _queue.clear();
    _pool = const [];
    _generation++;
    _phase = FreestyleSessionPhase.idle;
    _liveLabel = null;
    _liveQuality = null;
    _liveState = RecognitionState.searching;
    _detectedProp = null;
    notifyListeners();
  }

  bool _matches(int generation) => !_disposed && generation == _generation;

  bool confirmTarget(int generation, int targetGeneration) {
    if (!_matches(generation) ||
        targetGeneration != _targetGeneration ||
        currentTarget == null ||
        !isActive ||
        _targetReady) {
      return false;
    }
    _targetReady = true;
    _remainingSeconds = currentTarget!.seconds;
    if (!isPaused) _startTargetTimer();
    notifyListeners();
    return true;
  }

  void _startTargetTimer() {
    _targetTimer?.cancel();
    _targetTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed ||
          _phase != FreestyleSessionPhase.active ||
          !_targetReady) {
        return;
      }
      _remainingSeconds--;
      if (_remainingSeconds <= 0) {
        _targetReady = false;
        _targetTimer?.cancel();
        _stats = _stats.copyWith(missed: _stats.missed + 1, combo: 0);
        _advanceTarget();
      } else {
        notifyListeners();
      }
    });
  }

  void _fillQueue() {
    while (_queue.length < 3 && _pool.isNotEmpty) {
      final previous = _queue.isEmpty ? null : _queue.last;
      final beforePrevious = _queue.length < 2
          ? null
          : _queue[_queue.length - 2];
      var choices = _pool
          .where(
            (target) =>
                _pool.length == 1 || target.movement != previous?.movement,
          )
          .toList();
      if (choices.length > 1 && beforePrevious != null) {
        final varied = choices
            .where((target) => target.movement != beforePrevious.movement)
            .toList();
        if (varied.isNotEmpty) choices = varied;
      }
      if (choices.isEmpty) choices = _pool;
      _queue.add(choices[_randomIndex(choices.length)]);
    }
  }

  void _advanceTarget() {
    if (_queue.isEmpty) return;
    _queue.removeAt(0);
    _fillQueue();
    // Event IDs need only be retained for the active target. The wire target
    // generation rejects delayed events after this boundary.
    _seenEventIds.clear();
    _targetGeneration++;
    _targetReady = false;
    _pendingAdvance = false;
    _successQuality = null;
    _remainingSeconds = currentTarget?.seconds ?? 0;
    notifyListeners();
  }

  void _cancelTimers() {
    _targetTimer?.cancel();
    _advanceTimer?.cancel();
    _targetTimer = null;
    _advanceTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
