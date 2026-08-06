/// Cosmetic profile-border catalog for achievement rewards.
///
/// Pure Dart — uses fixed integer ARGB color values so unit tests and
/// Firestorm rule helpers can share IDs without importing Flutter `Color`.
enum ProfileBorderRarity { common, uncommon, rare, epic, legendary }

/// Strongly typed ornament family for the frame painter.
enum ProfileBorderVisualStyle {
  beginnerCrest,
  bronzeMetal,
  violetLiquid,
  royalGold,
  cyanSegments,
  crystalPulse,
  spectrumArc,
  triadSegments,
  streakShield,
  tinArmor,
}

/// Motion personality for animated frames.
enum ProfileBorderMotionStyle {
  softSweep,
  emberDrift,
  liquidFlow,
  crownShimmer,
  orbitalDots,
  crystalPulse,
  spectrumSlide,
  triadBreath,
  streakGlow,
  armoredOrbit,
}

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
    required this.visualStyle,
    required this.motionStyle,
    this.tertiaryColorValue,
    this.ornamentIntensity = 0.55,
    this.particleCount = 0,
    this.animationDurationMs = 4200,
  });

  final String id;
  final String displayName;
  final String description;
  final ProfileBorderRarity rarity;

  /// ARGB integer (e.g. `0xFF7C4DFF`). Convert with `Color(value)` in UI.
  final int primaryColorValue;
  final int secondaryColorValue;

  /// Optional third accent used by multi-tone frames.
  final int? tertiaryColorValue;

  /// Soft outer glow strength in logical pixels (0 = none).
  final double glowStrength;
  final double strokeWidth;

  final ProfileBorderVisualStyle visualStyle;
  final ProfileBorderMotionStyle motionStyle;

  /// 0–1 strength for crests, fins, and metal layering.
  final double ornamentIntensity;

  /// Suggested particle count when animation is enabled.
  final int particleCount;

  /// Preferred loop duration in milliseconds (typically 3000–6000).
  final int animationDurationMs;

  /// Extra layout padding (logical px) outside the avatar diameter so
  /// crests/fins/particles are not clipped.
  double get ornamentExtent {
    final base = switch (rarity) {
      ProfileBorderRarity.common => 10.0,
      ProfileBorderRarity.uncommon => 12.0,
      ProfileBorderRarity.rare => 14.0,
      ProfileBorderRarity.epic => 16.0,
      ProfileBorderRarity.legendary => 18.0,
    };
    return base + strokeWidth + ornamentIntensity * 4;
  }

  String get rarityLabel => switch (rarity) {
    ProfileBorderRarity.common => 'Common',
    ProfileBorderRarity.uncommon => 'Uncommon',
    ProfileBorderRarity.rare => 'Rare',
    ProfileBorderRarity.epic => 'Epic',
    ProfileBorderRarity.legendary => 'Legendary',
  };
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
        tertiaryColorValue: 0xFF4FC3F7,
        glowStrength: 4,
        strokeWidth: 2.5,
        visualStyle: ProfileBorderVisualStyle.beginnerCrest,
        motionStyle: ProfileBorderMotionStyle.softSweep,
        ornamentIntensity: 0.35,
        particleCount: 0,
        animationDurationMs: 4800,
      ),
      ProfileBorderDefinition(
        id: 'bronze_ember',
        displayName: 'Bronze Ember',
        description: 'Warm bronze for trainees building momentum.',
        rarity: ProfileBorderRarity.common,
        primaryColorValue: 0xFFCD7F32,
        secondaryColorValue: 0xFFE8A87C,
        tertiaryColorValue: 0xFFFF6E40,
        glowStrength: 5,
        strokeWidth: 2.5,
        visualStyle: ProfileBorderVisualStyle.bronzeMetal,
        motionStyle: ProfileBorderMotionStyle.emberDrift,
        ornamentIntensity: 0.45,
        particleCount: 3,
        animationDurationMs: 5200,
      ),
      ProfileBorderDefinition(
        id: 'violet_flow',
        displayName: 'Violet Flow',
        description: 'A flowing violet halo for dedicated flair practice.',
        rarity: ProfileBorderRarity.uncommon,
        primaryColorValue: 0xFF7C4DFF,
        secondaryColorValue: 0xFFB388FF,
        tertiaryColorValue: 0xFFE040FB,
        glowStrength: 6,
        strokeWidth: 3,
        visualStyle: ProfileBorderVisualStyle.violetLiquid,
        motionStyle: ProfileBorderMotionStyle.liquidFlow,
        ornamentIntensity: 0.55,
        particleCount: 2,
        animationDurationMs: 5600,
      ),
      ProfileBorderDefinition(
        id: 'gold_mastery',
        displayName: 'Gold Mastery',
        description: 'Century-club gold for elite session volume.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFFFC107,
        secondaryColorValue: 0xFFFFECB3,
        tertiaryColorValue: 0xFFFFD54F,
        glowStrength: 8,
        strokeWidth: 3,
        visualStyle: ProfileBorderVisualStyle.royalGold,
        motionStyle: ProfileBorderMotionStyle.crownShimmer,
        ornamentIntensity: 0.7,
        particleCount: 2,
        animationDurationMs: 4500,
      ),
      ProfileBorderDefinition(
        id: 'cyan_orbit',
        displayName: 'Cyan Orbit',
        description: 'Orbital cyan earned by scoring 90 or higher.',
        rarity: ProfileBorderRarity.uncommon,
        primaryColorValue: 0xFF00BCD4,
        secondaryColorValue: 0xFF80DEEA,
        tertiaryColorValue: 0xFFE0F7FA,
        glowStrength: 6,
        strokeWidth: 3,
        visualStyle: ProfileBorderVisualStyle.cyanSegments,
        motionStyle: ProfileBorderMotionStyle.orbitalDots,
        ornamentIntensity: 0.55,
        particleCount: 2,
        animationDurationMs: 4000,
      ),
      ProfileBorderDefinition(
        id: 'perfect_serve',
        displayName: 'Perfect Serve',
        description: 'A pristine rim reserved for a flawless 100.',
        rarity: ProfileBorderRarity.epic,
        primaryColorValue: 0xFFE91E63,
        secondaryColorValue: 0xFFF8BBD0,
        tertiaryColorValue: 0xFFFFFFFF,
        glowStrength: 9,
        strokeWidth: 3.5,
        visualStyle: ProfileBorderVisualStyle.crystalPulse,
        motionStyle: ProfileBorderMotionStyle.crystalPulse,
        ornamentIntensity: 0.75,
        particleCount: 3,
        animationDurationMs: 5000,
      ),
      ProfileBorderDefinition(
        id: 'prismatic_arc',
        displayName: 'Prismatic Arc',
        description: 'Multi-hue arc for explorers of many movements.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFAB47BC,
        secondaryColorValue: 0xFF26C6DA,
        tertiaryColorValue: 0xFFFFCA28,
        glowStrength: 7,
        strokeWidth: 3,
        visualStyle: ProfileBorderVisualStyle.spectrumArc,
        motionStyle: ProfileBorderMotionStyle.spectrumSlide,
        ornamentIntensity: 0.65,
        particleCount: 0,
        animationDurationMs: 5400,
      ),
      ProfileBorderDefinition(
        id: 'triad_frame',
        displayName: 'Triad Frame',
        description: 'Three-tone frame for Easy, Medium, and Hard mastery.',
        rarity: ProfileBorderRarity.epic,
        primaryColorValue: 0xFF43A047,
        secondaryColorValue: 0xFFFF7043,
        tertiaryColorValue: 0xFF1E88E5,
        glowStrength: 8,
        strokeWidth: 3.5,
        visualStyle: ProfileBorderVisualStyle.triadSegments,
        motionStyle: ProfileBorderMotionStyle.triadBreath,
        ornamentIntensity: 0.7,
        particleCount: 0,
        animationDurationMs: 4800,
      ),
      ProfileBorderDefinition(
        id: 'week_warrior',
        displayName: 'Week Warrior',
        description: 'Consistency ring for a seven-day practice streak.',
        rarity: ProfileBorderRarity.rare,
        primaryColorValue: 0xFFFF7043,
        secondaryColorValue: 0xFFFFAB91,
        tertiaryColorValue: 0xFFFFD180,
        glowStrength: 7,
        strokeWidth: 3,
        visualStyle: ProfileBorderVisualStyle.streakShield,
        motionStyle: ProfileBorderMotionStyle.streakGlow,
        ornamentIntensity: 0.6,
        particleCount: 2,
        animationDurationMs: 4600,
      ),
      ProfileBorderDefinition(
        id: 'tin_specialist',
        displayName: 'Tin Specialist',
        description: 'Specialist plating for Bottle in a Tin experts.',
        rarity: ProfileBorderRarity.legendary,
        primaryColorValue: 0xFF5C6BC0,
        secondaryColorValue: 0xFFFFD54F,
        tertiaryColorValue: 0xFFB0BEC5,
        glowStrength: 10,
        strokeWidth: 3.5,
        visualStyle: ProfileBorderVisualStyle.tinArmor,
        motionStyle: ProfileBorderMotionStyle.armoredOrbit,
        ornamentIntensity: 0.9,
        particleCount: 4,
        animationDurationMs: 3800,
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
