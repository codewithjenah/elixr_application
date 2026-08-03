import '../../core/constants/movements.dart';
import '../../data/models/movement.dart';
import '../../data/models/session.dart';

/// Mastery tier derived from recent practice performance.
enum MovementMasteryStatus { notPracticed, learning, improving, mastered }

/// Direction of recent score movement when a prior window is available.
enum ScoreTrend { unknown, stable, improving, declining }

/// Aggregated mastery statistics for a single movement.
class MovementMastery {
  const MovementMastery({
    required this.movement,
    required this.completedSessions,
    required this.lifetimeAverageScore,
    required this.bestScore,
    required this.recentAverageScore,
    required this.previousRecentAverageScore,
    required this.scoreTrend,
    required this.lastPracticedAt,
    required this.status,
    required this.catalogIndex,
  });

  final Movement movement;
  final int completedSessions;
  final double? lifetimeAverageScore;
  final int? bestScore;
  final double? recentAverageScore;
  final double? previousRecentAverageScore;
  final ScoreTrend scoreTrend;
  final DateTime? lastPracticedAt;
  final MovementMasteryStatus status;

  /// Original index in [movementCatalog] for deterministic tie-breaking.
  final int catalogIndex;
}

/// Rule-based training recommendation with per-movement mastery data.
class TrainingRecommendation {
  const TrainingRecommendation({
    required this.recommended,
    required this.reason,
    required this.masteries,
  });

  final MovementMastery recommended;
  final String reason;

  /// Mastery rows for every enabled movement, grouped-ready by difficulty.
  final List<MovementMastery> masteries;
}

const _difficultyOrder = <String, int>{'Easy': 0, 'Medium': 1, 'Hard': 2};

const _recentWindowSize = 5;
const _scoreTrendEpsilon = 1.0;

/// Builds mastery statistics and a single next-practice recommendation.
///
/// Pure function: no I/O, no clock access, deterministic for the same inputs.
TrainingRecommendation buildTrainingRecommendation({
  required List<Session> sessions,
  required List<Movement> movements,
}) {
  final enabledMovements = <({Movement movement, int catalogIndex})>[];
  for (var i = 0; i < movements.length; i++) {
    final movement = movements[i];
    if (movement.enabled) {
      enabledMovements.add((movement: movement, catalogIndex: i));
    }
  }

  final sessionsByMovement = <String, List<Session>>{};
  for (final session in sessions) {
    (sessionsByMovement[session.movementName] ??= <Session>[]).add(session);
  }

  final masteries = <MovementMastery>[
    for (final entry in enabledMovements)
      _buildMovementMastery(
        movement: entry.movement,
        catalogIndex: entry.catalogIndex,
        movementSessions: sessionsByMovement[entry.movement.name] ?? const [],
      ),
  ];

  final recommended = _selectRecommendation(masteries, sessions.isEmpty);
  final reason = _buildReason(recommended, masteries, sessions.isEmpty);

  return TrainingRecommendation(
    recommended: recommended,
    reason: reason,
    masteries: masteries,
  );
}

MovementMastery _buildMovementMastery({
  required Movement movement,
  required int catalogIndex,
  required List<Session> movementSessions,
}) {
  if (movementSessions.isEmpty) {
    return MovementMastery(
      movement: movement,
      completedSessions: 0,
      lifetimeAverageScore: null,
      bestScore: null,
      recentAverageScore: null,
      previousRecentAverageScore: null,
      scoreTrend: ScoreTrend.unknown,
      lastPracticedAt: null,
      status: MovementMasteryStatus.notPracticed,
      catalogIndex: catalogIndex,
    );
  }

  final sorted = List<Session>.from(movementSessions)
    ..sort(_compareSessionsChronologically);

  final clampedScores = sorted.map((s) => _clampScore(s.score)).toList();
  final completedSessions = sorted.length;
  final lifetimeAverage =
      clampedScores.reduce((a, b) => a + b) / completedSessions;
  final bestScore = clampedScores.reduce((a, b) => a > b ? a : b);

  final recentScores = clampedScores.length <= _recentWindowSize
      ? clampedScores
      : clampedScores.sublist(clampedScores.length - _recentWindowSize);
  final recentAverage =
      recentScores.reduce((a, b) => a + b) / recentScores.length;

  double? previousRecentAverage;
  ScoreTrend scoreTrend = ScoreTrend.unknown;
  if (sorted.length > _recentWindowSize) {
    final previousStart = sorted.length - (_recentWindowSize * 2);
    final safeStart = previousStart < 0 ? 0 : previousStart;
    final previousEnd = sorted.length - _recentWindowSize;
    final previousScores = clampedScores.sublist(safeStart, previousEnd);
    if (previousScores.isNotEmpty) {
      previousRecentAverage =
          previousScores.reduce((a, b) => a + b) / previousScores.length;
      final delta = recentAverage - previousRecentAverage;
      if (delta.abs() < _scoreTrendEpsilon) {
        scoreTrend = ScoreTrend.stable;
      } else if (delta > 0) {
        scoreTrend = ScoreTrend.improving;
      } else {
        scoreTrend = ScoreTrend.declining;
      }
    }
  }

  final lastPracticedAt = _sessionTimestamp(sorted.last);

  final status = _resolveStatus(
    completedSessions: completedSessions,
    recentAverage: recentAverage,
  );

  return MovementMastery(
    movement: movement,
    completedSessions: completedSessions,
    lifetimeAverageScore: lifetimeAverage,
    bestScore: bestScore,
    recentAverageScore: recentAverage,
    previousRecentAverageScore: previousRecentAverage,
    scoreTrend: scoreTrend,
    lastPracticedAt: lastPracticedAt,
    status: status,
    catalogIndex: catalogIndex,
  );
}

