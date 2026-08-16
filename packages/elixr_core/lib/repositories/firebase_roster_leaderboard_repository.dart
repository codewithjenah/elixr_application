import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/roster_leaderboard_entry.dart';
import '../models/teacher_student_link.dart';
import 'roster_leaderboard_repository.dart';

class FirebaseRosterLeaderboardRepository
    implements RosterLeaderboardRepository {
  FirebaseRosterLeaderboardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<RosterLeaderboardEntry>> fetchRosterRanking(
    String teacherId,
  ) async {
    final linkSnapshot = await _firestore
        .collection(FirestoreCollections.teacherStudentLinks)
        .where('teacher_id', isEqualTo: teacherId)
        .get();
    final links = linkSnapshot.docs
        .map((doc) => TeacherStudentLink.tryFromMap(doc.data(), id: doc.id))
        .whereType<TeacherStudentLink>()
        .where((link) => link.isApproved)
        .toList();
    final fallbackNames = {
      for (final link in links) link.traineeId: link.traineeDisplayName,
    };
    final leaderboardRows = <String, Map<String, dynamic>>{};
    final ids = fallbackNames.keys.toList();
    for (var offset = 0; offset < ids.length; offset += 30) {
      final chunk = ids.skip(offset).take(30).toList();
      final snapshot = await _firestore
          .collection(FirestoreCollections.leaderboard)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        leaderboardRows[doc.id] = doc.data();
      }
    }
    final result = <RosterLeaderboardEntry>[
      for (final entry in fallbackNames.entries)
        RosterLeaderboardEntry.tryFromMap(
              leaderboardRows[entry.key] ?? const {},
              id: entry.key,
              fallbackName: entry.value,
            ) ??
            RosterLeaderboardEntry(
              userId: entry.key,
              displayName: entry.value,
              totalXp: 0,
              sessionsCompleted: 0,
              bestScore: 0,
              rosterRank: 0,
            ),
    ]..sort(RosterLeaderboardEntry.compare);
    return List.unmodifiable([
      for (var index = 0; index < result.length; index++)
        result[index].withRank(index + 1),
    ]);
  }

  @override
  Future<int?> fetchGlobalRank(String userId) async {
    final own = await _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId)
        .get();
    if (!own.exists) return null;
    final snapshot = await _firestore
        .collection(FirestoreCollections.leaderboard)
        .orderBy('total_xp', descending: true)
        .orderBy('best_score', descending: true)
        .orderBy(FieldPath.documentId)
        .get();
    final index = snapshot.docs.indexWhere((doc) => doc.id == userId);
    return index < 0 ? null : index + 1;
  }
}
