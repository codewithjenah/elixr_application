import 'package:elixr_core/utils/comparable_rubric_progress.dart';

import '../database/firestore_helper.dart';
import '../models/session.dart';

class ProgressStats {
  const ProgressStats({
    required this.totalSessions,
    this.rubricSessionCount = 0,
    this.averageRubricTotal,
    this.bestRubricTotal,
    this.legacySessionCount = 0,
    this.averageLegacyScore,
    this.bestLegacyScore,
    this.mostPracticedMovement,
    required this.sessionsByMovement,
  });

  final int totalSessions;
  final int rubricSessionCount;
  final double? averageRubricTotal;
  final int? bestRubricTotal;
  final int legacySessionCount;
  final double? averageLegacyScore;
  final int? bestLegacyScore;
  final String? mostPracticedMovement;
  final Map<String, int> sessionsByMovement;

  /// Preferred overall average for UI: rubric when any V2 sessions exist.
  double? get preferredAverage =>
      rubricSessionCount > 0 ? averageRubricTotal : averageLegacyScore;

  int? get preferredBest =>
      rubricSessionCount > 0 ? bestRubricTotal : bestLegacyScore;

  bool get hasRubricData => rubricSessionCount > 0;
  bool get hasLegacyOnly => rubricSessionCount == 0 && legacySessionCount > 0;

  /// Dashboard/all-time aggregates from an already-loaded session list.
  ///
  /// Matches [ProgressRepository.getStatsForUser] client-side math on the same
  /// snapshot: V1/V2 stay partitioned, and [totalSessions] is the list length.
  factory ProgressStats.fromSessions(List<Session> sessions) {
    var rubricCount = 0;
    var rubricSum = 0;
    var rubricBest = 0;
    var legacyCount = 0;
    var legacySum = 0;
    var legacyBest = 0;
    final byMovement = <String, int>{};

    for (final session in sessions) {
      byMovement.update(
        session.movementName,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final rubricTotal = ComparableRubricProgress.scoreFor(
        assessmentVersion: session.assessmentVersion,
        rubricTotal: session.rubricTotal,
      );
      if (rubricTotal != null) {
        rubricCount++;
        rubricSum += rubricTotal;
        if (rubricTotal > rubricBest) rubricBest = rubricTotal;
      } else if (session.legacyScore != null) {
        final score = session.legacyScore!;
        legacyCount++;
        legacySum += score;
        if (score > legacyBest) legacyBest = score;
      }
    }

    String? mostPracticed;
    var maxCount = 0;
    byMovement.forEach((movement, count) {
      if (count > maxCount) {
        maxCount = count;
        mostPracticed = movement;
      }
    });

    return ProgressStats(
      totalSessions: sessions.length,
      rubricSessionCount: rubricCount,
      averageRubricTotal: rubricCount == 0 ? null : rubricSum / rubricCount,
      bestRubricTotal: rubricCount == 0 ? null : rubricBest,
      legacySessionCount: legacyCount,
      averageLegacyScore: legacyCount == 0 ? null : legacySum / legacyCount,
      bestLegacyScore: legacyCount == 0 ? null : legacyBest,
      mostPracticedMovement: mostPracticed,
      sessionsByMovement: byMovement,
    );
  }
}

class ProgressRepository {
  ProgressRepository({FirestoreHelper? db}) : _dbOverride = db;

  final FirestoreHelper? _dbOverride;
  FirestoreHelper get _db => _dbOverride ?? FirestoreHelper.instance;

  Future<ProgressStats> getStatsForUser(String userId) async {
    final total = await _db.countSessionsForUser(userId);
    final assessment = await _db.sessionAssessmentStatsForUser(userId);
    final byMovement = await _db.sessionCountByMovement(userId);

    String? mostPracticed;
    var maxCount = 0;
    byMovement.forEach((movement, count) {
      if (count > maxCount) {
        maxCount = count;
        mostPracticed = movement;
      }
    });

    return ProgressStats(
      totalSessions: total,
      rubricSessionCount: assessment.rubricSessionCount,
      averageRubricTotal: assessment.averageRubricTotal,
      bestRubricTotal: assessment.bestRubricTotal,
      legacySessionCount: assessment.legacySessionCount,
      averageLegacyScore: assessment.averageLegacyScore,
      bestLegacyScore: assessment.bestLegacyScore,
      mostPracticedMovement: mostPracticed,
      sessionsByMovement: byMovement,
    );
  }
}
