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

  /// Whether [dayKeyA] and [dayKeyB] denote the same Manila calendar day.
  /// Prefer this over comparing raw [DateTime] values.
  static bool dayKeyEquals(String dayKeyA, String dayKeyB) =>
      dayKeyA == dayKeyB;
}
