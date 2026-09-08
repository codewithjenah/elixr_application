import 'package:flutter/foundation.dart';

import '../../../data/models/recognition_event.dart';
import '../../../data/models/training_prop.dart';
import 'freestyle_models.dart';

/// I/O-free Playground freestyle session. The screen owns WebSocket commands
/// and reports results with the matching [generation].
class FreestyleSessionController extends ChangeNotifier {
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

  FreestyleSessionPhase get phase => _phase;
  int get generation => _generation;
  FreestyleSessionStats get stats => _stats;
  String? get liveLabel => _liveLabel;
  RecognitionQuality? get liveQuality => _liveQuality;
  RecognitionState get liveState => _liveState;
  TrainingProp? get detectedProp => _detectedProp;
  String? get errorMessage => _errorMessage;
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

  int? start() {
    if (_disposed) return null;
    _seenEventIds.clear();
    _uniqueMovements.clear();
    _stats = const FreestyleSessionStats();
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
    _liveState = RecognitionState.paused;
    notifyListeners();
    return true;
  }

  bool resume(int generation) {
    if (!_matches(generation) || _phase != FreestyleSessionPhase.paused) {
      return false;
    }
    _phase = FreestyleSessionPhase.active;
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
    if (state != null && state != RecognitionState.unknown) {
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
    } else if (recognizedDisplay != null && recognizedDisplay.isNotEmpty) {
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
      props: props,
      feed: List.unmodifiable(feed),
    );
    notifyListeners();
    return true;
  }

  bool beginEnding(int generation) {
    if (!_matches(generation) || !isActive) return false;
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
    _generation++;
    _phase = FreestyleSessionPhase.idle;
    _liveLabel = null;
    _liveQuality = null;
    _liveState = RecognitionState.searching;
    _detectedProp = null;
    notifyListeners();
  }

  bool _matches(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
