import 'package:flutter/foundation.dart';

import '../../data/models/session.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../progress/training_recommendation.dart';

/// Coordinates trainee dashboard stats/session loading, including refresh,
/// user isolation, and overlapping-request cancellation.
class DashboardStatsLoader {
  DashboardStatsLoader({
    required this.sessionRepository,
    TrainingRecommendation Function(List<Session> sessions)?
    buildRecommendation,
  }) : _buildRecommendation = buildRecommendation;

  final SessionRepository sessionRepository;
  final TrainingRecommendation Function(List<Session> sessions)?
  _buildRecommendation;

  ProgressStats? stats;
  List<Session> sessions = const [];
  TrainingRecommendation? trainingRecommendation;
  bool loading = true;
  String? loadError;
  String? loadedUserId;

  /// User id passed to the in-flight or latest [load] call.
  String? requestedUserId;
  int _generation = 0;

  bool get showFullPageError => loadError != null && stats == null;
  bool get showInlineError => loadError != null && stats != null;

  /// True when rendered stats/sessions belong to [userId].
  bool hasDataFor(String? userId) =>
      userId != null && loadedUserId == userId && stats != null;

  Future<void> load(
    String? userId, {
    TrainingRecommendation Function(List<Session> sessions)?
    buildRecommendation,
    bool Function()? stillCurrent,
  }) async {
    final generation = ++_generation;
    requestedUserId = userId;
    bool current() =>
        generation == _generation && (stillCurrent == null || stillCurrent());

    if (userId == null) {
      stats = null;
      sessions = const [];
      trainingRecommendation = null;
      loadedUserId = null;
      loadError = null;
      loading = false;
      return;
    }

    final isUserSwitch = loadedUserId != userId;
    if (isUserSwitch) {
      loading = true;
      trainingRecommendation = null;
      stats = null;
      sessions = const [];
      loadedUserId = null;
      loadError = null;
    }

    try {
      final nextSessions = await sessionRepository.getSessionsForUser(userId);
      if (!current()) return;
      final nextStats = ProgressStats.fromSessions(nextSessions);
      final recommend = buildRecommendation ?? _buildRecommendation;
      if (recommend == null) {
        throw StateError(
          'DashboardStatsLoader requires a recommendation builder',
        );
      }
      final nextRecommendation = recommend(nextSessions);
      if (!current()) return;

      stats = nextStats;
      sessions = nextSessions;
      trainingRecommendation = nextRecommendation;
      loadedUserId = userId;
      loadError = null;
      loading = false;
    } catch (error, stackTrace) {
      if (!current()) return;
      debugPrint('Dashboard statistics load failed: $error\n$stackTrace');
      loadError = 'We could not load your dashboard. Please try again.';
      loading = false;
    }
  }
}
