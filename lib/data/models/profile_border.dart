/// Cosmetic profile-border catalog for achievement rewards.
///
/// Pure Dart — uses fixed integer ARGB color values so unit tests and
/// Firestorm rule helpers can share IDs without importing Flutter `Color`.
enum ProfileBorderRarity { common, uncommon, rare, epic, legendary }

class ProfileBorderDefinition {
  const ProfileBorderDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.rarity,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    required this.glowStrength,
    required this.strokeWidth,
  });

  final String id;
  final String displayName;
  final String description;
  final ProfileBorderRarity rarity;

  /// ARGB integer (e.g. `0xFF7C4DFF`). Convert with `Color(value)` in UI.
  final int primaryColorValue;
  final int secondaryColorValue;

  /// Soft outer glow strength in logical pixels (0 = none).
  final double glowStrength;
  final double strokeWidth;
}

const List<ProfileBorderDefinition> profileBorderCatalog =
    <ProfileBorderDefinition>[
      ProfileBorderDefinition(
        id: 'starter_glow',
        displayName: 'Starter Glow',
        description: 'A soft debut rim for your first session.',
        rarity: ProfileBorderRarity.common,
        primaryColorValue: 0xFF90CAF9,
        secondaryColorValue: 0xFFE3F2FD,
        glowStrength: 4,
        strokeWidth: 2.5,
      ),
      ProfileBorderDefinition(
        id: 'bronze_ember',
        displayName: 'Bronze Ember',
        description: 'Warm bronze for trainees building momentum.',
        rarity: ProfileBorderRarity.common,
        primaryColorValue: 0xFFCD7F32,
        secondaryColorValue: 0xFFE8A87C,
        glowStrength: 5,
        strokeWidth: 2.5,
      ),
      ProfileBorderDefinition(
        id: 'violet_flow',
        displayName: 'Violet Flow',
        description: 'A flowing violet halo for dedicated flair practice.',
        rarity: ProfileBorderRarity.uncommon,
        primaryColorValue: 0xFF7C4DFF,
        secondaryColorValue: 0xFFB388FF,
        glowStrength: 6,
        strokeWidth: 3,
      ),
      ProfileBorderDefinition(
        id: 'gold_mastery',
        displayName: 'Gold Mastery',
        description: 'Century-club gold for elite session volume.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFFFC107,
        secondaryColorValue: 0xFFFFECB3,
        glowStrength: 8,
        strokeWidth: 3,
      ),
      ProfileBorderDefinition(
        id: 'cyan_orbit',
        displayName: 'Cyan Orbit',
        description: 'Orbital cyan earned by scoring 90 or higher.',
        rarity: ProfileBorderRarity.uncommon,
        primaryColorValue: 0xFF00BCD4,
        secondaryColorValue: 0xFF80DEEA,
        glowStrength: 6,
        strokeWidth: 3,
      ),
      ProfileBorderDefinition(
        id: 'perfect_serve',
        displayName: 'Perfect Serve',
        description: 'A pristine rim reserved for a flawless 100.',
        rarity: ProfileBorderRarity.epic,
        primaryColorValue: 0xFFE91E63,
        secondaryColorValue: 0xFFF8BBD0,
        glowStrength: 9,
        strokeWidth: 3.5,
      ),
      ProfileBorderDefinition(
        id: 'prismatic_arc',
        displayName: 'Prismatic Arc',
        description: 'Multi-hue arc for explorers of many movements.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFAB47BC,
        secondaryColorValue: 0xFF26C6DA,
        glowStrength: 7,
        strokeWidth: 3,
      ),
      ProfileBorderDefinition(
        id: 'triad_frame',
        displayName: 'Triad Frame',
        description: 'Three-tone frame for Easy, Medium, and Hard mastery.',
        rarity: ProfileBorderRarity.epic,
        primaryColorValue: 0xFF43A047,
        secondaryColorValue: 0xFFFF7043,
        glowStrength: 8,
        strokeWidth: 3.5,
      ),
      ProfileBorderDefinition(
        id: 'week_warrior',
        displayName: 'Week Warrior',
        description: 'Consistency ring for a seven-day practice streak.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFFF7043,
        secondaryColorValue: 0xFFFFAB91,
        glowStrength: 7,
        strokeWidth: 3,
      ),
      ProfileBorderDefinition(
        id: 'tin_specialist',
        displayName: 'Tin Specialist',
        description: 'Specialist plating for Bottle in a Tin experts.',
        rarity: ProfileBorderRarity.legendary,
        primaryColorValue: 0xFF5C6BC0,
        secondaryColorValue: 0xFFFFD54F,
        glowStrength: 10,
        strokeWidth: 3.5,
      ),
    ];

/// Fixed achievement → reward border mapping (exactly one border per achievement).
const Map<String, String> achievementRewardBorderIds = <String, String>{
  'first_steps': 'starter_glow',
  'getting_started': 'bronze_ember',
  'flair_regular': 'violet_flow',
  'century_club': 'gold_mastery',
  'sharp_pour': 'cyan_orbit',
  'perfect_serve': 'perfect_serve',
  'movement_explorer': 'prismatic_arc',
  'versatility_master': 'triad_frame',
  'week_warrior': 'week_warrior',
  'bottle_in_tin_specialist': 'tin_specialist',
};

ProfileBorderDefinition? profileBorderById(String id) {
  for (final border in profileBorderCatalog) {
    if (border.id == id) return border;
  }
  return null;
}

bool isKnownProfileBorderId(String id) => profileBorderById(id) != null;

String? rewardBorderForAchievement(String achievementId) =>
    achievementRewardBorderIds[achievementId];
