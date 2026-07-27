/// Shared XP and level rules for sidebar gamification and the global leaderboard.
abstract final class GamificationRules {
  static const int xpPerSession = 25;
  static const int xpPerLevel = 250;

  static int xpForSessions(int sessionCount) {
    return sessionCount * xpPerSession;
  }

  static int levelForXp(int totalXp) {
    return totalXp ~/ xpPerLevel + 1;
  }

  static int xpIntoLevel(int totalXp) {
    return totalXp % xpPerLevel;
  }
}
