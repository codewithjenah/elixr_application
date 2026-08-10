import 'package:elixr_application/core/utils/manila_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManilaDay', () {
    test(
      'an instant shortly after UTC midnight maps to the next Manila day',
      () {
        // 2026-08-03T20:00:00Z + 8h = 2026-08-04T04:00 Manila.
        final nowUtc = DateTime.utc(2026, 8, 3, 20, 0, 0);
        expect(ManilaDay.dayKeyFor(nowUtc), '20260804');
        expect(
          ManilaDay.dayStartUtcFor(nowUtc),
          DateTime.utc(2026, 8, 3, 16, 0, 0),
        );
      },
    );

    test('an instant later the same UTC day maps to the same Manila day', () {
      // 2026-08-04T10:00:00Z + 8h = 2026-08-04T18:00 Manila: same day as above.
      final nowUtc = DateTime.utc(2026, 8, 4, 10, 0, 0);
      expect(ManilaDay.dayKeyFor(nowUtc), '20260804');
      expect(
        ManilaDay.dayStartUtcFor(nowUtc),
        DateTime.utc(2026, 8, 3, 16, 0, 0),
      );
    });

    test('just before the Manila boundary is the previous Manila day', () {
      // 2026-08-03T15:59:59Z + 8h = 2026-08-03T23:59:59 Manila.
      final nowUtc = DateTime.utc(2026, 8, 3, 15, 59, 59);
      expect(ManilaDay.dayKeyFor(nowUtc), '20260803');
      expect(
        ManilaDay.dayStartUtcFor(nowUtc),
        DateTime.utc(2026, 8, 2, 16, 0, 0),
      );
    });

    test('exactly at the Manila boundary rolls to the new day', () {
      // 2026-08-03T16:00:00Z + 8h = 2026-08-04T00:00:00 Manila.
      final nowUtc = DateTime.utc(2026, 8, 3, 16, 0, 0);
      expect(ManilaDay.dayKeyFor(nowUtc), '20260804');
      expect(
        ManilaDay.dayStartUtcFor(nowUtc),
        DateTime.utc(2026, 8, 3, 16, 0, 0),
      );
    });

    test('is deterministic across repeated calls with the same instant', () {
      final nowUtc = DateTime.utc(2026, 1, 15, 3, 30);
      final firstKey = ManilaDay.dayKeyFor(nowUtc);
      final secondKey = ManilaDay.dayKeyFor(nowUtc);
      final firstStart = ManilaDay.dayStartUtcFor(nowUtc);
      final secondStart = ManilaDay.dayStartUtcFor(nowUtc);

      expect(firstKey, secondKey);
      expect(firstStart, secondStart);
    });

    test('dayKeyEquals compares day keys, not DateTime values', () {
      expect(ManilaDay.dayKeyEquals('20260804', '20260804'), isTrue);
      expect(ManilaDay.dayKeyEquals('20260804', '20260805'), isFalse);
    });

    test('single-digit month and day are zero-padded', () {
      final nowUtc = DateTime.utc(2026, 1, 5, 1, 0);
      expect(ManilaDay.dayKeyFor(nowUtc), '20260105');
      expect(ManilaDay.monthKeyFor(nowUtc), '202601');
    });

    test('month key rolls over at the Manila month boundary', () {
      expect(
        ManilaDay.monthKeyFor(DateTime.utc(2026, 7, 31, 15, 59, 59)),
        '202607',
      );
      expect(ManilaDay.monthKeyFor(DateTime.utc(2026, 7, 31, 16)), '202608');
    });

    test('month key rolls over across the Manila year boundary', () {
      expect(
        ManilaDay.monthKeyFor(DateTime.utc(2026, 12, 31, 15, 59, 59)),
        '202612',
      );
      expect(ManilaDay.monthKeyFor(DateTime.utc(2026, 12, 31, 16)), '202701');
    });

    test('monthKeyFromDayKey validates and derives the board month', () {
      expect(ManilaDay.monthKeyFromDayKey('20260804'), '202608');
      expect(
        () => ManilaDay.monthKeyFromDayKey('20260230'),
        throwsFormatException,
      );
    });

    test(
      'enumerateDailyQuestBoardIds includes endpoints for a short range',
      () {
        final ids = ManilaDay.enumerateDailyQuestBoardIds(
          userId: 'alice',
          createdAtUtc: DateTime.utc(2026, 1, 1, 0),
          nowUtc: DateTime.utc(2026, 1, 2, 0),
        );
        expect(ids, ['alice_20260101', 'alice_20260102']);
      },
    );

    test('boardEnumerationFallbackStartUtc is 2024-01-01 Manila', () {
      expect(
        ManilaDay.dayKeyFor(ManilaDay.boardEnumerationFallbackStartUtc),
        '20240101',
      );
    });
  });
}
