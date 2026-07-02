import '../database/firestore_helper.dart';

class ProgressStats {
  const ProgressStats({
    required this.totalSessions,
    this.averageScore,
    this.bestScore,
    this.mostPracticedMovement,
    required this.sessionsByMovement,
  });

  final int totalSessions;
  final double? averageScore;
  final int? bestScore;
  final String? mostPracticedMovement;
  final Map<String, int> sessionsByMovement;
}

class ProgressRepository {
  ProgressRepository({FirestoreHelper? db}) : _db = db ?? FirestoreHelper.instance;

  final FirestoreHelper _db;

  Future<ProgressStats> getStatsForUser(String userId) async {
    final total = await _db.countSessionsForUser(userId);
    final avg = await _db.averageScoreForUser(userId);
    final best = await _db.bestScoreForUser(userId);
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
      averageScore: avg,
      bestScore: best,
      mostPracticedMovement: mostPracticed,
      sessionsByMovement: byMovement,
    );
  }
}
