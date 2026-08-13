/// Centralized Asia/Manila calendar-day calculation for the daily quest
/// board (see [Persistent Daily Quest System]).
///
/// The board's "real day" boundary is anchored to Asia/Manila (UTC+8)
/// rather than the device's local timezone so that the Firestore security
/// rules (which only trust the server-stamped `request.time`, never a
/// client-supplied clock) can independently re-derive the exact same
/// `day_key`/`day_start` and reject boards or claims for any other day.
/// See `firestore.rules` (`manilaDayStart`, `manilaDayKey`) for the
/// server-side mirror of this logic.
///
/// Every function here takes an explicit `nowUtc` parameter instead of
/// calling `DateTime.now()` internally — this *is* the "injectable clock":
/// production call sites pass `DateTime.now().toUtc()`, tests pass a fixed
/// instant.
abstract final class ManilaDay {
  static const _manilaOffset = Duration(hours: 8);

  static DateTime _manilaCalendarDate(DateTime nowUtc) {
    final shifted = nowUtc.toUtc().add(_manilaOffset);
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }

  /// The UTC instant of 00:00 Asia/Manila for the Manila calendar day that
  /// contains [nowUtc].
  static DateTime dayStartUtcFor(DateTime nowUtc) =>
      _manilaCalendarDate(nowUtc).subtract(_manilaOffset);

  /// `'yyyyMMdd'` for the Manila calendar day that contains [nowUtc].
  static String dayKeyFor(DateTime nowUtc) {
    final d = _manilaCalendarDate(nowUtc);
    return '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// `'yyyyMM'` for the Manila calendar month that contains [nowUtc].
  static String monthKeyFor(DateTime nowUtc) {
    final d = _manilaCalendarDate(nowUtc);
    return '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}';
  }

  /// Derives a `'yyyyMM'` month key from a validated `'yyyyMMdd'` day key.
  ///
  /// Daily quest awards use the verified board's day key as their source of
  /// period identity. Keeping this conversion here avoids duplicating date-key
  /// formatting in repositories.
  static String monthKeyFromDayKey(String dayKey) {
    if (!_isValidDayKey(dayKey)) {
      throw FormatException('Invalid Manila day key', dayKey);
    }
    return dayKey.substring(0, 6);
  }

  /// Whether [dayKeyA] and [dayKeyB] denote the same Manila calendar day.
  /// Prefer this over comparing raw [DateTime] values.
  static bool dayKeyEquals(String dayKeyA, String dayKeyB) =>
      dayKeyA == dayKeyB;

  static bool _isValidDayKey(String value) {
    if (!RegExp(r'^\d{8}$').hasMatch(value)) return false;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(4, 6));
    final day = int.parse(value.substring(6, 8));
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;

    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  /// Fixed fallback start when a user document has no usable `created_at`
  /// (2024-01-01 00:00 Asia/Manila) for account self-erasure board enumeration.
  static final DateTime boardEnumerationFallbackStartUtc = DateTime.utc(
    2023,
    12,
    31,
    16,
  );

  /// Builds `daily_quest_boards` document ids from [createdAtUtc] through
  /// [nowUtc] (inclusive Manila days): `{userId}_{yyyyMMdd}`.
  ///
  /// Used for RA 10173 account erasure because boards cannot be listed
  /// (`allow list: if false`).
  static List<String> enumerateDailyQuestBoardIds({
    required String userId,
    required DateTime createdAtUtc,
    required DateTime nowUtc,
  }) {
    if (userId.isEmpty) return const [];

    var start = dayStartUtcFor(createdAtUtc);
    final end = dayStartUtcFor(nowUtc);
    if (start.isAfter(end)) {
      start = end;
    }

    final ids = <String>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      ids.add('${userId}_${dayKeyFor(cursor)}');
      cursor = cursor.add(const Duration(days: 1));
    }
    return ids;
  }
}
