import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/gamification_rules.dart';
import '../data/models/leaderboard_entry.dart';
import '../data/repositories/leaderboard_repository.dart';

/// Already-resolved trainee XP/level for personal progression surfaces.
///
/// Does not evaluate access policy itself. Router and UI call
/// [evaluatePersonal] with these values.
class TraineeProgressionService extends ChangeNotifier {
  TraineeProgressionService({LeaderboardRepository? leaderboardRepository})
    : _leaderboardRepository = leaderboardRepository;

  /// Test/harness constructor with an already-known XP total.
  TraineeProgressionService.ready({int totalXp = 0})
    : _leaderboardRepository = null,
      _ready = true,
      _totalXp = totalXp;

  final LeaderboardRepository? _leaderboardRepository;
  StreamSubscription<LeaderboardEntry?>? _sub;
  String? _userId;
  bool _ready = false;
  int _totalXp = 0;
  int _generation = 0;
  bool _disposed = false;

  bool get isReady => _ready;
  int get totalXp => _totalXp;
  int get level => GamificationRules.levelForXp(_totalXp);

  /// Null while XP has not been resolved for the current trainee.
  int? get currentLevelOrNull => _ready ? level : null;

  Future<void> setUser(String? userId) async {
    final normalized = userId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_userId == next && _ready) return;
    final generation = ++_generation;
    await _sub?.cancel();
    if (_disposed || generation != _generation) return;
    _sub = null;
    _userId = next;
    _ready = false;
    _totalXp = 0;
    notifyListeners();
    final uid = _userId;
    final repo = _leaderboardRepository;
    if (uid == null || repo == null) {
      _ready = true;
      notifyListeners();
      return;
    }
    _sub = repo
        .watchPlayer(uid)
        .listen(
          (entry) {
            if (_disposed || generation != _generation || _userId != uid) {
              return;
            }
            _totalXp = entry?.totalXp ?? 0;
            _ready = true;
            notifyListeners();
          },
          onError: (_) {
            if (_disposed || generation != _generation || _userId != uid) {
              return;
            }
            // Fail closed: keep not-ready so gated personal actions do not unlock.
            _ready = false;
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
