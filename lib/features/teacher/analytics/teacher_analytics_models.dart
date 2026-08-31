import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/public_profile_session.dart';

import '../../../core/utils/manila_day.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';

enum AnalyticsPeriod {
  thisWeek,
  thisMonth,
  custom;

  String get label => switch (this) {
    AnalyticsPeriod.thisWeek => 'This Week',
    AnalyticsPeriod.thisMonth => 'This Month',
    AnalyticsPeriod.custom => 'Custom range',
  };
}

/// A half-open UTC interval. All calendar construction is Manila-based; all
/// Firestore reads use this UTC representation.
class AnalyticsRange {
  const AnalyticsRange({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;

  Duration get duration => endUtc.difference(startUtc);
  bool get isEmpty => startUtc.isAtSameMomentAs(endUtc);

  bool contains(DateTime value) {
    final instant = value.toUtc();
    return !instant.isBefore(startUtc) && instant.isBefore(endUtc);
  }

  AnalyticsRange copyWith({DateTime? startUtc, DateTime? endUtc}) =>
      AnalyticsRange(
        startUtc: startUtc ?? this.startUtc,
        endUtc: endUtc ?? this.endUtc,
      );
}

class AnalyticsPeriodWindow {
  const AnalyticsPeriodWindow({
    required this.current,
    required this.comparison,
    required this.period,
  });

  final AnalyticsRange current;
  final AnalyticsRange comparison;
  final AnalyticsPeriod period;

  factory AnalyticsPeriodWindow.resolve({
    required AnalyticsPeriod period,
    required DateTime nowUtc,
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) {
    final now = nowUtc.toUtc();
    late final AnalyticsRange current;

    switch (period) {
      case AnalyticsPeriod.thisWeek:
        final currentDayStart = ManilaDay.dayStartUtcFor(now);
        final civil = ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(now));
        final weekStart = currentDayStart.subtract(
          Duration(days: civil.weekday - DateTime.monday),
        );
        current = AnalyticsRange(startUtc: weekStart, endUtc: now);
      case AnalyticsPeriod.thisMonth:
        final civil = ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(now));
        final monthStart = _manilaMidnightUtc(
          DateTime(civil.year, civil.month, 1),
        );
        current = AnalyticsRange(startUtc: monthStart, endUtc: now);
      case AnalyticsPeriod.custom:
        current = _customRange(
          startDate: customStartDate,
          endDate: customEndDate,
          nowUtc: now,
        );
    }

    late final AnalyticsRange comparison;
    switch (period) {
      case AnalyticsPeriod.thisWeek:
        final elapsed = current.duration;
        final previousStart = current.startUtc.subtract(
          const Duration(days: 7),
        );
        comparison = AnalyticsRange(
          startUtc: previousStart,
          endUtc: _minDateTime(previousStart.add(elapsed), current.startUtc),
        );
      case AnalyticsPeriod.thisMonth:
        final currentCivil = ManilaDay.civilDateFromDayKey(
          ManilaDay.dayKeyFor(current.startUtc),
        );
        final previousMonthCivil = DateTime(
          currentCivil.year,
          currentCivil.month - 1,
          1,
        );
        final previousStart = _manilaMidnightUtc(previousMonthCivil);
        comparison = AnalyticsRange(
          startUtc: previousStart,
          endUtc: _minDateTime(
            previousStart.add(current.duration),
            current.startUtc,
          ),
        );
      case AnalyticsPeriod.custom:
        final elapsed = current.duration;
        comparison = AnalyticsRange(
          startUtc: current.startUtc.subtract(elapsed),
          endUtc: current.startUtc,
        );
    }

    return AnalyticsPeriodWindow(
      current: current,
      comparison: comparison,
      period: period,
    );
  }
}

class AnalyticsRangeException implements Exception {
  const AnalyticsRangeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AnalyticsScope {
  const AnalyticsScope({this.groupId});

  const AnalyticsScope.allClasses() : groupId = null;

  const AnalyticsScope.group(String value) : groupId = value;

  final String? groupId;
  bool get isAllClasses => groupId == null;
}

class AnalyticsEligibleStudent {
  const AnalyticsEligibleStudent({
    required this.traineeId,
    required this.displayName,
    required this.memberships,
    required this.enrolledAt,
  });

  final String traineeId;
  final String displayName;
  final List<GroupMembership> memberships;
  final DateTime? enrolledAt;

