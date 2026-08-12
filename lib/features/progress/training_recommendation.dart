import '../../core/constants/movements.dart';
import '../../data/models/movement.dart';
import '../../data/models/rubric_assessment.dart';
import '../../data/models/session.dart';

/// Mastery tier derived from recent practice performance.
enum MovementMasteryStatus { notPracticed, learning, improving, mastered }

/// Direction of recent rubric movement when a prior window is available.
enum ScoreTrend { unknown, stable, improving, declining }

/// Aggregated mastery statistics for a single movement.
///
/// Every rubric aggregate is derived only from Assessment V2 sessions on the
/// 0..12 scale. Legacy percentage sessions still count towards
/// [completedSessions] but never contribute to a rubric average or best.
class MovementMastery {
  const MovementMastery({
    required this.movement,
    required this.completedSessions,
    required this.rubricSessionCount,
    required this.lifetimeAverageRubric,
    required this.bestRubricTotal,
    required this.recentAverageRubric,
    required this.previousRecentAverageRubric,
    required this.scoreTrend,
    required this.lastPracticedAt,
    required this.status,
    required this.catalogIndex,
  });

  final Movement movement;
  final int completedSessions;

  /// Sessions with an Assessment V2 rubric, i.e. the aggregate sample size.
  final int rubricSessionCount;

  final double? lifetimeAverageRubric;
  final int? bestRubricTotal;
  final double? recentAverageRubric;
  final double? previousRecentAverageRubric;
  final ScoreTrend scoreTrend;
  final DateTime? lastPracticedAt;
  final MovementMasteryStatus status;

  /// Original index in [movementCatalog] for deterministic tie-breaking.
  final int catalogIndex;

  /// Performance level of the recent rubric window, when rubric data exists.
  PerformanceLevel? get recentPerformanceLevel => recentAverageRubric == null
      ? null
      : PerformanceLevel.fromAverage(recentAverageRubric!);
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

/// Trend deadband on the 0..12 rubric scale (a quarter of one criterion point).
const _rubricTrendEpsilon = 0.25;

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
      rubricSessionCount: 0,
      lifetimeAverageRubric: null,
      bestRubricTotal: null,
      recentAverageRubric: null,
      previousRecentAverageRubric: null,
      scoreTrend: ScoreTrend.unknown,
      lastPracticedAt: null,
      status: MovementMasteryStatus.notPracticed,
      catalogIndex: catalogIndex,
    );
  }

  final sorted = List<Session>.from(movementSessions)
    ..sort(_compareSessionsChronologically);
  final completedSessions = sorted.length;
  final lastPracticedAt = _sessionTimestamp(sorted.last);

  // Only Assessment V2 sessions feed the rubric aggregates; legacy percentage
  // sessions are on an unrelated 0..100 scale.
  final rubricTotals = <int>[
    for (final session in sorted)
      if (session.isRubricAssessed) _clampRubricTotal(session.rubricTotal!),
  ];

  if (rubricTotals.isEmpty) {
    return MovementMastery(
      movement: movement,
      completedSessions: completedSessions,
      rubricSessionCount: 0,
      lifetimeAverageRubric: null,
      bestRubricTotal: null,
      recentAverageRubric: null,
      previousRecentAverageRubric: null,
      scoreTrend: ScoreTrend.unknown,
      lastPracticedAt: lastPracticedAt,
      status: MovementMasteryStatus.learning,
      catalogIndex: catalogIndex,
    );
  }

  final lifetimeAverage =
      rubricTotals.reduce((a, b) => a + b) / rubricTotals.length;
  final bestRubricTotal = rubricTotals.reduce((a, b) => a > b ? a : b);

  final recentTotals = rubricTotals.length <= _recentWindowSize
      ? rubricTotals
      : rubricTotals.sublist(rubricTotals.length - _recentWindowSize);
  final recentAverage =
      recentTotals.reduce((a, b) => a + b) / recentTotals.length;

  double? previousRecentAverage;
  ScoreTrend scoreTrend = ScoreTrend.unknown;
  if (rubricTotals.length > _recentWindowSize) {
    final previousStart = rubricTotals.length - (_recentWindowSize * 2);
    final safeStart = previousStart < 0 ? 0 : previousStart;
    final previousEnd = rubricTotals.length - _recentWindowSize;
    final previousTotals = rubricTotals.sublist(safeStart, previousEnd);
    if (previousTotals.isNotEmpty) {
      previousRecentAverage =
          previousTotals.reduce((a, b) => a + b) / previousTotals.length;
      final delta = recentAverage - previousRecentAverage;
      if (delta.abs() < _rubricTrendEpsilon) {
        scoreTrend = ScoreTrend.stable;
      } else if (delta > 0) {
        scoreTrend = ScoreTrend.improving;
      } else {
        scoreTrend = ScoreTrend.declining;
      }
    }
  }

  final status = _resolveStatus(
    rubricSessionCount: rubricTotals.length,
    recentAverageRubric: recentAverage,
  );

  return MovementMastery(
    movement: movement,
    completedSessions: completedSessions,
    rubricSessionCount: rubricTotals.length,
    lifetimeAverageRubric: lifetimeAverage,
    bestRubricTotal: bestRubricTotal,
    recentAverageRubric: recentAverage,
    previousRecentAverageRubric: previousRecentAverage,
    scoreTrend: scoreTrend,
    lastPracticedAt: lastPracticedAt,
    status: status,
    catalogIndex: catalogIndex,
  );
}

/// Mastery tiers follow the rubric performance levels, never a percentage.
MovementMasteryStatus _resolveStatus({
  required int rubricSessionCount,
  required double recentAverageRubric,
}) {
  if (rubricSessionCount == 0) {
    return MovementMasteryStatus.notPracticed;
  }
  final level = PerformanceLevel.fromAverage(recentAverageRubric);
  switch (level) {
    case PerformanceLevel.mastered:
    case PerformanceLevel.proficient:
      return rubricSessionCount >= 3
          ? MovementMasteryStatus.mastered
          : MovementMasteryStatus.improving;
    case PerformanceLevel.competent:
      return MovementMasteryStatus.improving;
    case PerformanceLevel.developing:
    case PerformanceLevel.beginning:
      return MovementMasteryStatus.learning;
  }
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
  final recentA = a.recentAverageRubric ?? double.infinity;
  final recentB = b.recentAverageRubric ?? double.infinity;
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
    return 'Your recent rubric totals are declining, so this movement needs reinforcement.';
  }

  final recent = recommended.recentAverageRubric;
  if (recent == null) {
    return 'This movement has no rubric assessment yet, so practice it next.';
  }
  return 'Your recent rubric average of ${recent.round()} / 12 is your lowest '
      'current mastery result.';
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
  return _resultForTieBreak(a).compareTo(_resultForTieBreak(b));
}

/// Stable tie-break value; only used to order same-timestamp sessions.
int _resultForTieBreak(Session session) =>
    session.rubricTotal ?? session.legacyScore ?? 0;

DateTime? _sessionTimestamp(Session session) {
  final raw = session.createdAt;
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

int _clampRubricTotal(int total) => total.clamp(0, 12);

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
