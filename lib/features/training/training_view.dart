/// Internal views of the top-level Training destination.
enum TrainingView {
  planner,
  history;

  static const viewQueryParameter = 'view';
  static const dateQueryParameter = 'date';

  /// Parses `?view=` from the Training URL.
  ///
  /// Missing, empty, and unknown values fall back to [TrainingView.planner].
  static TrainingView fromQuery(String? raw) {
    return switch (raw) {
      'history' => TrainingView.history,
      _ => TrainingView.planner,
    };
  }

  String get queryValue => switch (this) {
    TrainingView.planner => 'planner',
    TrainingView.history => 'history',
  };

  bool get isPlanner => this == TrainingView.planner;
  bool get isHistory => this == TrainingView.history;
}

/// Canonical Training location. Always includes `view` so navigation stays
/// deterministic. [date] is an optional `YYYY-MM-DD` civil date.
String trainingLocation({
  TrainingView view = TrainingView.planner,
  String? date,
}) {
  return Uri(
    path: '/training',
    queryParameters: {
      TrainingView.viewQueryParameter: view.queryValue,
      if (date != null && date.isNotEmpty)
        TrainingView.dateQueryParameter: date,
    },
  ).toString();
}

/// Compatibility redirect for `/calendar` and `/calendar?date=`.
String trainingLocationFromCalendar({String? date}) {
  return trainingLocation(view: TrainingView.planner, date: date);
}

/// Compatibility redirect for `/history`.
String trainingLocationFromHistory({String? date}) {
  return trainingLocation(view: TrainingView.history, date: date);
}
