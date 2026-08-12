import 'leaderboard_entry.dart';
import 'profile_border.dart';
import 'session.dart';
import 'training_prop.dart';

enum AchievementCategory {
  sessions,
  score,
  exploration,
  consistency,
  specialization,
}

enum AchievementState { locked, inProgress, claimable, claimed }

class AchievementProgress {
  const AchievementProgress({
    required this.current,
    required this.target,
    required this.completed,
  });

  final int current;
  final int target;
  final bool completed;

  double get normalizedProgress {
    if (target <= 0) return completed ? 1.0 : 0.0;
    final ratio = current / target;
    if (ratio < 0) return 0.0;
    if (ratio > 1) return 1.0;
    return ratio;
  }
}

typedef AchievementEvaluator =
    AchievementProgress Function(
      List<Session> sessions,
      LeaderboardEntry? leaderboardEntry,
    );

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.rewardBorderId,
    required this.target,
    required this.progressionOrder,
    required this.evaluator,
  });

  final String id;
  final String title;
  final String description;
  final AchievementCategory category;
  final String rewardBorderId;
  final int target;

  /// Presentation progression: lower values are easier / earlier.
  /// Independent of catalog list order and of movement Easy/Medium/Hard.
  final int progressionOrder;
  final AchievementEvaluator evaluator;
}

/// Deterministic easiest-to-hardest ordering for achievement presentation.
int compareAchievementsByProgression(
  AchievementDefinition a,
  AchievementDefinition b,
) {
  final byOrder = a.progressionOrder.compareTo(b.progressionOrder);
  if (byOrder != 0) return byOrder;
  return a.id.compareTo(b.id);
}

class AchievementViewData {
  const AchievementViewData({
    required this.definition,
    required this.progress,
    required this.state,
  });

  final AchievementDefinition definition;
  final AchievementProgress progress;
  final AchievementState state;
}

String normalizeLabel(String value) => value.trim().toLowerCase();

int _sessionCount(List<Session> sessions, LeaderboardEntry? entry) {
  final historyCount = sessions.length;
  final boardCount = entry?.sessionsCompleted ?? 0;
  return historyCount >= boardCount ? historyCount : boardCount;
}

AchievementProgress _countProgress(int current, int target) {
  final clamped = current < 0 ? 0 : current;
  return AchievementProgress(
    current: clamped > target ? target : clamped,
    target: target,
    completed: clamped >= target,
  );
}

DateTime? _parseSessionDay(Session session) {
  final raw = session.createdAt;
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Longest consecutive calendar-day streak ending on the most recent session day.
int _longestEndingStreak(List<Session> sessions) {
  final days = <DateTime>{};
  for (final session in sessions) {
    final day = _parseSessionDay(session);
    if (day != null) days.add(day);
  }
  if (days.isEmpty) return 0;

  final sorted = days.toList()..sort();
  var best = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].difference(sorted[i - 1]).inDays;
    if (gap == 1) {
      run += 1;
      if (run > best) best = run;
    } else if (gap > 1) {
      run = 1;
    }
  }
  return best;
}

AchievementProgress _sessionsMilestone(
  List<Session> sessions,
  LeaderboardEntry? entry,
  int target,
) {
  return _countProgress(_sessionCount(sessions, entry), target);
}

/// Best Assessment V2 rubric total (0..12) reached in [sessions].
///
/// Deliberately ignores [LeaderboardEntry.bestScore]: that aggregate is a
/// frozen legacy 0..100 percentage and is not comparable to a rubric total.
/// Legacy V1 sessions are ignored for the same reason.
AchievementProgress _bestRubricTotalAtLeast(
  List<Session> sessions,
  int threshold,
) {
  var best = 0;
  for (final session in sessions) {
    if (!session.isRubricAssessed) continue;
    final total = session.rubricTotal;
    if (total != null && total > best) best = total;
  }
  return AchievementProgress(
    current: best > threshold ? threshold : best,
    target: threshold,
    completed: best >= threshold,
  );
}

AchievementProgress _distinctMovements(List<Session> sessions, int target) {
  final names = <String>{};
  for (final session in sessions) {
    final name = normalizeLabel(session.movementName);
    if (name.isNotEmpty) names.add(name);
  }
  return _countProgress(names.length, target);
}

AchievementProgress _allDifficulties(List<Session> sessions) {
  final found = <String>{};
  for (final session in sessions) {
    final d = normalizeLabel(session.difficulty);
    if (d == 'easy' || d == 'medium' || d == 'hard') {
      found.add(d);
    }
  }
  final current = found.length;
  return AchievementProgress(
    current: current > 3 ? 3 : current,
    target: 3,
    completed: found.containsAll({'easy', 'medium', 'hard'}),
  );
}

AchievementProgress _weekStreak(List<Session> sessions) {
  return _countProgress(_longestEndingStreak(sessions), 7);
}

AchievementProgress _bottleInTinSpecialist(List<Session> sessions) {
  final matching = sessions.where((session) {
    return normalizeLabel(session.movementName) == 'bottle in a tin' &&
        session.propType == TrainingProp.bottleAndShaker;
  }).length;
  return _countProgress(matching, 5);
}