  bool belongsTo(String groupId) =>
      memberships.any((membership) => membership.groupId == groupId);
}

class MovementInsight {
  const MovementInsight({
    required this.movementName,
    required this.sessionCount,
    required this.distinctStudentCount,
    this.averageScore,
  });

  final String movementName;
  final int sessionCount;
  final int distinctStudentCount;
  final double? averageScore;
}

class AnalyticsTrendBucket {
  const AnalyticsTrendBucket({
    required this.startUtc,
    required this.endUtc,
    required this.label,
    required this.sessionCount,
    required this.distinctStudentCount,
    required this.averageScore,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final String label;
  final int sessionCount;
  final int distinctStudentCount;
  final double? averageScore;
}

class GroupComparison {
  const GroupComparison({
    required this.group,
    required this.eligibleStudentCount,
    required this.sessionCount,
    required this.averageScore,
    required this.averagePracticeSessions,
    required this.completionRate,
    required this.improvement,
    required this.expectedSubmissionCount,
    required this.turnedInSubmissionCount,
    required this.matchedStudentCount,
  });

  final ElixrGroup group;
  final int eligibleStudentCount;
  final int sessionCount;
  final double? averageScore;
  final double? averagePracticeSessions;
  final double? completionRate;
  final double? improvement;
  final int expectedSubmissionCount;
  final int turnedInSubmissionCount;
  final int matchedStudentCount;
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.scope,
    required this.periodWindow,
    required this.eligibleStudentCount,
    required this.sessionCount,
    required this.rubricSessionCount,
    required this.rubricStudentCount,
    required this.averageScore,
    required this.averagePracticeSessions,
    required this.completionRate,
    required this.expectedSubmissionCount,
    required this.turnedInSubmissionCount,
    required this.improvement,
    required this.matchedStudentCount,
    required this.trendBuckets,
    required this.mostPracticed,
    required this.hardest,
    required this.groupComparisons,
  });

  final AnalyticsScope scope;
  final AnalyticsPeriodWindow periodWindow;
  final int eligibleStudentCount;
  final int sessionCount;
  final int rubricSessionCount;
  final int rubricStudentCount;
  final double? averageScore;
  final double? averagePracticeSessions;
  final double? completionRate;
  final int expectedSubmissionCount;
  final int turnedInSubmissionCount;
  final double? improvement;
  final int matchedStudentCount;
  final List<AnalyticsTrendBucket> trendBuckets;
  final MovementInsight? mostPracticed;
  final MovementInsight? hardest;
  final List<GroupComparison> groupComparisons;

  bool get hasExpectedWork => expectedSubmissionCount > 0;
  bool get hasActivity => sessionCount > 0;
}

class AnalyticsCalculator {
  const AnalyticsCalculator._();

  static AnalyticsSnapshot calculate({
    required String teacherId,
    required List<ElixrGroup> groups,
    required List<GroupMembership> memberships,
    required List<GroupAssignment> assignments,
    required List<AssignmentAttempt> attempts,
    required Map<String, List<PublicProfileSession>> currentSessionsByTrainee,
    required Map<String, List<PublicProfileSession>>
    comparisonSessionsByTrainee,
    required AnalyticsScope scope,
    required AnalyticsPeriodWindow periodWindow,
    required DateTime nowUtc,
  }) {
    final activeGroups = groups
        .where((group) => group.teacherId == teacherId && group.isActive)
        .toList(growable: false);
    final currentStudents = eligibleStudents(
      teacherId: teacherId,
      groups: activeGroups,
      memberships: memberships,
      scope: scope,
    );
    final metrics = _calculateMetrics(
      teacherId: teacherId,
      students: currentStudents,
      scope: scope,
      activeGroups: activeGroups,
      assignments: assignments,
      attempts: attempts,
      currentSessionsByTrainee: currentSessionsByTrainee,
      comparisonSessionsByTrainee: comparisonSessionsByTrainee,
      periodWindow: periodWindow,
      nowUtc: nowUtc,
    );

    final comparisons = [
      for (final group in activeGroups)
        _toGroupComparison(
          group,
          _calculateMetrics(
            teacherId: teacherId,
            students: eligibleStudents(
              teacherId: teacherId,
              groups: activeGroups,
              memberships: memberships,
              scope: AnalyticsScope.group(group.id),
            ),
            scope: AnalyticsScope.group(group.id),
            activeGroups: activeGroups,
            assignments: assignments,
            attempts: attempts,
            currentSessionsByTrainee: currentSessionsByTrainee,
            comparisonSessionsByTrainee: comparisonSessionsByTrainee,
            periodWindow: periodWindow,
            nowUtc: nowUtc,
          ),
        ),
    ];

    return AnalyticsSnapshot(
      scope: scope,
      periodWindow: periodWindow,
      eligibleStudentCount: currentStudents.length,
      sessionCount: metrics.sessionCount,
      rubricSessionCount: metrics.rubricSessionCount,
      rubricStudentCount: metrics.rubricStudentCount,
      averageScore: metrics.averageScore,
      averagePracticeSessions: metrics.averagePracticeSessions,
      completionRate: metrics.completionRate,
      expectedSubmissionCount: metrics.expectedSubmissionCount,
      turnedInSubmissionCount: metrics.turnedInSubmissionCount,
      improvement: metrics.improvement,
      matchedStudentCount: metrics.matchedStudentCount,
      trendBuckets: metrics.trendBuckets,
      mostPracticed: metrics.mostPracticed,
      hardest: metrics.hardest,
      groupComparisons: List<GroupComparison>.unmodifiable(comparisons),
    );
  }

