import '../models/session.dart';
import 'daily_quest.dart';
import 'daily_quest_eligibility.dart';

/// Persisted per-user, per-real-day quest board. Immutable after creation —
/// `firestore.rules` disallows `update`/`delete` entirely on
/// `daily_quest_boards/{boardId}`.
class DailyQuestBoard {
  const DailyQuestBoard({
    required this.userId,
    required this.dayKey,
    required this.dayStart,
    required this.questIds,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;

  /// `'yyyyMMdd'` for the Manila calendar day this board belongs to.
  final String dayKey;

  /// UTC instant of 00:00 Asia/Manila for [dayKey] (see `ManilaDay`).
  final DateTime dayStart;

  /// Exactly 5 catalog ids: 2 easy + 2 medium + 1 hard, ordered so the first
  /// 3 are always exactly one easy + one medium + one hard.
  final List<String> questIds;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String documentId(String userId, String dayKey) => '${userId}_$dayKey';

  String get id => documentId(userId, dayKey);

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'day_key': dayKey,
      'day_start': dayStart,
      'quest_ids': questIds,
    };
  }

  static DailyQuestBoard? tryFromMap(Map<String, dynamic> map) {
    final userId = map['user_id'];
    final dayKey = map['day_key'];
    final dayStart = _readDateTime(map['day_start']);
    final questIds = map['quest_ids'];
    if (userId is! String ||
        userId.isEmpty ||
        dayKey is! String ||
        dayKey.isEmpty ||
        dayStart == null ||
        questIds is! List) {
      return null;
    }
    return DailyQuestBoard(
      userId: userId,
      dayKey: dayKey,
      dayStart: dayStart,
      questIds: questIds.whereType<String>().toList(growable: false),
      createdAt: _readDateTime(map['created_at']),
      updatedAt: _readDateTime(map['updated_at']),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    // Timestamp-like objects expose toDate() in cloud_firestore.
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        return toDate() as DateTime?;
      }
    } catch (_) {
      // Fall through for plain maps in unit tests.
    }
    return null;
  }
}

// Derived from questCatalog (not hand-duplicated) so there is exactly one
// Dart-side source of truth for tier/category membership; only
// firestore.rules (which cannot import Dart) needs its own copy, guarded by
// the contract test.
Set<String> _idsWithCategory(QuestCategory category) =>
    questCatalog.where((q) => q.category == category).map((q) => q.id).toSet();

final _sessionCountIds = _idsWithCategory(QuestCategory.sessionCount);
final _durationIds = _idsWithCategory(QuestCategory.duration);
final _scoreThresholdIds = _idsWithCategory(QuestCategory.scoreThreshold);

typedef _TierCombo = ({
  List<String> easyPair,
  List<String> mediumPair,
  String hard,
});

final Map<int, List<_TierCombo>> _validCombosByLevel = {};

/// Clamps a trainee level for board generation: below 1 behaves as Level 1,
/// Level 20+ uses the personally unlocked pool for Level 20.
int effectiveQuestGenerationLevel(int currentLevel) {
  if (currentLevel < 1) return 1;
  if (currentLevel > 20) return 20;
  return currentLevel;
}

List<String> _idsWithTierAtLevel(
  QuestTier tier,
  int level,
  DailyQuestUnlockPool pool,
) => questCatalog
    .where(
      (q) =>
          q.tier == tier &&
          q.minimumLevel <= level &&
          isEligibleForDailyQuestGeneration(q, pool),
    )
    .map((q) => q.id)
    .toList();

int _categoryConflictCount(List<String> ids, Set<String> category) =>
    ids.where(category.contains).length;

bool _isValidCombo(
  List<String> easyPair,
  List<String> mediumPair,
  String hard,
) {
  final all = [...easyPair, ...mediumPair, hard];
  return _categoryConflictCount(all, _sessionCountIds) <= 1 &&
      _categoryConflictCount(all, _durationIds) <= 1 &&
      _categoryConflictCount(all, _scoreThresholdIds) <= 1;
}