MovementMasteryStatus _resolveStatus({
  required int completedSessions,
  required double recentAverage,
}) {
  if (completedSessions == 0) {
    return MovementMasteryStatus.notPracticed;
  }
  if (recentAverage >= 85 && completedSessions >= 3) {
    return MovementMasteryStatus.mastered;
  }
  if (recentAverage >= 70) {
    return MovementMasteryStatus.improving;
  }
  return MovementMasteryStatus.learning;
}

MovementMastery _selectRecommendation(
  List<MovementMastery> masteries,
  bool hasNoSessions,
) {
  assert(masteries.isNotEmpty, 'At least one enabled movement is required.');

  if (hasNoSessions) {
    return _firstEnabledEasy(masteries);
  }

  final unpracticed =
      masteries
          .where((m) => m.status == MovementMasteryStatus.notPracticed)
          .toList()
        ..sort(_compareMasteryPriority);
  if (unpracticed.isNotEmpty) {
    return unpracticed.first;
  }

  final nonMastered = masteries
      .where((m) => m.status != MovementMasteryStatus.mastered)
      .toList();
  if (nonMastered.isNotEmpty) {
    nonMastered.sort(_compareWeakestNonMastered);
    return nonMastered.first;
  }

  final mastered =
      masteries
          .where((m) => m.status == MovementMasteryStatus.mastered)
          .toList()
        ..sort(_compareMaintenanceCandidate);
  return mastered.first;
}

MovementMastery _firstEnabledEasy(List<MovementMastery> masteries) {
  final easy = masteries.where((m) => m.movement.difficulty == 'Easy').toList()
    ..sort((a, b) => a.catalogIndex.compareTo(b.catalogIndex));
  return easy.first;
}

int _compareMasteryPriority(MovementMastery a, MovementMastery b) {
  final difficulty = _difficultyOrder[a.movement.difficulty]!.compareTo(
    _difficultyOrder[b.movement.difficulty]!,
  );
  if (difficulty != 0) return difficulty;
  return a.catalogIndex.compareTo(b.catalogIndex);
}

int _compareWeakestNonMastered(MovementMastery a, MovementMastery b) {
  final recentA = a.recentAverageScore ?? double.infinity;
  final recentB = b.recentAverageScore ?? double.infinity;
  final recentCompare = recentA.compareTo(recentB);
  if (recentCompare != 0) return recentCompare;

  final practicedCompare = _compareLastPracticedOldestFirst(
    a.lastPracticedAt,
    b.lastPracticedAt,
  );
  if (practicedCompare != 0) return practicedCompare;

  final difficulty = _difficultyOrder[a.movement.difficulty]!.compareTo(
    _difficultyOrder[b.movement.difficulty]!,
  );
  if (difficulty != 0) return difficulty;

  return a.catalogIndex.compareTo(b.catalogIndex);
}

int _compareMaintenanceCandidate(MovementMastery a, MovementMastery b) {
  final practicedCompare = _compareLastPracticedOldestFirst(
    a.lastPracticedAt,
    b.lastPracticedAt,
  );
  if (practicedCompare != 0) return practicedCompare;

  final difficulty = _difficultyOrder[a.movement.difficulty]!.compareTo(
    _difficultyOrder[b.movement.difficulty]!,
  );
  if (difficulty != 0) return difficulty;

  return a.catalogIndex.compareTo(b.catalogIndex);
}

/// Oldest practice date first; null dates sort before dated entries.
int _compareLastPracticedOldestFirst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  return a.compareTo(b);
}

String _buildReason(
  MovementMastery recommended,
  List<MovementMastery> masteries,
  bool hasNoSessions,
) {
  if (hasNoSessions ||
      recommended.status == MovementMasteryStatus.notPracticed) {
    return 'You have not practiced this movement yet.';
  }

  final allMastered = masteries.every(
    (m) => m.status == MovementMasteryStatus.mastered,
  );
  if (allMastered) {
    return 'All movements are mastered. Revisit this movement to maintain your skill.';
  }

  if (recommended.scoreTrend == ScoreTrend.declining) {
    return 'Your recent scores are declining, so this movement needs reinforcement.';
  }

  final recent = recommended.recentAverageScore?.round() ?? 0;
  return 'Your recent average of $recent is your lowest current mastery score.';
}

int _compareSessionsChronologically(Session a, Session b) {
  final aTime = _sessionTimestamp(a);
  final bTime = _sessionTimestamp(b);
  if (aTime == null && bTime == null) {
    return a.movementName.compareTo(b.movementName);
  }
  if (aTime == null) return -1;
  if (bTime == null) return 1;
  final compare = aTime.compareTo(bTime);
  if (compare != 0) return compare;
  return a.score.compareTo(b.score);
}

DateTime? _sessionTimestamp(Session session) {
  final raw = session.createdAt;
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

int _clampScore(int score) => score.clamp(0, 100);

/// Human-readable label for a mastery status.
String masteryStatusLabel(MovementMasteryStatus status) {
  switch (status) {
    case MovementMasteryStatus.notPracticed:
      return 'Not practiced';
    case MovementMasteryStatus.learning:
      return 'Learning';
    case MovementMasteryStatus.improving:
      return 'Improving';
    case MovementMasteryStatus.mastered:
      return 'Mastered';
  }
}

/// Enabled movements from [movementCatalog] in catalog order.
List<Movement> enabledMovementsFromCatalog() {
  return [
    for (var i = 0; i < movementCatalog.length; i++)
      if (movementCatalog[i].enabled) movementCatalog[i],
  ];
}