  static List<AnalyticsEligibleStudent> eligibleStudents({
    required String teacherId,
    required List<ElixrGroup> groups,
    required List<GroupMembership> memberships,
    required AnalyticsScope scope,
  }) {
    final activeGroupIds = groups
        .where((group) => group.teacherId == teacherId && group.isActive)
        .map((group) => group.id)
        .toSet();
    final scopedGroupId = scope.groupId;
    if (scopedGroupId != null && !activeGroupIds.contains(scopedGroupId)) {
      return const [];
    }

    final byMembership = <String, GroupMembership>{};
    for (final membership in memberships) {
      if (membership.teacherId != teacherId ||
          !membership.isApproved ||
          !activeGroupIds.contains(membership.groupId) ||
          (scopedGroupId != null && membership.groupId != scopedGroupId)) {
        continue;
      }
      final key = '${membership.groupId}:${membership.traineeId}';
      final existing = byMembership[key];
      if (existing == null ||
          _membershipDate(membership).isAfter(_membershipDate(existing))) {
        byMembership[key] = membership;
      }
    }

    final byTrainee = <String, List<GroupMembership>>{};
    for (final membership in byMembership.values) {
      byTrainee.putIfAbsent(membership.traineeId, () => []).add(membership);
    }

    final result = [
      for (final entry in byTrainee.entries)
        AnalyticsEligibleStudent(
          traineeId: entry.key,
          displayName: _displayName(entry.value),
          memberships: List<GroupMembership>.unmodifiable(entry.value),
          enrolledAt: _earliestMembershipDate(entry.value),
        ),
    ];
    result.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return List<AnalyticsEligibleStudent>.unmodifiable(result);
  }

  static _AnalyticsMetrics _calculateMetrics({
    required String teacherId,
    required List<AnalyticsEligibleStudent> students,
    required AnalyticsScope scope,
    required List<ElixrGroup> activeGroups,
    required List<GroupAssignment> assignments,
    required List<AssignmentAttempt> attempts,
    required Map<String, List<PublicProfileSession>> currentSessionsByTrainee,
    required Map<String, List<PublicProfileSession>>
    comparisonSessionsByTrainee,
    required AnalyticsPeriodWindow periodWindow,
    required DateTime nowUtc,
  }) {
    final currentSessions = <String, List<PublicProfileSession>>{};
    final comparisonSessions = <String, List<PublicProfileSession>>{};
    for (final student in students) {
      currentSessions[student.traineeId] = _filterSessions(
        currentSessionsByTrainee[student.traineeId] ?? const [],
        periodWindow.current,
        student.enrolledAt,
        student.traineeId,
      );
      comparisonSessions[student.traineeId] = _filterSessions(
        comparisonSessionsByTrainee[student.traineeId] ?? const [],
        periodWindow.comparison,
        student.enrolledAt,
        student.traineeId,
      );
    }

    final allCurrent = currentSessions.values.expand((items) => items).toList();
    final currentScores = _studentAverages(currentSessions);
    final comparisonScores = _studentAverages(comparisonSessions);
    final matchedIds = currentScores.keys
        .where(comparisonScores.containsKey)
        .toList(growable: false);
    final improvement = matchedIds.isEmpty
        ? null
        : _mean([
            for (final id in matchedIds)
              currentScores[id]! - comparisonScores[id]!,
          ]);
    final completion = _completion(
      teacherId: teacherId,
      students: students,
      scope: scope,
      activeGroups: activeGroups,
      assignments: assignments,
      attempts: attempts,
      period: periodWindow.current,
      nowUtc: nowUtc,
    );

    return _AnalyticsMetrics(
      eligibleStudentCount: students.length,
      sessionCount: allCurrent.length,
      rubricSessionCount: allCurrent.where((s) => s.isRubricAssessed).length,
      rubricStudentCount: currentScores.length,
      averageScore: _mean(currentScores.values),
      averagePracticeSessions: students.isEmpty
          ? null
          : allCurrent.length / students.length,
      completionRate: completion.rate,
      expectedSubmissionCount: completion.expected,
      turnedInSubmissionCount: completion.turnedIn,
      improvement: improvement,
      matchedStudentCount: matchedIds.length,
      trendBuckets: _trendBuckets(
        students: students,
        currentSessions: currentSessions,
        range: periodWindow.current,
      ),
      mostPracticed: _mostPracticed(
        students: students,
        currentSessions: currentSessions,
      ),
      hardest: _hardest(students: students, currentSessions: currentSessions),
    );
  }

