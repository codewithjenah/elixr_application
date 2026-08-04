/// Private cosmetics inventory for a single user.
///
/// Equipped border is NOT stored here — public equipped state lives on
/// `leaderboard/{userId}.equipped_border_id`.
class UserCosmetics {
  const UserCosmetics({
    required this.userId,
    required this.unlockedBorderIds,
    required this.lastAchievementClaimId,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;
  final List<String> unlockedBorderIds;
  final String lastAchievementClaimId;
  final String? createdAt;
  final String? updatedAt;

  bool isUnlocked(String borderId) => unlockedBorderIds.contains(borderId);

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'unlocked_border_ids': List<String>.from(unlockedBorderIds),
      'last_achievement_claim_id': lastAchievementClaimId,
    };
  }

  static UserCosmetics? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final userId = _readString(map['user_id']) ?? id;
    if (userId == null || userId.isEmpty) return null;

    final unlocked = <String>[];
    final raw = map['unlocked_border_ids'];
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.isNotEmpty && !unlocked.contains(item)) {
          unlocked.add(item);
        }
      }
    }

    final lastClaim = _readString(map['last_achievement_claim_id']) ?? '';

    return UserCosmetics(
      userId: userId,
      unlockedBorderIds: List<String>.unmodifiable(unlocked),
      lastAchievementClaimId: lastClaim,
      createdAt: _readTimestampString(map['created_at']),
      updatedAt: _readTimestampString(map['updated_at']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static String? _readTimestampString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toIso8601String();
      }
    } catch (_) {
      // Unit tests may pass plain maps without Timestamp.
    }
    return null;
  }
}
