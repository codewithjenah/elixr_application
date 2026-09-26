import 'dart:io';

import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against `lib/data/models/daily_quest.dart` and the server-side
/// quest catalog (`private.quest_definition` in the core migration) drifting
/// apart. The database cannot import Dart, so claim evaluation duplicates the
/// ids, XP tiers, and categories; an edit to one side without the other fails
/// here instead of silently diverging in production.
Map<String, (int xp, String kind)> _sqlQuestCatalog() {
  final source = File(
    'supabase/migrations/20260926000100_elixr_core.sql',
  ).readAsStringSync();
  final start = source.indexOf('function private.quest_definition(');
  if (start < 0) fail('Could not find private.quest_definition()');
  final block = source.substring(start, source.indexOf(r'$$;', start));
  return {
    for (final m in RegExp(
      r'''when '([a-z0-9_]+)' then '\[(\d+), "([a-z]+)"''',
    ).allMatches(block))
      m.group(1)!: (int.parse(m.group(2)!), m.group(3)!),
  };
}

void main() {
  late Map<String, (int xp, String kind)> sql;

  setUpAll(() => sql = _sqlQuestCatalog());

  test('the database quest catalog lists exactly the Dart catalog ids', () {
    expect(sql.keys.toSet(), questCatalog.map((q) => q.id).toSet());
  });

  test('database XP matches the Dart tier of every quest', () {
    for (final quest in questCatalog) {
      expect(sql[quest.id]!.$1, quest.tier.xp, reason: quest.id);
    }
  });

  test('database kinds match the Dart category-conflict partition', () {
    Set<String> sqlIds(String kind) => {
      for (final e in sql.entries)
        if (e.value.$2 == kind) e.key,
    };
    Set<String> dartIds(QuestCategory category) => questCatalog
        .where((q) => q.category == category)
        .map((q) => q.id)
        .toSet();
    expect(sqlIds('count'), dartIds(QuestCategory.sessionCount));
    expect(sqlIds('duration'), dartIds(QuestCategory.duration));
    expect(sqlIds('best'), dartIds(QuestCategory.scoreThreshold));
  });

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

  test('every quest minimumLevel is at least 1', () {
    for (final quest in questCatalog) {
      expect(quest.minimumLevel, greaterThanOrEqualTo(1), reason: quest.id);
    }
  });

  test('content-dependent quests stay in the catalog for persisted boards', () {
    const contentDependentIds = {
      'two_movements',
      'three_movements',
      'practice_easy_movement',
      'practice_medium_movement',
      'practice_hard_movement',
      'use_shaker',
      'distinct_props_2',
      'use_bottle_and_shaker_combo',
    };
    expect(
      questCatalog.map((quest) => quest.id).toSet(),
      containsAll(contentDependentIds),
    );
  });

  test(
    'coarse minimumLevel is not enough to make singleton-gated content quests eligible',
    () {
      const gatedAtMinimum = {
        'two_movements',
        'three_movements',
        'practice_medium_movement',
        'practice_hard_movement',
        'use_shaker',
        'distinct_props_2',
        'use_bottle_and_shaker_combo',
      };
      for (final id in gatedAtMinimum) {
        final quest = questById(id)!;
        final pool = DailyQuestUnlockPool.fromPersonalLevel(quest.minimumLevel);
        expect(
          isEligibleForDailyQuestGeneration(quest, pool),
          isFalse,
          reason:
              '$id should still be ineligible at minimumLevel ${quest.minimumLevel}',
        );
      }
    },
  );
}
