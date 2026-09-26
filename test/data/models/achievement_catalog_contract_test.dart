import 'dart:io';

import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:flutter_test/flutter_test.dart';

/// Body of a `create or replace function private.<name>(...)` definition.
String _sqlFunctionBody(String source, String name) {
  final start = source.indexOf('function private.$name(');
  if (start < 0) fail('Could not find private.$name() in the core migration');
  final bodyStart = source.indexOf(r'$$', start);
  final bodyEnd = source.indexOf(r'$$', bodyStart + 2);
  return source.substring(bodyStart + 2, bodyEnd);
}

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260926000100_elixr_core.sql',
    ).readAsStringSync();
  });

  Map<String, String> rewardMap() => {
    for (final m in RegExp(
      r"when '([a-z0-9_]+)' then '([a-z0-9_]+)'",
    ).allMatches(_sqlFunctionBody(sql, 'achievement_reward_border')))
      m.group(1)!: m.group(2)!,
  };

  test('database achievement ids are exactly the Dart catalog ids', () {
    expect(
      rewardMap().keys.toSet(),
      achievementCatalog.map((a) => a.id).toSet(),
    );
  });

  test('database border ids are exactly the Dart border catalog ids', () {
    final body = _sqlFunctionBody(sql, 'is_known_border');
    expect(
      RegExp("'([a-z0-9_]+)'").allMatches(body).map((m) => m.group(1)).toSet(),
      profileBorderCatalog.map((b) => b.id).toSet(),
    );
  });

  test('achievement_reward_border matches Dart reward mappings', () {
    final map = rewardMap();
    expect(map, achievementRewardBorderIds);
    for (final achievement in achievementCatalog) {
      expect(map[achievement.id], achievement.rewardBorderId);
    }
  });
}
