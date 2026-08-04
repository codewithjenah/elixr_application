import 'dart:io';

import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:flutter_test/flutter_test.dart';

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

Map<String, String> _extractRewardMap(String rulesSource) {
  final pattern = RegExp(
    r"function rewardBorderForAchievement\(id\)\s*\{([\s\S]*?)\}",
  );
  final match = pattern.firstMatch(rulesSource);
  if (match == null) {
    fail('Could not find rewardBorderForAchievement() in firestore.rules');
  }
  final body = match.group(1)!;
  final pairPattern = RegExp(
    r"id\s*==\s*'([a-zA-Z0-9_]+)'\s*\?\s*'([a-zA-Z0-9_]+)'",
  );
  return {
    for (final m in pairPattern.allMatches(body)) m.group(1)!: m.group(2)!,
  };
}

void main() {
  late String rulesSource;

  setUpAll(() {
    final file = File('firestore.rules');
    if (!file.existsSync()) {
      fail(
        'Could not find firestore.rules relative to the test working directory',
      );
    }
    rulesSource = file.readAsStringSync();
  });

  test('achievementIds() lists exactly the Dart catalog ids', () {
    expect(
      _extractIdList(rulesSource, 'achievementIds').toSet(),
      achievementCatalog.map((a) => a.id).toSet(),
    );
  });

  test('profileBorderIds() lists exactly the Dart border catalog ids', () {
    expect(
      _extractIdList(rulesSource, 'profileBorderIds').toSet(),
      profileBorderCatalog.map((b) => b.id).toSet(),
    );
  });

  test('rewardBorderForAchievement matches Dart reward mappings', () {
    final rulesMap = _extractRewardMap(rulesSource);
    expect(rulesMap, achievementRewardBorderIds);
    for (final achievement in achievementCatalog) {
      expect(rulesMap[achievement.id], achievement.rewardBorderId);
    }
  });
}
