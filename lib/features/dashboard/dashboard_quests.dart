import '../../data/models/daily_quest.dart';
import '../../data/models/daily_quest_board.dart';
import '../../data/models/session.dart';

/// A single quest tile ready for the dashboard UI: catalog metadata plus
/// progress evaluated against the board's Manila-day session window.
class DashboardQuest {
  const DashboardQuest({
    required this.id,
    required this.title,
    required this.xp,
    required this.tier,
    required this.current,
    required this.target,
    required this.completed,
  });

  final String id;
  final String title;
  final int xp;
  final QuestTier tier;
  final int current;
  final int target;
  final bool completed;
}

/// Builds the current active quest list (at most 3, always board order —
/// which is exactly one easy + one medium + one hard while unclaimed) for
/// display.
///
/// [sessions] should be the user's full session history, *not* a
/// device-local "today" filter: quest progress must be evaluated against
/// the board's persisted Manila-day window (`board.dayStart` .. `+24h`),
/// which this function enforces itself via [sessionsWithinBoardWindow]
/// rather than trusting a caller-supplied "sessions today" list.
List<DashboardQuest> buildActiveDashboardQuests({
  required DailyQuestBoard board,
  required Set<String> claimedQuestIds,
  required List<Session> sessions,
}) {
  final windowed = sessionsWithinBoardWindow(board, sessions);
  final activeIds = board.questIds
      .where((id) => !claimedQuestIds.contains(id))
      .take(3);

  final quests = <DashboardQuest>[];
  for (final id in activeIds) {
    final quest = questById(id);
    if (quest != null) {
      quests.add(_buildQuest(quest, windowed));
    }
  }
  return quests;
}

/// Whether every quest on [board] has been claimed today.
bool isDailyBoardComplete({
  required DailyQuestBoard board,
  required Set<String> claimedQuestIds,
}) {
  return board.questIds.every(claimedQuestIds.contains);
}

DashboardQuest _buildQuest(
  QuestDefinition quest,
  List<Session> windowedSessions,
) {
  final progress = quest.evaluate(windowedSessions);
  return DashboardQuest(
    id: quest.id,
    title: quest.title,
    xp: quest.xp,
    tier: quest.tier,
    current: progress.current,
    target: progress.target,
    completed: progress.completed,
  );
}
