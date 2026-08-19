/// Derived training-plan state for one Manila calendar day.
///
/// Never persist these values. They are computed from the plan, the current
/// Manila day, and matching completed sessions.
enum TrainingDayStatus {
  unplanned,
  planned,
  inProgress,
  completed,
  missed,
  rest;

  String get label => switch (this) {
    TrainingDayStatus.unplanned => 'Unplanned',
    TrainingDayStatus.planned => 'Planned',
    TrainingDayStatus.inProgress => 'In Progress',
    TrainingDayStatus.completed => 'Completed',
    TrainingDayStatus.missed => 'Missed',
    TrainingDayStatus.rest => 'Rest',
  };
}