  static GroupComparison _toGroupComparison(
    ElixrGroup group,
    _AnalyticsMetrics metrics,
  ) => GroupComparison(
    group: group,
    eligibleStudentCount: metrics.eligibleStudentCount,
    sessionCount: metrics.sessionCount,
    averageScore: metrics.averageScore,
    averagePracticeSessions: metrics.averagePracticeSessions,
    completionRate: metrics.completionRate,
    improvement: metrics.improvement,
    expectedSubmissionCount: metrics.expectedSubmissionCount,
    turnedInSubmissionCount: metrics.turnedInSubmissionCount,
    matchedStudentCount: metrics.matchedStudentCount,
  );

  static List<PublicProfileSession> _filterSessions(
    Iterable<PublicProfileSession> source,
    AnalyticsRange range,
    DateTime? enrolledAt,
    String traineeId,
  ) {
    final seenIds = <String>{};
    final result = <PublicProfileSession>[];
    for (final session in source) {
      if (session.userId != traineeId || !seenIds.add(session.sessionId)) {
        continue;
      }
      final createdAt = session.createdAt == null
          ? null
          : DateTime.tryParse(session.createdAt!);
      if (createdAt == null || !range.contains(createdAt)) continue;
      if (enrolledAt != null && createdAt.toUtc().isBefore(enrolledAt)) {
        continue;
      }
      result.add(session);
    }
    result.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
    return result;
  }

  static Map<String, double> _studentAverages(
    Map<String, List<PublicProfileSession>> sessions,
  ) {
    final result = <String, double>{};
    for (final entry in sessions.entries) {
      final scores = [
        for (final session in entry.value)
          if (session.isRubricAssessed) session.rubric!.total.toDouble(),
      ];
      final average = _mean(scores);
      if (average != null) result[entry.key] = average;
    }
    return result;
  }

  static _CompletionMetrics _completion({
    required String teacherId,
    required List<AnalyticsEligibleStudent> students,
    required AnalyticsScope scope,
    required List<ElixrGroup> activeGroups,
    required List<GroupAssignment> assignments,
    required List<AssignmentAttempt> attempts,
    required AnalyticsRange period,
    required DateTime nowUtc,
  }) {
    final activeGroupIds = activeGroups.map((group) => group.id).toSet();
    final scopedAssignments = assignments.where((assignment) {
      if (assignment.teacherId != teacherId) return false;
      if (!activeGroupIds.contains(assignment.groupId)) return false;
      if (scope.groupId != null && assignment.groupId != scope.groupId) {
        return false;
      }
      final date = (assignment.dueAt ?? assignment.createdAt)?.toUtc();
      if (date == null || date.isAfter(nowUtc.toUtc())) return false;
      return period.contains(date);
    });

    var expected = 0;
    var turnedIn = 0;
    for (final assignment in scopedAssignments) {
      final assignmentAttempts = attempts.where(
        (attempt) =>
            attempt.teacherId == teacherId &&
            attempt.groupId == assignment.groupId,
      );
      for (final student in students) {
        if (!student.belongsTo(assignment.groupId) ||
            !assignment.isAvailableToTrainee(student.traineeId)) {
          continue;
        }
        expected++;
        final latest = AssignmentAttemptSemantics.latestVisible(
          attempts: assignmentAttempts,
          assignmentId: assignment.id,
          traineeId: student.traineeId,
        );
        if (AssignmentAttemptSemantics.isTurnedIn(latest)) turnedIn++;
      }
    }
    return _CompletionMetrics(
      expected: expected,
      turnedIn: turnedIn,
      rate: expected == 0 ? null : turnedIn / expected,
    );
  }

