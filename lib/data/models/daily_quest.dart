import '../models/session.dart';
import '../models/training_prop.dart';

/// Category used only to enforce "never assign multiple X quests to the same
/// board" constraints during board generation. Not shown in the UI.
enum QuestCategory {
  sessionCount,
  duration,
  scoreThreshold,
  scoreCount,
  movementVariety,
  movementDifficulty,
  propUsage,
}

/// Reward tier. Every board has exactly 2 easy + 2 medium + 1 hard quest,
/// and fixed XP is derived purely from tier: easy=10, medium=15, hard=20.
enum QuestTier { easy, medium, hard }

extension QuestTierXp on QuestTier {
  int get xp => switch (this) {
    QuestTier.easy => 10,
    QuestTier.medium => 15,
    QuestTier.hard => 20,
  };
}

/// Current progress toward a quest's target, plus whether it is complete.
class QuestProgress {
  const QuestProgress({required this.current, required this.target});

  final int current;
  final int target;

  bool get completed => current >= target;
}

typedef QuestEvaluator = QuestProgress Function(List<Session> sessionsToday);

/// One catalog entry. Immutable and stateless — all "did the user complete
/// this" logic lives in [evaluate], which only reads [Session] fields that
/// already exist (rubric, durationSeconds, movementName, difficulty,
/// propType).
class QuestDefinition {
  const QuestDefinition({
    required this.id,
    required this.title,
    required this.category,
    required this.tier,
    required this.evaluate,
  });

  final String id;
  final String title;
  final QuestCategory category;
  final QuestTier tier;
  final QuestEvaluator evaluate;

  int get xp => tier.xp;
}

String _normalizedDifficulty(Session session) =>
    session.difficulty.trim().toLowerCase();

int _totalDurationSeconds(List<Session> sessions) =>
    sessions.fold<int>(0, (total, session) => total + session.durationSeconds);

/// Highest Assessment V2 rubric total (0..12) among [sessions].
///
/// Legacy Assessment V1 sessions carry a 0..100 percentage that is not
/// comparable to a rubric total, so they are ignored entirely rather than
/// rescaled.
int _bestRubricTotal(List<Session> sessions) {
  var best = 0;
  for (final session in sessions) {
    if (!session.isRubricAssessed) continue;
    final total = session.rubricTotal;
    if (total != null && total > best) best = total;
  }
  return best;
}

int _distinctMovementCount(List<Session> sessions) {
  final movements = <String>{};
  for (final session in sessions) {
    final normalized = session.movementName.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    movements.add(normalized);
  }
  return movements.length;
}

int _distinctPropCount(List<Session> sessions) {
  return sessions.map((session) => session.propType).toSet().length;
}

/// Count of Assessment V2 sessions whose rubric total reaches [threshold].
/// Legacy sessions never count.
int _sessionsAtOrAboveRubricTotal(List<Session> sessions, int threshold) =>
    sessions.where((session) {
      if (!session.isRubricAssessed) return false;
      final total = session.rubricTotal;
      return total != null && total >= threshold;
    }).length;

int _sessionsWithDifficulty(List<Session> sessions, String difficulty) =>
    sessions
        .where((session) => _normalizedDifficulty(session) == difficulty)
        .length;

int _sessionsWithProp(List<Session> sessions, TrainingProp prop) =>
    sessions.where((session) => session.propType == prop).length;

QuestProgress _capAtOne(int count) =>
    QuestProgress(current: count > 1 ? 1 : count, target: 1);

