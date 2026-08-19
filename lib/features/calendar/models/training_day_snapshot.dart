import '../../../data/models/session.dart';
import '../../../data/models/training_plan.dart';
import 'training_day_status.dart';

/// Planner view of one Manila calendar day.
class TrainingDaySnapshot {
  const TrainingDaySnapshot({
    required this.dayKey,
    required this.civilDate,
    required this.status,
    required this.matchedDurationSeconds,
    required this.hasUnplannedActivity,
    this.plan,
    this.bestMatchingRubricTotal,
    this.matchingSessions = const [],
  });

  final String dayKey;
  final DateTime civilDate;
  final TrainingDayStatus status;
  final TrainingPlan? plan;
  final int matchedDurationSeconds;
  final bool hasUnplannedActivity;
  final int? bestMatchingRubricTotal;

  /// Matching sessions for the planned movement only. Never used as a
  /// History-style session list in Calendar UI.
  final List<Session> matchingSessions;

  bool get hasPlan => plan != null;
  bool get isRest => status == TrainingDayStatus.rest;
  bool get isTraining => plan?.isTraining ?? false;
}