  static List<AnalyticsTrendBucket> _trendBuckets({
    required List<AnalyticsEligibleStudent> students,
    required Map<String, List<PublicProfileSession>> currentSessions,
    required AnalyticsRange range,
  }) {
    if (range.isEmpty) return const [];
    final daily = range.duration <= const Duration(days: 31);
    final buckets = <AnalyticsTrendBucket>[];
    var cursor = daily ? range.startUtc : _manilaWeekStartUtc(range.startUtc);
    if (cursor.isBefore(range.startUtc)) cursor = range.startUtc;
    while (cursor.isBefore(range.endUtc)) {
      final nominalEnd = cursor.add(
        daily ? const Duration(days: 1) : const Duration(days: 7),
      );
      final end = _minDateTime(nominalEnd, range.endUtc);
      final bucketSessions = <PublicProfileSession>[];
      final bucketStudents = <String>{};
      for (final student in students) {
        for (final session in currentSessions[student.traineeId] ?? const []) {
          final createdAt = session.createdAt == null
              ? null
              : DateTime.tryParse(session.createdAt!);
          if (createdAt == null ||
              createdAt.toUtc().isBefore(cursor) ||
              !createdAt.toUtc().isBefore(end)) {
            continue;
          }
          bucketSessions.add(session);
          bucketStudents.add(student.traineeId);
        }
      }
      final byStudent = <String, List<double>>{};
      for (final session in bucketSessions) {
        if (!session.isRubricAssessed) continue;
        byStudent
            .putIfAbsent(session.userId, () => [])
            .add(session.rubric!.total.toDouble());
      }
      final studentAverages = [
        for (final scores in byStudent.values) _mean(scores)!,
      ];
      buckets.add(
        AnalyticsTrendBucket(
          startUtc: cursor,
          endUtc: end,
          label: ManilaDay.dayKeyFor(cursor),
          sessionCount: bucketSessions.length,
          distinctStudentCount: bucketStudents.length,
          averageScore: _mean(studentAverages),
        ),
      );
      cursor = end;
    }
    return List<AnalyticsTrendBucket>.unmodifiable(buckets);
  }