final List<AchievementDefinition>
achievementCatalog = List<AchievementDefinition>.unmodifiable(
  <AchievementDefinition>[
    AchievementDefinition(
      id: 'first_steps',
      title: 'First Steps',
      description: 'Complete 1 training session.',
      category: AchievementCategory.sessions,
      rewardBorderId: achievementRewardBorderIds['first_steps']!,
      target: 1,
      progressionOrder: 1,
      evaluator: (sessions, entry) => _sessionsMilestone(sessions, entry, 1),
    ),
    AchievementDefinition(
      id: 'getting_started',
      title: 'Getting Started',
      description: 'Complete 10 training sessions.',
      category: AchievementCategory.sessions,
      rewardBorderId: achievementRewardBorderIds['getting_started']!,
      target: 10,
      progressionOrder: 2,
      evaluator: (sessions, entry) => _sessionsMilestone(sessions, entry, 10),
    ),
    AchievementDefinition(
      id: 'flair_regular',
      title: 'Flair Regular',
      description: 'Complete 50 training sessions.',
      category: AchievementCategory.sessions,
      rewardBorderId: achievementRewardBorderIds['flair_regular']!,
      target: 50,
      progressionOrder: 6,
      evaluator: (sessions, entry) => _sessionsMilestone(sessions, entry, 50),
    ),
    AchievementDefinition(
      id: 'century_club',
      title: 'Century Club',
      description: 'Complete 100 training sessions.',
      category: AchievementCategory.sessions,
      rewardBorderId: achievementRewardBorderIds['century_club']!,
      target: 100,
      progressionOrder: 10,
      evaluator: (sessions, entry) => _sessionsMilestone(sessions, entry, 100),
    ),
    AchievementDefinition(
      id: 'sharp_pour',
      title: 'Sharp Pour',
      description: 'Reach Proficient (10 of 12) in a session.',
      category: AchievementCategory.score,
      rewardBorderId: achievementRewardBorderIds['sharp_pour']!,
      target: 10,
      progressionOrder: 4,
      evaluator: (sessions, entry) => _bestRubricTotalAtLeast(sessions, 10),
    ),
    AchievementDefinition(
      id: 'perfect_serve',
      title: 'Perfect Serve',
      description: 'Reach Mastered with a perfect 12 of 12 in a session.',
      category: AchievementCategory.score,
      rewardBorderId: achievementRewardBorderIds['perfect_serve']!,
      target: 12,
      progressionOrder: 9,
      evaluator: (sessions, entry) => _bestRubricTotalAtLeast(sessions, 12),
    ),
    AchievementDefinition(
      id: 'movement_explorer',
      title: 'Movement Explorer',
      description: 'Practice at least 5 distinct movements.',
      category: AchievementCategory.exploration,
      rewardBorderId: achievementRewardBorderIds['movement_explorer']!,
      target: 5,
      progressionOrder: 3,
      evaluator: (sessions, entry) => _distinctMovements(sessions, 5),
    ),
    AchievementDefinition(
      id: 'versatility_master',
      title: 'Versatility Master',
      description:
          'Complete at least one Easy, one Medium, and one Hard session.',
      category: AchievementCategory.exploration,
      rewardBorderId: achievementRewardBorderIds['versatility_master']!,
      target: 3,
      progressionOrder: 7,
      evaluator: (sessions, entry) => _allDifficulties(sessions),
    ),
    AchievementDefinition(
      id: 'week_warrior',
      title: 'Week Warrior',
      description: 'Practice on 7 consecutive calendar days.',
      category: AchievementCategory.consistency,
      rewardBorderId: achievementRewardBorderIds['week_warrior']!,
      target: 7,
      progressionOrder: 5,
      evaluator: (sessions, entry) => _weekStreak(sessions),
    ),
    AchievementDefinition(
      id: 'bottle_in_tin_specialist',
      title: 'Bottle in a Tin Specialist',
      description:
          'Complete 5 Bottle in a Tin sessions using Bottle + Cocktail Shaker.',
      category: AchievementCategory.specialization,
      rewardBorderId: achievementRewardBorderIds['bottle_in_tin_specialist']!,
      target: 5,
      progressionOrder: 8,
      evaluator: (sessions, entry) => _bottleInTinSpecialist(sessions),
    ),
  ],
);

AchievementDefinition? achievementById(String id) {
  for (final achievement in achievementCatalog) {
    if (achievement.id == id) return achievement;
  }
  return null;
}

bool isKnownAchievementId(String id) => achievementById(id) != null;

AchievementState resolveAchievementState({
  required AchievementProgress progress,
  required bool isClaimed,
}) {
  if (isClaimed) return AchievementState.claimed;
  if (progress.completed) return AchievementState.claimable;
  if (progress.current > 0) return AchievementState.inProgress;
  return AchievementState.locked;
}

AchievementViewData buildAchievementViewData({
  required AchievementDefinition definition,
  required List<Session> sessions,
  required LeaderboardEntry? leaderboardEntry,
  required Set<String> claimedAchievementIds,
}) {
  final isClaimed = claimedAchievementIds.contains(definition.id);
  final progress = definition.evaluator(sessions, leaderboardEntry);
  return AchievementViewData(
    definition: definition,
    progress: progress,
    state: resolveAchievementState(progress: progress, isClaimed: isClaimed),
  );
}

List<AchievementViewData> buildAllAchievementViewData({
  required List<Session> sessions,
  required LeaderboardEntry? leaderboardEntry,
  required Set<String> claimedAchievementIds,
}) {
  return achievementCatalog
      .map(
        (definition) => buildAchievementViewData(
          definition: definition,
          sessions: sessions,
          leaderboardEntry: leaderboardEntry,
          claimedAchievementIds: claimedAchievementIds,
        ),
      )
      .toList(growable: false);
}
