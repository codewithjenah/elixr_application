import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/manila_day.dart';
import '../database/firestore_helper.dart';
import '../models/daily_quest.dart';
import '../models/daily_quest_board.dart';
import '../models/quest_claim.dart';
import '../models/session.dart';

/// Persistence for the daily quest board and quest claims.
///
/// CAPSTONE SECURITY NOTE: [claimQuest]'s pre-transaction completion check
/// (and its `boardExpired` pre-check) are defense-in-depth / UX guards only
/// — they let the UI show a precise message instead of an opaque
/// permission error, and they save a doomed round-trip to Firestore. They
/// are **not** a security boundary: a modified client could skip this
/// class entirely and write to Firestore directly. The actual security
/// boundary is `firestore.rules` — XP-arithmetic invariants, catalog
/// membership, replay-proof claim/leaderboard linkage, and the
/// server-time-anchored Asia/Manila real-day window (`request.time` is
/// stamped by the Firestore server and cannot be spoofed by the client).
class GamificationRepository {
  GamificationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _boardRef(String boardId) =>
      _firestore.collection(FirestoreCollections.dailyQuestBoards).doc(boardId);

  DocumentReference<Map<String, dynamic>> _claimRef(String claimId) =>
      _firestore.collection(FirestoreCollections.dailyQuestClaims).doc(claimId);

  DocumentReference<Map<String, dynamic>> _leaderboardRef(String userId) =>
      _firestore.collection(FirestoreCollections.leaderboard).doc(userId);

  /// Returns today's (Manila calendar day) board for [userId], creating it
  /// deterministically on first access. Never mutates `quest_ids`/`day_key`/
  /// `day_start` once created — a repeated call on the same real day always
  /// returns the same board.
  Future<DailyQuestBoard> getOrCreateDailyBoard({
    required String userId,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final dayKey = ManilaDay.dayKeyFor(now);
    final dayStart = ManilaDay.dayStartUtcFor(now);
    final boardRef = _boardRef(DailyQuestBoard.documentId(userId, dayKey));

    return _firestore.runTransaction<DailyQuestBoard>((tx) async {
      final snap = await tx.get(boardRef);
      if (snap.exists && snap.data() != null) {
        final existing = DailyQuestBoard.tryFromMap(snap.data()!);
        if (existing != null) return existing;
      }

      final questIds = generateDailyQuestIds(userId: userId, dayKey: dayKey);
      final board = DailyQuestBoard(
        userId: userId,
        dayKey: dayKey,
        dayStart: dayStart,
        questIds: questIds,
      );
      tx.set(boardRef, {
        ...board.toMap(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return board;
    });
  }

  /// Live set of claimed quest ids for [userId]'s board [boardId]. Filters
  /// on both fields (matches the `user_id`+`board_id` composite index in
  /// `firestore.indexes.json` and the ownership-scoped `list` rule).
  Stream<Set<String>> watchClaimedQuestIds({
    required String userId,
    required String boardId,
  }) {
    return _firestore
        .collection(FirestoreCollections.dailyQuestClaims)
        .where('user_id', isEqualTo: userId)
        .where('board_id', isEqualTo: boardId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => doc.data()['quest_id'])
              .whereType<String>()
              .toSet();
        });
  }

  /// Claims [questId] for [userId], awarding its fixed catalog XP exactly
  /// once. See the class-level capstone security note above.
  Future<QuestClaimResult> claimQuest({
    required String userId,
    required String questId,
    required List<Session> sessionsToday,
    DateTime? nowUtc,
  }) async {
    final quest = questById(questId);
    if (quest == null) {
      return const QuestClaimResult.invalidQuest();
    }

    final now = (nowUtc ?? DateTime.now()).toUtc();
    final currentDayKey = ManilaDay.dayKeyFor(now);

    // Defense-in-depth only (see class doc comment) — evaluated against the
    // caller-supplied sessionsToday, which should already be filtered to
    // the board's Manila window via sessionsWithinBoardWindow.
    if (!quest.evaluate(sessionsToday).completed) {
      return const QuestClaimResult.questNotCompleted();
    }

    final boardId = DailyQuestBoard.documentId(userId, currentDayKey);
    final boardRef = _boardRef(boardId);
    final leaderboardRef = _leaderboardRef(userId);
    final claimId = QuestClaim.documentId(userId, currentDayKey, questId);
    final claimRef = _claimRef(claimId);

    return _firestore.runTransaction<QuestClaimResult>((tx) async {
      final claimSnap = await tx.get(claimRef);
      if (claimSnap.exists) {
        return const QuestClaimResult.alreadyClaimed();
      }

      final boardSnap = await tx.get(boardRef);
      if (!boardSnap.exists || boardSnap.data() == null) {
        return const QuestClaimResult.boardMissing();
      }
      final board = DailyQuestBoard.tryFromMap(boardSnap.data()!);
      if (board == null) {
        return const QuestClaimResult.boardMissing();
      }
      // Client-side-only freshness check; firestore.rules independently
      // enforces the real window via request.time regardless of this.
      if (!ManilaDay.dayKeyEquals(board.dayKey, currentDayKey)) {
        return const QuestClaimResult.boardExpired();
      }
      if (!board.questIds.contains(questId)) {
        return const QuestClaimResult.invalidQuest();
      }

      final leaderboardSnap = await tx.get(leaderboardRef);
      if (!leaderboardSnap.exists || leaderboardSnap.data() == null) {
        return const QuestClaimResult.leaderboardMissing();
      }

      final plan = QuestAwardPlan.fromExisting(
        claimExists: false,
        existing: leaderboardSnap.data(),
        xpAwarded: quest.xp,
      );

      final claim = QuestClaim(
        userId: userId,
        boardId: boardId,
        dayKey: currentDayKey,
        dayStart: board.dayStart,
        questId: questId,
        xpAwarded: quest.xp,
      );
      tx.set(claimRef, {
        ...claim.toMap(),
        'claimed_at': FieldValue.serverTimestamp(),
      });
      tx.set(leaderboardRef, {
        'quest_xp': plan.questXp,
        'total_xp': plan.totalXp,
        'last_claim_id': claimId,
      }, SetOptions(merge: true));

      return QuestClaimResult.claimed(quest.xp);
    });
  }
}