  static MovementInsight? _mostPracticed({
    required List<AnalyticsEligibleStudent> students,
    required Map<String, List<PublicProfileSession>> currentSessions,
  }) {
    final byMovement = <String, List<PublicProfileSession>>{};
    for (final student in students) {
      for (final session in currentSessions[student.traineeId] ?? const []) {
        byMovement.putIfAbsent(session.movementName, () => []).add(session);
      }
    }
    if (byMovement.isEmpty) return null;
    final entries = byMovement.entries.toList()
      ..sort((a, b) {
        final count = b.value.length.compareTo(a.value.length);
        return count != 0
            ? count
            : a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    final selected = entries.first;
    return MovementInsight(
      movementName: selected.key,
      sessionCount: selected.value.length,
      distinctStudentCount: selected.value.map((s) => s.userId).toSet().length,
    );
  }

  static MovementInsight? _hardest({
    required List<AnalyticsEligibleStudent> students,
    required Map<String, List<PublicProfileSession>> currentSessions,
  }) {
    final byMovement = <String, List<PublicProfileSession>>{};
    for (final student in students) {
      for (final session in currentSessions[student.traineeId] ?? const []) {
        if (session.isRubricAssessed) {
          byMovement.putIfAbsent(session.movementName, () => []).add(session);
        }
      }
    }
    final candidates = <MovementInsight>[];
    for (final entry in byMovement.entries) {
      final sessionsByStudent = <String, List<double>>{};
      for (final session in entry.value) {
        sessionsByStudent
            .putIfAbsent(session.userId, () => [])
            .add(session.rubric!.total.toDouble());
      }
      if (entry.value.length < 3 || sessionsByStudent.length < 2) continue;
      candidates.add(
        MovementInsight(
          movementName: entry.key,
          sessionCount: entry.value.length,
          distinctStudentCount: sessionsByStudent.length,
          averageScore: _mean([
            for (final scores in sessionsByStudent.values) _mean(scores)!,
          ]),
        ),
      );
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final score = a.averageScore!.compareTo(b.averageScore!);
      return score != 0
          ? score
          : a.movementName.toLowerCase().compareTo(
              b.movementName.toLowerCase(),
            );
    });
    return candidates.first;
  }

  static double? _mean(Iterable<double> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static DateTime _membershipDate(GroupMembership membership) =>
      (membership.updatedAt ??
              membership.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .toUtc();

  static DateTime? _earliestMembershipDate(
    Iterable<GroupMembership> memberships,
  ) {
    final dates = memberships
        .map((membership) => membership.updatedAt ?? membership.createdAt)
        .whereType<DateTime>()
        .map((date) => date.toUtc())
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  static String _displayName(Iterable<GroupMembership> memberships) {
    final sorted = memberships.toList()
      ..sort((a, b) => _membershipDate(b).compareTo(_membershipDate(a)));
    return sorted.first.traineeDisplayName;
  }

  static DateTime _manilaWeekStartUtc(DateTime instantUtc) {
    final civil = ManilaDay.civilDateFromDayKey(
      ManilaDay.dayKeyFor(instantUtc),
    );
    final dayStart = ManilaDay.dayStartUtcFor(instantUtc);
    return dayStart.subtract(Duration(days: civil.weekday - DateTime.monday));
  }
}

class _AnalyticsMetrics {
  const _AnalyticsMetrics({
    required this.eligibleStudentCount,
    required this.sessionCount,
    required this.rubricSessionCount,
    required this.rubricStudentCount,
    required this.averageScore,
    required this.averagePracticeSessions,
    required this.completionRate,
    required this.expectedSubmissionCount,
    required this.turnedInSubmissionCount,
    required this.improvement,
    required this.matchedStudentCount,
    required this.trendBuckets,
    required this.mostPracticed,
    required this.hardest,
  });

  final int eligibleStudentCount;
  final int sessionCount;
  final int rubricSessionCount;
  final int rubricStudentCount;
  final double? averageScore;
  final double? averagePracticeSessions;
  final double? completionRate;
  final int expectedSubmissionCount;
  final int turnedInSubmissionCount;
  final double? improvement;
  final int matchedStudentCount;
  final List<AnalyticsTrendBucket> trendBuckets;
  final MovementInsight? mostPracticed;
  final MovementInsight? hardest;
}

class _CompletionMetrics {
  const _CompletionMetrics({
    required this.expected,
    required this.turnedIn,
    required this.rate,
  });

  final int expected;
  final int turnedIn;
  final double? rate;
}

DateTime _customManilaDate(Object? value) {
  if (value is! DateTime) {
    throw const AnalyticsRangeException('Choose a valid custom date range.');
  }
  final date = DateTime(value.year, value.month, value.day);
  if (date.year != value.year ||
      date.month != value.month ||
      date.day != value.day) {
    throw const AnalyticsRangeException('Choose a valid custom date range.');
  }
  return date;
}

AnalyticsRange _customRange({
  required DateTime? startDate,
  required DateTime? endDate,
  required DateTime nowUtc,
}) {
  final start = _customManilaDate(startDate);
  final end = _customManilaDate(endDate);
  if (end.isBefore(start)) {
    throw const AnalyticsRangeException(
      'The end date must be on or after the start date.',
    );
  }
  final today = ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(nowUtc));
  if (start.isAfter(today) || end.isAfter(today)) {
    throw const AnalyticsRangeException('Future dates are not available.');
  }
  final inclusiveDays = end.difference(start).inDays + 1;
  if (inclusiveDays > 90) {
    throw const AnalyticsRangeException(
      'Custom ranges can cover up to 90 days.',
    );
  }

  final startUtc = _manilaMidnightUtc(start);
  final endUtc = _manilaMidnightUtc(end.add(const Duration(days: 1)));
  return AnalyticsRange(
    startUtc: startUtc,
    endUtc: _minDateTime(endUtc, nowUtc.toUtc()),
  );
}

DateTime _manilaMidnightUtc(DateTime civilDate) => DateTime.utc(
  civilDate.year,
  civilDate.month,
  civilDate.day,
).subtract(const Duration(hours: 8));

DateTime _minDateTime(DateTime first, DateTime second) =>
    first.isBefore(second) ? first : second;
