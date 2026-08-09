import 'achievement.dart';
import 'profile_border.dart';

/// Ordered unlocked/locked profile borders for Settings presentation.
///
/// Does not include the "No Frame" utility control — that stays outside
/// these groups in the UI.
class ProfileFramePresentationOrder {
  const ProfileFramePresentationOrder({
    required this.unlockedBorders,
    required this.lockedBorders,
  });

  final List<ProfileBorderDefinition> unlockedBorders;
  final List<ProfileBorderDefinition> lockedBorders;
}

/// Builds presentation order for profile frames.
///
/// Order rules:
/// - Unlocked: equipped first (when a known catalog border), then remaining
///   unlocked by achievement [progressionOrder], then catalog-index fallback
///   for borders without an achievement mapping.
/// - Locked: achievement progression, then catalog-index fallback.
///
/// If [equippedBorderId] is a known catalog border but missing from
/// [unlockedBorderIds], it is included under unlocked for display only.
/// Caller sets are never mutated; nothing is persisted.
ProfileFramePresentationOrder buildProfileFramePresentationOrder({
  required Set<String> unlockedBorderIds,
  required String? equippedBorderId,
}) {
  final catalogIndex = <String, int>{
    for (var i = 0; i < profileBorderCatalog.length; i++)
      profileBorderCatalog[i].id: i,
  };

  final progressionByBorderId = <String, int>{};
  for (final achievement in achievementCatalog) {
    progressionByBorderId[achievement.rewardBorderId] =
        achievement.progressionOrder;
  }

  final normalizedEquipped = _normalizeEquippedId(equippedBorderId);
  final equippedBorder = normalizedEquipped == null
      ? null
      : profileBorderById(normalizedEquipped);

  final presentationUnlockedIds = <String>{
    ...unlockedBorderIds.where(isKnownProfileBorderId),
    if (equippedBorder != null) equippedBorder.id,
  };

  final unlocked = <ProfileBorderDefinition>[];
  final locked = <ProfileBorderDefinition>[];
  for (final border in profileBorderCatalog) {
    if (presentationUnlockedIds.contains(border.id)) {
      unlocked.add(border);
    } else {
      locked.add(border);
    }
  }

  int compareBorders(ProfileBorderDefinition a, ProfileBorderDefinition b) {
    final aProgression = progressionByBorderId[a.id];
    final bProgression = progressionByBorderId[b.id];
    if (aProgression != null && bProgression != null) {
      final byProgression = aProgression.compareTo(bProgression);
      if (byProgression != 0) return byProgression;
    } else if (aProgression != null) {
      return -1;
    } else if (bProgression != null) {
      return 1;
    }
    final aIndex = catalogIndex[a.id] ?? 1 << 20;
    final bIndex = catalogIndex[b.id] ?? 1 << 20;
    final byIndex = aIndex.compareTo(bIndex);
    if (byIndex != 0) return byIndex;
    return a.id.compareTo(b.id);
  }

  unlocked.sort((a, b) {
    if (equippedBorder != null) {
      if (a.id == equippedBorder.id && b.id != equippedBorder.id) return -1;
      if (b.id == equippedBorder.id && a.id != equippedBorder.id) return 1;
    }
    return compareBorders(a, b);
  });
  locked.sort(compareBorders);

  return ProfileFramePresentationOrder(
    unlockedBorders: List<ProfileBorderDefinition>.unmodifiable(unlocked),
    lockedBorders: List<ProfileBorderDefinition>.unmodifiable(locked),
  );
}

String? _normalizeEquippedId(String? equippedBorderId) {
  if (equippedBorderId == null) return null;
  final trimmed = equippedBorderId.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}
