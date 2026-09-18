import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/gamification_rules.dart';
import '../core/progression/matrix_test_access.dart';
import '../core/progression/progression_catalog.dart';
import '../data/models/leaderboard_entry.dart';
import '../data/repositories/leaderboard_repository.dart';
import 'trainee_progression_snapshot_store.dart';

/// Already-resolved trainee XP/level for personal progression surfaces.
///
/// Does not evaluate access policy itself. Router and UI call
/// [evaluatePersonal] with these values.
class TraineeProgressionService extends ChangeNotifier {
  TraineeProgressionService({
    LeaderboardRepository? leaderboardRepository,
    TraineeProgressionSnapshotStore? progressionSnapshotStore,
    MatrixTestAccessPolicy matrixTestAccessPolicy =
        const MatrixTestAccessPolicy(),
  }) : _leaderboardRepository = leaderboardRepository,
       _progressionSnapshotStore =
           progressionSnapshotStore ?? TraineeProgressionSnapshotStore(),
       _matrixTestAccessPolicy = matrixTestAccessPolicy;

  /// Test/harness constructor with an already-known XP total.
  TraineeProgressionService.ready({
    int totalXp = 0,
    MatrixTestAccessPolicy matrixTestAccessPolicy =
        const MatrixTestAccessPolicy(),
  }) : _leaderboardRepository = null,
       _progressionSnapshotStore = null,
       _matrixTestAccessPolicy = matrixTestAccessPolicy,
       _ready = true,
       _totalXp = totalXp;

  final LeaderboardRepository? _leaderboardRepository;
  final TraineeProgressionSnapshotStore? _progressionSnapshotStore;
  final MatrixTestAccessPolicy _matrixTestAccessPolicy;
  StreamSubscription<LeaderboardEntry?>? _sub;
  String? _userId;
  bool _ready = false;
  int _totalXp = 0;
  int _generation = 0;
  bool _disposed = false;

  bool get isReady => _ready;
  int get totalXp => _totalXp;
  int get level => GamificationRules.levelForXp(_totalXp);

  /// Personal-access level, which can be Level 20 only for the local debug
  /// matrix-test account. [level] and [totalXp] always remain the real values.
  int get effectivePersonalAccessLevel =>
      _matrixTestAccessPolicy.isEnabledFor(_userId)
      ? progressionMilestones.last.requiredLevel
      : level;

  /// Null while XP has not been resolved for the current trainee.
  int? get currentLevelOrNull => _ready ? effectivePersonalAccessLevel : null;

  Future<void> setUser(String? userId) async {
    final normalized = userId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_userId == next && _ready) return;
    final generation = ++_generation;
    final previousSubscription = _sub;
    _sub = null;
    _userId = next;
    _ready = false;
    _totalXp = 0;
    notifyListeners();
    await previousSubscription?.cancel();
    if (_disposed || generation != _generation) return;
    final uid = _userId;
    final repo = _leaderboardRepository;
    if (uid == null || repo == null) {
      _ready = true;
      notifyListeners();
      return;
    }
    final snapshotStore = _progressionSnapshotStore;
    if (snapshotStore != null) {
      TraineeProgressionSnapshot? snapshot;
      try {
        snapshot = await snapshotStore.load(uid);
      } catch (_) {
        // Cache availability never changes the fail-closed progression policy.
      }
      if (_disposed || generation != _generation || _userId != uid) return;
      if (snapshot != null) {
        _totalXp = snapshot.totalXp;
        _ready = true;
        notifyListeners();
      }
    }
    _sub = repo
        .watchPlayer(uid)
        .listen(
          (entry) => unawaited(
            _applyAuthoritativeEntry(
              entry: entry,
              uid: uid,
              generation: generation,
            ),
          ),
          onError: (_) {
            if (_disposed || generation != _generation || _userId != uid) {
              return;
            }
            // Retain an already loaded authoritative snapshot. Without one,
            // remain fail-closed so gated personal actions cannot unlock.
            if (!_ready) notifyListeners();
          },
        );
  }

  Future<void> _applyAuthoritativeEntry({
    required LeaderboardEntry? entry,
    required String uid,
    required int generation,
  }) async {
    if (_disposed || generation != _generation || _userId != uid) return;
    final totalXp = entry?.totalXp ?? 0;
    _totalXp = totalXp;
    _ready = true;
    notifyListeners();
    final store = _progressionSnapshotStore;
    if (store == null) return;
    try {
      await store.save(
        TraineeProgressionSnapshot(
          userId: uid,
          totalXp: totalXp,
          authoritativeSnapshotAt: DateTime.now().toUtc(),
        ),
      );
    } catch (_) {
      // Storage is an availability enhancement; a failed cache write must not
      // change the currently authoritative in-memory progression.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
