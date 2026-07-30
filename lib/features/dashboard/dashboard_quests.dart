import '../../data/models/session.dart';

/// A single daily quest shown on the dashboard.
class DashboardQuest {
  const DashboardQuest({
    required this.id,
    required this.title,
    required this.xp,
    required this.completed,
    required this.isDailyFocus,
  });

  final String id;
  final String title;
  final int xp;
  final bool completed;

  /// Whether this quest is part of today's rotating daily trio.
  final bool isDailyFocus;
}

typedef _QuestDefinition = ({
  String id,
  String title,
  int xp,
  bool Function(List<Session> sessionsToday, int streakDays) isComplete,
});

const _questCanonicalOrder = [
  'complete_one_session',
  'complete_three_sessions',
  'score_80',
  'score_90',
  'two_movements',
  'train_two_minutes',
  'three_day_streak',
];

const _sessionCountQuests = {'complete_one_session', 'complete_three_sessions'};
const _scoreQuests = {'score_80', 'score_90'};

final List<_QuestDefinition> _questDefinitions = [
  (
    id: 'complete_one_session',
    title: 'Complete 1 Practice Session',
    xp: 10,
    isComplete: _completeOneSession,
  ),
  (
    id: 'complete_three_sessions',
    title: 'Complete 3 Practice Sessions',
    xp: 25,
    isComplete: _completeThreeSessions,
  ),
  (
    id: 'score_80',
    title: 'Score 80+ in a Session',
    xp: 15,
    isComplete: _scoreAtLeast80,
  ),
  (
    id: 'score_90',
    title: 'Score 90+ in a Session',
    xp: 30,
    isComplete: _scoreAtLeast90,
  ),
  (
    id: 'two_movements',
    title: 'Practice 2 Different Movements',
    xp: 20,
    isComplete: _twoDistinctMovements,
  ),
  (
    id: 'train_two_minutes',
    title: 'Train for 2 Minutes Total',
    xp: 20,
    isComplete: _trainTwoMinutes,
  ),
  (
    id: 'three_day_streak',
    title: 'Maintain a 3-Day Streak',
    xp: 25,
    isComplete: _threeDayStreak,
  ),
];

final Map<String, _QuestDefinition> _questDefinitionById = {
  for (final definition in _questDefinitions) definition.id: definition,
};

final List<List<String>> _validDailyQuestSelections =
    _buildValidDailyQuestSelections();

List<List<String>> _buildValidDailyQuestSelections() {
  final selections = <List<String>>[];
  for (var i = 0; i < _questCanonicalOrder.length; i++) {
    for (var j = i + 1; j < _questCanonicalOrder.length; j++) {
      for (var k = j + 1; k < _questCanonicalOrder.length; k++) {
        final selection = [
          _questCanonicalOrder[i],
          _questCanonicalOrder[j],
          _questCanonicalOrder[k],
        ];
        if (_isValidDailyQuestSelection(selection)) {
          selections.add(selection);
        }
      }
    }
  }
  return selections;
}

bool _isValidDailyQuestSelection(List<String> questIds) {
  if (questIds.length != 3) return false;
  final sessionCountSelected = questIds
      .where(_sessionCountQuests.contains)
      .length;
  if (sessionCountSelected > 1) return false;
  final scoreSelected = questIds.where(_scoreQuests.contains).length;
  if (scoreSelected > 1) return false;
  return true;
}

int _localDateSeed(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

/// Deterministically picks three quest IDs for the given local calendar day.
List<String> selectDailyQuestIds(DateTime date) {
  if (_validDailyQuestSelections.isEmpty) {
    return const [];
  }
  final index = _localDateSeed(date) % _validDailyQuestSelections.length;
  return _validDailyQuestSelections[index];
}

List<DashboardQuest> buildDailyDashboardQuests({
  required List<Session> sessionsToday,
  required int streakDays,
  required DateTime date,
}) {
  final selectedIds = selectDailyQuestIds(date);
  final selectedIdSet = selectedIds.toSet();
  return [
    for (final id in selectedIds)
      _buildQuest(
        definition: _questDefinitionById[id]!,
        sessionsToday: sessionsToday,
        streakDays: streakDays,
        isDailyFocus: true,
      ),
    for (final id in _questCanonicalOrder)
      if (!selectedIdSet.contains(id))
        _buildQuest(
          definition: _questDefinitionById[id]!,
          sessionsToday: sessionsToday,
          streakDays: streakDays,
          isDailyFocus: false,
        ),
  ];
}

DashboardQuest _buildQuest({
  required _QuestDefinition definition,
  required List<Session> sessionsToday,
  required int streakDays,
  required bool isDailyFocus,
}) {
  return DashboardQuest(
    id: definition.id,
    title: definition.title,
    xp: definition.xp,
    completed: definition.isComplete(sessionsToday, streakDays),
    isDailyFocus: isDailyFocus,
  );
}

bool _completeOneSession(List<Session> sessionsToday, int streakDays) =>
    sessionsToday.isNotEmpty;

bool _completeThreeSessions(List<Session> sessionsToday, int streakDays) =>
    sessionsToday.length >= 3;

bool _scoreAtLeast80(List<Session> sessionsToday, int streakDays) =>
    sessionsToday.any((session) => session.score >= 80);

bool _scoreAtLeast90(List<Session> sessionsToday, int streakDays) =>
    sessionsToday.any((session) => session.score >= 90);

bool _twoDistinctMovements(List<Session> sessionsToday, int streakDays) {
  final movements = <String>{};
  for (final session in sessionsToday) {
    final normalized = session.movementName.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    movements.add(normalized);
  }
  return movements.length >= 2;
}

bool _trainTwoMinutes(List<Session> sessionsToday, int streakDays) {
  var totalSeconds = 0;
  for (final session in sessionsToday) {
    totalSeconds += session.durationSeconds < 0 ? 0 : session.durationSeconds;
  }
  return totalSeconds >= 120;
}

bool _threeDayStreak(List<Session> sessionsToday, int streakDays) =>
    streakDays >= 3;