List<_TierCombo> _buildValidCombos({
  required List<String> easyIds,
  required List<String> mediumIds,
  required List<String> hardIds,
}) {
  final combos = <_TierCombo>[];
  for (var i = 0; i < easyIds.length; i++) {
    for (var j = i + 1; j < easyIds.length; j++) {
      final easyPair = [easyIds[i], easyIds[j]];
      for (var k = 0; k < mediumIds.length; k++) {
        for (var l = k + 1; l < mediumIds.length; l++) {
          final mediumPair = [mediumIds[k], mediumIds[l]];
          for (final hard in hardIds) {
            if (_isValidCombo(easyPair, mediumPair, hard)) {
              combos.add((
                easyPair: easyPair,
                mediumPair: mediumPair,
                hard: hard,
              ));
            }
          }
        }
      }
    }
  }
  return combos;
}

List<_TierCombo> _validCombosForLevel(int level) {
  return _validCombosByLevel.putIfAbsent(level, () {
    final pool = DailyQuestUnlockPool.fromPersonalLevel(level);
    return _buildValidCombos(
      easyIds: _idsWithTierAtLevel(QuestTier.easy, level, pool),
      mediumIds: _idsWithTierAtLevel(QuestTier.medium, level, pool),
      hardIds: _idsWithTierAtLevel(QuestTier.hard, level, pool),
    );
  });
}

/// Deterministic, restart-safe 32-bit-masked djb2-style hash. Never uses
/// `Object.hashCode` (not guaranteed stable across runs) or `dart:math`
/// `Random` (not restart-safe).
int stableHash32(String input) {
  var hash = 5381;
  for (final unit in input.codeUnits) {
    hash = ((hash << 5) + hash + unit) & 0xFFFFFFFF;
  }
  return hash;
}

/// Deterministically picks 5 quest ids for [userId] on the Manila calendar
/// day identified by [dayKey] at [currentLevel]: exactly 2 easy + 2 medium
/// + 1 hard, at most one quest per conflicting category (session count /
/// duration / single score threshold), ordered so the first 3 are exactly
/// Easy → Medium → Hard (the "active" slots) and the last 2 are the reserve
/// easy/medium (never an arbitrary rotation of the whole board).
///
/// Candidates must satisfy both [QuestDefinition.minimumLevel] (coarse
/// prerequisite) and [isEligibleForDailyQuestGeneration] against the
/// trainee's personally unlocked practice pool. Same (userId, dayKey,
/// effective level) always yields the same 5 ids, in the same order,
/// across restarts because the unlock pool is a pure function of level.
/// Different users typically yield different boards on the same day.
List<String> generateDailyQuestIds({
  required String userId,
  required String dayKey,
  required int currentLevel,
}) {
  final effectiveLevel = effectiveQuestGenerationLevel(currentLevel);
  final combos = _validCombosForLevel(effectiveLevel);
  if (combos.isEmpty) {
    throw StateError(
      'No valid daily quest board exists for level $effectiveLevel',
    );
  }
  final seed = '$userId|$dayKey|$effectiveLevel';
  final comboIndex = stableHash32(seed) % combos.length;
  final combo = combos[comboIndex];

  final orderSeed = stableHash32('$seed|order');
  final activeEasyIndex = orderSeed % 2;
  final activeMediumIndex = (orderSeed ~/ 2) % 2;

  final activeEasy = combo.easyPair[activeEasyIndex];
  final reserveEasy = combo.easyPair[1 - activeEasyIndex];
  final activeMedium = combo.mediumPair[activeMediumIndex];
  final reserveMedium = combo.mediumPair[1 - activeMediumIndex];

  return [activeEasy, activeMedium, combo.hard, reserveEasy, reserveMedium];
}

/// Sessions strictly inside the board's persisted Manila-day window
/// (`board.dayStart <= session.createdAt < board.dayStart + 24h`).
///
/// Quest evaluators must use this instead of the dashboard's device-local
/// "sessions today" filter — the board's window is the one both the client
/// and `firestore.rules` agree on (server-time-anchored), so quest progress
/// stays consistent with what can actually be claimed. Sessions with a
/// missing or unparseable `createdAt` never count.
List<Session> sessionsWithinBoardWindow(
  DailyQuestBoard board,
  List<Session> sessions,
) {
  final windowEnd = board.dayStart.add(const Duration(hours: 24));
  return sessions
      .where((session) {
        final raw = session.createdAt;
        if (raw == null) return false;
        final createdAt = DateTime.tryParse(raw);
        if (createdAt == null) return false;
        final utc = createdAt.toUtc();
        return !utc.isBefore(board.dayStart) && utc.isBefore(windowEnd);
      })
      .toList(growable: false);
}