/// The full Phase 1 catalog: 18 quests, 6 easy / 7 medium / 5 hard.
///
/// Kept in sync with the duplicated id/tier/XP tables in `firestore.rules`
/// by `test/data/models/daily_quest_catalog_contract_test.dart` — security
/// rules cannot import Dart source, so this list and the rules' catalog
/// tables are two independent sources of truth that must be edited together.
final List<QuestDefinition> questCatalog = [
  // ---- Easy (10 XP) ----
  QuestDefinition(
    id: 'session_count_1',
    title: 'Complete 1 Practice Session',
    category: QuestCategory.sessionCount,
    tier: QuestTier.easy,
    evaluate: (sessions) => QuestProgress(current: sessions.length, target: 1),
  ),
  QuestDefinition(
    id: 'duration_10min',
    title: 'Practice for 10 Minutes Total',
    category: QuestCategory.duration,
    tier: QuestTier.easy,
    evaluate: (sessions) =>
        QuestProgress(current: _totalDurationSeconds(sessions), target: 600),
  ),
  QuestDefinition(
    id: 'score_70',
    title: 'Reach Competent in a Session',
    category: QuestCategory.scoreThreshold,
    tier: QuestTier.easy,
    evaluate: (sessions) =>
        QuestProgress(current: _bestRubricTotal(sessions), target: 7),
  ),
  QuestDefinition(
    id: 'two_movements',
    title: 'Practice 2 Different Movements',
    category: QuestCategory.movementVariety,
    tier: QuestTier.easy,
    evaluate: (sessions) =>
        QuestProgress(current: _distinctMovementCount(sessions), target: 2),
  ),
  QuestDefinition(
    id: 'practice_easy_movement',
    title: 'Complete an Easy-Difficulty Session',
    category: QuestCategory.movementDifficulty,
    tier: QuestTier.easy,
    evaluate: (sessions) =>
        _capAtOne(_sessionsWithDifficulty(sessions, 'easy')),
  ),
  QuestDefinition(
    id: 'use_shaker',
    title: 'Use the Cocktail Shaker',
    category: QuestCategory.propUsage,
    tier: QuestTier.easy,
    evaluate: (sessions) =>
        _capAtOne(_sessionsWithProp(sessions, TrainingProp.shaker)),
  ),

  // ---- Medium (15 XP) ----
  QuestDefinition(
    id: 'session_count_3',
    title: 'Complete 3 Practice Sessions',
    category: QuestCategory.sessionCount,
    tier: QuestTier.medium,
    evaluate: (sessions) => QuestProgress(current: sessions.length, target: 3),
  ),
  QuestDefinition(
    id: 'duration_20min',
    title: 'Practice for 20 Minutes Total',
    category: QuestCategory.duration,
    tier: QuestTier.medium,
    evaluate: (sessions) =>
        QuestProgress(current: _totalDurationSeconds(sessions), target: 1200),
  ),
  QuestDefinition(
    id: 'score_85',
    title: 'Reach Proficient in a Session',
    category: QuestCategory.scoreThreshold,
    tier: QuestTier.medium,
    evaluate: (sessions) =>
        QuestProgress(current: _bestRubricTotal(sessions), target: 10),
  ),
  QuestDefinition(
    id: 'sessions_above_70_x2',
    title: 'Competent in 2 Sessions',
    category: QuestCategory.scoreCount,
    tier: QuestTier.medium,
    evaluate: (sessions) => QuestProgress(
      current: _sessionsAtOrAboveRubricTotal(sessions, 7),
      target: 2,
    ),
  ),
  QuestDefinition(
    id: 'three_movements',
    title: 'Practice 3 Different Movements',
    category: QuestCategory.movementVariety,
    tier: QuestTier.medium,
    evaluate: (sessions) =>
        QuestProgress(current: _distinctMovementCount(sessions), target: 3),
  ),
  QuestDefinition(
    id: 'practice_medium_movement',
    title: 'Complete a Medium-Difficulty Session',
    category: QuestCategory.movementDifficulty,
    tier: QuestTier.medium,
    evaluate: (sessions) =>
        _capAtOne(_sessionsWithDifficulty(sessions, 'medium')),
  ),
  QuestDefinition(
    id: 'distinct_props_2',
    title: 'Use 2 Different Props Today',
    category: QuestCategory.propUsage,
    tier: QuestTier.medium,
    evaluate: (sessions) =>
        QuestProgress(current: _distinctPropCount(sessions), target: 2),
  ),

  // ---- Hard (20 XP) ----
  QuestDefinition(
    id: 'session_count_5',
    title: 'Complete 5 Practice Sessions',
    category: QuestCategory.sessionCount,
    tier: QuestTier.hard,
    evaluate: (sessions) => QuestProgress(current: sessions.length, target: 5),
  ),
  QuestDefinition(
    id: 'duration_30min',
    title: 'Practice for 30 Minutes Total',
    category: QuestCategory.duration,
    tier: QuestTier.hard,
    evaluate: (sessions) =>
        QuestProgress(current: _totalDurationSeconds(sessions), target: 1800),
  ),
  QuestDefinition(
    id: 'score_95',
    title: 'Reach Mastered in a Session',
    category: QuestCategory.scoreThreshold,
    tier: QuestTier.hard,
    evaluate: (sessions) =>
        QuestProgress(current: _bestRubricTotal(sessions), target: 12),
  ),
  QuestDefinition(
    id: 'practice_hard_movement',
    title: 'Complete a Hard-Difficulty Session',
    category: QuestCategory.movementDifficulty,
    tier: QuestTier.hard,
    evaluate: (sessions) =>
        _capAtOne(_sessionsWithDifficulty(sessions, 'hard')),
  ),
  QuestDefinition(
    id: 'use_bottle_and_shaker_combo',
    title: 'Complete a Bottle + Shaker Combo Session',
    category: QuestCategory.propUsage,
    tier: QuestTier.hard,
    evaluate: (sessions) =>
        _capAtOne(_sessionsWithProp(sessions, TrainingProp.bottleAndShaker)),
  ),
];

final Map<String, QuestDefinition> _questById = {
  for (final quest in questCatalog) quest.id: quest,
};

QuestDefinition? questById(String id) => _questById[id];

bool isKnownQuestId(String id) => _questById.containsKey(id);

/// Fixed XP for a catalog id, or `null` if [id] is not a known quest.
/// Never accept an XP amount supplied by a caller — always look it up here.
int? questXpFor(String id) => _questById[id]?.xp;
