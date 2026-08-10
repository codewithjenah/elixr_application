import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'period presentation and Firestore fields are selected consistently',
    () {
      expect(LeaderboardPeriod.today.selectorLabel, 'Today');
      expect(LeaderboardPeriod.today.xpHeading, 'XP today');
      expect(LeaderboardPeriod.today.xpField, 'daily_xp');
      expect(LeaderboardPeriod.thisMonth.selectorLabel, 'This month');
      expect(LeaderboardPeriod.thisMonth.bestScoreField, 'monthly_best_score');
      expect(LeaderboardPeriod.allTime.selectorLabel, 'All time');
      expect(LeaderboardPeriod.allTime.xpField, 'total_xp');
      expect(LeaderboardPeriod.allTime.keyField, isNull);
    },
  );

  test('period keys use Manila day and month boundaries', () {
    final beforeBoundary = DateTime.utc(2026, 7, 31, 15, 59, 59);
    final afterBoundary = DateTime.utc(2026, 7, 31, 16);

    expect(LeaderboardPeriod.today.keyFor(beforeBoundary), '20260731');
    expect(LeaderboardPeriod.today.keyFor(afterBoundary), '20260801');
    expect(LeaderboardPeriod.thisMonth.keyFor(beforeBoundary), '202607');
    expect(LeaderboardPeriod.thisMonth.keyFor(afterBoundary), '202608');
    expect(LeaderboardPeriod.allTime.keyFor(afterBoundary), isNull);
  });
}
