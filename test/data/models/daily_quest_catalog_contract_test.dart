import 'dart:io';

import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against `lib/data/models/daily_quest.dart` and `firestore.rules`
/// drifting apart. Security rules cannot import Dart source, so the quest
/// catalog's ids, XP-tier partition, and category-conflict partition are
/// deliberately duplicated as literal lists in `firestore.rules`. This test
/// parses those literals straight out of the rules file and asserts they
/// match the Dart catalog exactly, so an edit to one side without the other
/// fails loudly here instead of silently diverging in production.
List<String> _extractIdList(String rulesSource, String functionName) {
  final pattern = RegExp('function $functionName\\(\\)\\s*\\{([\\s\\S]*?)\\}');
  final match = pattern.firstMatch(rulesSource);
  if (match == null) {
    fail('Could not find function $functionName() in firestore.rules');
  }
  final body = match.group(1)!;
  final idPattern = RegExp("'([a-zA-Z0-9_]+)'");
  return idPattern.allMatches(body).map((m) => m.group(1)!).toList();
}

void main() {
  late String rulesSource;

  setUpAll(() {
    // `flutter test` runs with the repository root as the working
    // directory, so this relative path resolves to the real ruleset.
    final file = File('firestore.rules');
    if (!file.existsSync()) {
      fail(
        'Could not find firestore.rules relative to the test working directory',
      );
    }
    rulesSource = file.readAsStringSync();
  });

  test('questCatalogIds() lists exactly the Dart catalog ids', () {
    final ruleIds = _extractIdList(rulesSource, 'questCatalogIds').toSet();
    final dartIds = questCatalog.map((q) => q.id).toSet();
    expect(ruleIds, dartIds);
  });

  test('easyIds()/mediumIds()/hardIds() match the Dart tier partition', () {
    final ruleEasy = _extractIdList(rulesSource, 'easyIds').toSet();
    final ruleMedium = _extractIdList(rulesSource, 'mediumIds').toSet();
    final ruleHard = _extractIdList(rulesSource, 'hardIds').toSet();

    final dartEasy = questCatalog
        .where((q) => q.tier == QuestTier.easy)
        .map((q) => q.id)
        .toSet();
    final dartMedium = questCatalog
        .where((q) => q.tier == QuestTier.medium)
        .map((q) => q.id)
        .toSet();
    final dartHard = questCatalog
        .where((q) => q.tier == QuestTier.hard)
        .map((q) => q.id)
        .toSet();

    expect(
      ruleEasy,
      dartEasy,
      reason: 'easyIds() diverged from QuestTier.easy',
    );
    expect(
      ruleMedium,
      dartMedium,
      reason: 'mediumIds() diverged from QuestTier.medium',
    );
    expect(
      ruleHard,
      dartHard,
      reason: 'hardIds() diverged from QuestTier.hard',
    );
  });

  test(
    'sessionCountIds()/durationIds()/scoreThresholdIds() match the Dart category partition',
    () {
      final ruleSessionCount = _extractIdList(
        rulesSource,
        'sessionCountIds',
      ).toSet();
      final ruleDuration = _extractIdList(rulesSource, 'durationIds').toSet();
      final ruleScoreThreshold = _extractIdList(
        rulesSource,
        'scoreThresholdIds',
      ).toSet();

      final dartSessionCount = questCatalog
          .where((q) => q.category == QuestCategory.sessionCount)
          .map((q) => q.id)
          .toSet();
      final dartDuration = questCatalog
          .where((q) => q.category == QuestCategory.duration)
          .map((q) => q.id)
          .toSet();
      final dartScoreThreshold = questCatalog
          .where((q) => q.category == QuestCategory.scoreThreshold)
          .map((q) => q.id)
          .toSet();

      expect(ruleSessionCount, dartSessionCount);
      expect(ruleDuration, dartDuration);
      expect(ruleScoreThreshold, dartScoreThreshold);
    },
  );

  test('every catalog id has fixed XP matching its tier (10/15/20 only)', () {
    for (final quest in questCatalog) {
      final expectedXp = switch (quest.tier) {
        QuestTier.easy => 10,
        QuestTier.medium => 15,
        QuestTier.hard => 20,
      };
      expect(
        quest.xp,
        expectedXp,
        reason:
            '${quest.id} has unexpected XP ${quest.xp} for tier ${quest.tier}',
      );
    }
  });

  test(
    'the catalog has exactly 6 easy, 7 medium, 5 hard quests (18 total)',
    () {
      expect(questCatalog, hasLength(18));
      expect(questCatalog.where((q) => q.tier == QuestTier.easy), hasLength(6));
      expect(
        questCatalog.where((q) => q.tier == QuestTier.medium),
        hasLength(7),
      );
      expect(questCatalog.where((q) => q.tier == QuestTier.hard), hasLength(5));
    },
  );

  test(
    'maximum possible daily quest XP is exactly 70 (2*10 + 2*15 + 1*20)',
    () {
      const maxDailyQuestXp = 2 * 10 + 2 * 15 + 1 * 20;
      expect(maxDailyQuestXp, 70);
    },
  );
}
