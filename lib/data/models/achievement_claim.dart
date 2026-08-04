import 'achievement.dart';
import 'profile_border.dart';

/// Immutable achievement-claim marker. Document id is deterministic:
/// `achievement_claims/{userId}_{achievementId}`.
class AchievementClaim {
  const AchievementClaim({
    required this.userId,
    required this.achievementId,
    required this.rewardBorderId,
  });

  final String userId;
  final String achievementId;
  final String rewardBorderId;

  static String documentId(String userId, String achievementId) =>
      '${userId}_$achievementId';

  String get id => documentId(userId, achievementId);

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'achievement_id': achievementId,
      'reward_border_id': rewardBorderId,
    };
  }

  static AchievementClaim? tryFromMap(Map<String, dynamic> map) {
    final userId = map['user_id'];
    final achievementId = map['achievement_id'];
    final rewardBorderId = map['reward_border_id'];
    if (userId is! String ||
        userId.isEmpty ||
        achievementId is! String ||
        achievementId.isEmpty ||
        rewardBorderId is! String ||
        rewardBorderId.isEmpty) {
      return null;
    }
    return AchievementClaim(
      userId: userId,
      achievementId: achievementId,
      rewardBorderId: rewardBorderId,
    );
  }
}

enum AchievementClaimStatus {
  claimed,
  alreadyClaimed,
  notCompleted,
  invalidAchievement,
  cosmeticsCorrupt,
}

class AchievementClaimResult {
  const AchievementClaimResult._(this.status, {this.rewardBorderId});

  final AchievementClaimStatus status;
  final String? rewardBorderId;

  const AchievementClaimResult.claimed(String rewardBorderId)
    : this._(AchievementClaimStatus.claimed, rewardBorderId: rewardBorderId);
  const AchievementClaimResult.alreadyClaimed()
    : this._(AchievementClaimStatus.alreadyClaimed);
  const AchievementClaimResult.notCompleted()
    : this._(AchievementClaimStatus.notCompleted);
  const AchievementClaimResult.invalidAchievement()
    : this._(AchievementClaimStatus.invalidAchievement);
  const AchievementClaimResult.cosmeticsCorrupt()
    : this._(AchievementClaimStatus.cosmeticsCorrupt);
}

/// Pure unlock plan for appending exactly one reward border.
class AchievementUnlockPlan {
  const AchievementUnlockPlan._({
    required this.alreadyClaimed,
    required this.unlockedBorderIds,
    required this.lastAchievementClaimId,
    required this.rewardBorderId,
  });

  const AchievementUnlockPlan.alreadyClaimed()
    : alreadyClaimed = true,
      unlockedBorderIds = const [],
      lastAchievementClaimId = '',
      rewardBorderId = '';

  final bool alreadyClaimed;
  final List<String> unlockedBorderIds;
  final String lastAchievementClaimId;
  final String rewardBorderId;

  /// Builds the next unlocked-border list from an optional existing cosmetics
  /// map. Preserves original order, never duplicates, and returns
  /// [alreadyClaimed] without modification when [claimExists] is true.
  factory AchievementUnlockPlan.fromExisting({
    required bool claimExists,
    required Map<String, dynamic>? existingCosmetics,
    required String achievementId,
    required String claimDocumentId,
  }) {
    if (claimExists) {
      return const AchievementUnlockPlan.alreadyClaimed();
    }

    final rewardBorderId = rewardBorderForAchievement(achievementId);
    if (rewardBorderId == null || !isKnownProfileBorderId(rewardBorderId)) {
      throw ArgumentError(
        'Unknown achievement reward mapping for $achievementId',
      );
    }

    final previous = _readStringList(existingCosmetics?['unlocked_border_ids']);
    final next = List<String>.from(previous);
    if (!next.contains(rewardBorderId)) {
      next.add(rewardBorderId);
    }

    return AchievementUnlockPlan._(
      alreadyClaimed: false,
      unlockedBorderIds: List<String>.unmodifiable(next),
      lastAchievementClaimId: claimDocumentId,
      rewardBorderId: rewardBorderId,
    );
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final item in value) {
      if (item is String && item.isNotEmpty && !out.contains(item)) {
        out.add(item);
      }
    }
    return out;
  }
}

/// Typed outcome of [AchievementRepository.equipBorder].
enum EquipBorderStatus {
  equipped,
  alreadyEquipped,
  invalidBorder,
  borderLocked,
  cosmeticsMissing,
  leaderboardMissing,
}

class EquipBorderResult {
  const EquipBorderResult(this.status);

  final EquipBorderStatus status;

  const EquipBorderResult.equipped() : this(EquipBorderStatus.equipped);
  const EquipBorderResult.alreadyEquipped()
    : this(EquipBorderStatus.alreadyEquipped);
  const EquipBorderResult.invalidBorder()
    : this(EquipBorderStatus.invalidBorder);
  const EquipBorderResult.borderLocked() : this(EquipBorderStatus.borderLocked);
  const EquipBorderResult.cosmeticsMissing()
    : this(EquipBorderStatus.cosmeticsMissing);
  const EquipBorderResult.leaderboardMissing()
    : this(EquipBorderStatus.leaderboardMissing);
}

/// Validates that [achievementId] maps to a known catalog entry and reward.
bool isValidAchievementRewardPair(String achievementId, String borderId) {
  final definition = achievementById(achievementId);
  if (definition == null) return false;
  return definition.rewardBorderId == borderId &&
      isKnownProfileBorderId(borderId);
}
