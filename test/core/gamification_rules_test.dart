import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GamificationRules', () {
    test('0 sessions = 0 XP', () {
      expect(GamificationRules.xpForSessions(0), 0);
    });

    test('0 XP = level 1', () {
      expect(GamificationRules.levelForXp(0), 1);
      expect(GamificationRules.xpIntoLevel(0), 0);
    });

    test('10 sessions = 250 XP and level 2', () {
      final xp = GamificationRules.xpForSessions(10);
      expect(xp, 250);
      expect(GamificationRules.levelForXp(xp), 2);
      expect(GamificationRules.xpIntoLevel(xp), 0);
    });

    test('XP-in-level boundaries', () {
      expect(GamificationRules.xpIntoLevel(249), 249);
      expect(GamificationRules.levelForXp(249), 1);
      expect(GamificationRules.xpIntoLevel(250), 0);
      expect(GamificationRules.levelForXp(250), 2);
      expect(GamificationRules.xpIntoLevel(251), 1);
      expect(GamificationRules.levelForXp(251), 2);
    });

    test('earning rate remains 25 XP per session', () {
      expect(GamificationRules.xpPerSession, 25);
      expect(GamificationRules.xpPerLevel, 250);
      expect(GamificationRules.xpForSessions(4), 100);
    });
  });
}
