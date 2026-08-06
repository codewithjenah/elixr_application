import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog IDs are unique', () {
    final ids = profileBorderCatalog.map((b) => b.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('every achievement reward maps to a known border', () {
    for (final achievement in achievementCatalog) {
      expect(
        isKnownProfileBorderId(achievement.rewardBorderId),
        isTrue,
        reason: achievement.id,
      );
      expect(
        rewardBorderForAchievement(achievement.id),
        achievement.rewardBorderId,
      );
    }
  });

  test('every border is obtainable from exactly one achievement', () {
    final rewardCounts = <String, int>{};
    for (final borderId in achievementRewardBorderIds.values) {
      rewardCounts[borderId] = (rewardCounts[borderId] ?? 0) + 1;
    }
    for (final border in profileBorderCatalog) {
      expect(
        rewardCounts[border.id],
        1,
        reason: '${border.id} should be rewarded by exactly one achievement',
      );
    }
    expect(profileBorderCatalog, hasLength(achievementCatalog.length));
  });

  test('unknown IDs return null safely', () {
    expect(profileBorderById('nope'), isNull);
    expect(isKnownProfileBorderId('nope'), isFalse);
    expect(rewardBorderForAchievement('nope'), isNull);
  });

  test('every catalog border has presentation configuration', () {
    for (final border in profileBorderCatalog) {
      expect(border.visualStyle, isNotNull);
      expect(border.motionStyle, isNotNull);
      expect(border.ornamentExtent, greaterThan(0));
      expect(border.animationDurationMs, inInclusiveRange(3000, 6000));
      expect(border.rarityLabel, isNotEmpty);
    }
  });
}
