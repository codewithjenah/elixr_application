import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_helper.dart';
import '../models/achievement.dart';
import '../models/achievement_claim.dart';
import '../models/leaderboard_entry.dart';
import '../models/profile_border.dart';
import '../models/session.dart';
import '../models/user_cosmetics.dart';

/// Persistence for claimable achievements and equippable profile borders.
///
/// CAPSTONE SECURITY NOTE: [claimAchievement]'s pre-transaction completion
/// check is defense-in-depth / UX only. A modified client can bypass client-
/// side evaluation and write to Firestore directly. Security rules enforce
/// fixed reward mappings, ownership, atomic claim↔cosmetics linkage,
/// idempotency, and equip-only-if-unlocked — they do **not** independently
/// verify that an achievement was completed. Because Phase 2 rewards are
/// cosmetic-only (no XP), modified-client impact is limited to the
/// attacker's own cosmetics. Trusted callable-function evaluation remains
/// the future hostile-client hardening path.
class AchievementRepository {
  AchievementRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _claimRef(String claimId) =>
      _firestore
          .collection(FirestoreCollections.achievementClaims)
          .doc(claimId);

  DocumentReference<Map<String, dynamic>> _cosmeticsRef(String userId) =>
      _firestore.collection(FirestoreCollections.userCosmetics).doc(userId);

  DocumentReference<Map<String, dynamic>> _leaderboardRef(String userId) =>
      _firestore.collection(FirestoreCollections.leaderboard).doc(userId);

  /// Live set of claimed achievement ids for [userId].
  Stream<Set<String>> watchClaimedAchievementIds(String userId) {
    return _firestore
        .collection(FirestoreCollections.achievementClaims)
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => doc.data()['achievement_id'])
              .whereType<String>()
              .toSet();
        });
  }

  /// Watches `user_cosmetics/{userId}` directly.
  Stream<UserCosmetics?> watchUserCosmetics(String userId) {
    return _cosmeticsRef(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserCosmetics.tryFromMap(doc.data()!, id: doc.id);
    });
  }

  /// Claims [achievementId] once and unlocks its reward border.
  ///
  /// Never writes XP or leaderboard aggregates. The claim and cosmetics
  /// update are atomic and bidirectionally linked through
  /// `last_achievement_claim_id`.
  Future<AchievementClaimResult> claimAchievement({
    required String userId,
    required String achievementId,
    required List<Session> sessions,
    required LeaderboardEntry? leaderboardEntry,
  }) async {
    final definition = achievementById(achievementId);
    if (definition == null) {
      return const AchievementClaimResult.invalidAchievement();
    }

    // Defense-in-depth / UX only — see class doc comment.
    final progress = definition.evaluator(sessions, leaderboardEntry);
    if (!progress.completed) {
      return const AchievementClaimResult.notCompleted();
    }

    final claimId = AchievementClaim.documentId(userId, achievementId);
    final claimRef = _claimRef(claimId);
    final cosmeticsRef = _cosmeticsRef(userId);

    return _firestore.runTransaction<AchievementClaimResult>((tx) async {
      final claimSnap = await tx.get(claimRef);
      if (claimSnap.exists) {
        return const AchievementClaimResult.alreadyClaimed();
      }

      final cosmeticsSnap = await tx.get(cosmeticsRef);
      final existing = cosmeticsSnap.data();
      if (cosmeticsSnap.exists && existing != null) {
        final parsed = UserCosmetics.tryFromMap(existing, id: userId);
        if (parsed == null) {
          return const AchievementClaimResult.cosmeticsCorrupt();
        }
      }

      final AchievementUnlockPlan plan;
      try {
        plan = AchievementUnlockPlan.fromExisting(
          claimExists: false,
          existingCosmetics: existing,
          achievementId: achievementId,
          claimDocumentId: claimId,
        );
      } on ArgumentError {
        return const AchievementClaimResult.invalidAchievement();
      }

      final claim = AchievementClaim(
        userId: userId,
        achievementId: achievementId,
        rewardBorderId: plan.rewardBorderId,
      );

      tx.set(claimRef, {
        ...claim.toMap(),
        'claimed_at': FieldValue.serverTimestamp(),
      });

      final cosmeticsPayload = <String, dynamic>{
        'user_id': userId,
        'unlocked_border_ids': plan.unlockedBorderIds,
        'last_achievement_claim_id': plan.lastAchievementClaimId,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (!cosmeticsSnap.exists) {
        cosmeticsPayload['created_at'] = FieldValue.serverTimestamp();
        tx.set(cosmeticsRef, cosmeticsPayload);
      } else {
        tx.update(cosmeticsRef, cosmeticsPayload);
      }

      return AchievementClaimResult.claimed(plan.rewardBorderId);
    });
  }

  /// Equips [borderId] on `leaderboard/{userId}.equipped_border_id`.
  ///
  /// Pass an empty [borderId] to unequip. Persists unequip as `''`.
  /// Does not modify XP, session aggregates, quest fields, or profile
  /// metadata.
  Future<EquipBorderResult> equipBorder({
    required String userId,
    required String borderId,
  }) async {
    final trimmed = borderId.trim();
    final unequipping = trimmed.isEmpty;

    if (!unequipping && !isKnownProfileBorderId(trimmed)) {
      return const EquipBorderResult.invalidBorder();
    }

    final cosmeticsRef = _cosmeticsRef(userId);
    final leaderboardRef = _leaderboardRef(userId);

    return _firestore.runTransaction<EquipBorderResult>((tx) async {
      final cosmeticsSnap = await tx.get(cosmeticsRef);
      if (!cosmeticsSnap.exists || cosmeticsSnap.data() == null) {
        if (unequipping) {
          // Nothing unlocked / nothing equipped — treat as already clear.
          final leaderboardSnap = await tx.get(leaderboardRef);
          if (!leaderboardSnap.exists || leaderboardSnap.data() == null) {
            return const EquipBorderResult.leaderboardMissing();
          }
          final current =
              (leaderboardSnap.data()!['equipped_border_id'] as String?)
                  ?.trim() ??
              '';
          if (current.isEmpty) {
            return const EquipBorderResult.alreadyEquipped();
          }
          tx.update(leaderboardRef, {
            'equipped_border_id': '',
            'updated_at': FieldValue.serverTimestamp(),
          });
          return const EquipBorderResult.equipped();
        }
        return const EquipBorderResult.cosmeticsMissing();
      }

      final cosmetics = UserCosmetics.tryFromMap(
        cosmeticsSnap.data()!,
        id: userId,
      );
      if (cosmetics == null) {
        return const EquipBorderResult.cosmeticsMissing();
      }

      if (!unequipping && !cosmetics.isUnlocked(trimmed)) {
        return const EquipBorderResult.borderLocked();
      }

      final leaderboardSnap = await tx.get(leaderboardRef);
      if (!leaderboardSnap.exists || leaderboardSnap.data() == null) {
        return const EquipBorderResult.leaderboardMissing();
      }

      final current =
          (leaderboardSnap.data()!['equipped_border_id'] as String?)?.trim() ??
          '';
      final next = unequipping ? '' : trimmed;
      if (current == next) {
        return const EquipBorderResult.alreadyEquipped();
      }

      tx.update(leaderboardRef, {
        'equipped_border_id': next,
        'updated_at': FieldValue.serverTimestamp(),
      });
      return const EquipBorderResult.equipped();
    });
  }
}
