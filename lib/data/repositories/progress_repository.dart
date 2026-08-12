import '../database/firestore_helper.dart';

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
}

class ProgressRepository {
  ProgressRepository({FirestoreHelper? db})
    : _db = db ?? FirestoreHelper.instance;

  final FirestoreHelper _db;

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
