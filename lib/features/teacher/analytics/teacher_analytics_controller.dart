import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/public_profile_session.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_progress_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import 'teacher_analytics_models.dart';

/// Coordinates the read-only analytics snapshot without adding a persisted
/// analytics collection. Group, membership, assignment, and attempt streams
/// remain live; session projections are fetched only for the selected windows.
class TeacherAnalyticsController extends ChangeNotifier {
  TeacherAnalyticsController({
    required this.groupRepository,
    required this.assignmentRepository,
    required this.progressRepository,
    required this.teacherId,
    DateTime Function()? nowUtc,
    int maxConcurrentSessionReads = maxConcurrentSessionReadsDefault,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _maxConcurrentSessionReads = _validateConcurrency(
         maxConcurrentSessionReads,
       );

  static const maxConcurrentSessionReadsDefault = 5;

  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final TeacherProgressRepository progressRepository;
  final String teacherId;
  final DateTime Function() _nowUtc;
  final int _maxConcurrentSessionReads;

  AnalyticsScope scope = const AnalyticsScope.allClasses();
  AnalyticsPeriod period = AnalyticsPeriod.thisWeek;
  DateTime? customStartDate;
  DateTime? customEndDate;

  bool loading = true;
  bool sessionLoading = false;
  String? errorMessage;
  String? filterError;
  String? partialDataWarning;
  DateTime? lastUpdated;
  AnalyticsSnapshot? snapshot;

  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<GroupAssignment> assignments = const [];
  List<AssignmentAttempt> attempts = const [];
  Object? groupsStreamError;
  Object? membershipsStreamError;
  Object? assignmentsStreamError;
  Object? attemptsStreamError;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<GroupAssignment>>? _assignmentsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  Completer<void>? _groupsReady;
  Completer<void>? _membershipsReady;
  Completer<void>? _assignmentsReady;
  Completer<void>? _attemptsReady;

  Map<String, List<PublicProfileSession>> _currentSessionsByTrainee = {};
  Map<String, List<PublicProfileSession>> _comparisonSessionsByTrainee = {};
  AnalyticsPeriodWindow? _periodWindow;
  int _generation = 0;
  int _reloadGeneration = 0;
  bool _streamsReady = false;
  bool _disposed = false;

  String? get selectedGroupId => scope.groupId;
  bool get hasStreamError =>
      groupsStreamError != null ||
      membershipsStreamError != null ||
      assignmentsStreamError != null ||
      attemptsStreamError != null;
  bool get hasSnapshot => snapshot != null;
  int get maxConcurrentSessionReads => _maxConcurrentSessionReads;

  Future<void> start() async {
    final generation = ++_generation;
    _reloadGeneration++;
    _streamsReady = false;
    _complete(_groupsReady);
    _complete(_membershipsReady);
    _complete(_assignmentsReady);
    _complete(_attemptsReady);
    final oldGroupsSub = _groupsSub;
    final oldMembershipsSub = _membershipsSub;
    final oldAssignmentsSub = _assignmentsSub;
    final oldAttemptsSub = _attemptsSub;
    _groupsSub = null;
    _membershipsSub = null;
    _assignmentsSub = null;
    _attemptsSub = null;
    await _cancelAll(
      oldGroupsSub,
      oldMembershipsSub,
      oldAssignmentsSub,
      oldAttemptsSub,
    );
    if (_isStale(generation)) return;

    loading = true;
    sessionLoading = false;
    errorMessage = null;
    filterError = null;
    partialDataWarning = null;
    snapshot = null;
    _periodWindow = null;
    _currentSessionsByTrainee = {};
    _comparisonSessionsByTrainee = {};
    groupsStreamError = null;
    membershipsStreamError = null;
    assignmentsStreamError = null;
    attemptsStreamError = null;
    groups = const [];
    memberships = const [];
    assignments = const [];
    attempts = const [];
    _emit();

    final groupsReady = Completer<void>();
    final membershipsReady = Completer<void>();
    final assignmentsReady = Completer<void>();
    final attemptsReady = Completer<void>();
    _groupsReady = groupsReady;
    _membershipsReady = membershipsReady;
    _assignmentsReady = assignmentsReady;
    _attemptsReady = attemptsReady;

    final groupsSub = _listenSafely<ElixrGroup>(
      source: () => groupRepository.watchTeacherGroups(teacherId: teacherId),
      onData: (value) {
        if (_isStale(generation)) return;
        groups = value;
        groupsStreamError = null;
        _complete(groupsReady);
        _emit();
        _onMembershipContextChanged();
      },
      onError: (error) {
        if (_isStale(generation)) return;
        groupsStreamError = error;
        _complete(groupsReady);
        _emit();
      },
    );
    final membershipsSub = _listenSafely<GroupMembership>(
      source: () =>
          groupRepository.watchTeacherMemberships(teacherId: teacherId),
      onData: (value) {
        if (_isStale(generation)) return;
        memberships = value;
        membershipsStreamError = null;
        _complete(membershipsReady);
        _emit();
        _onMembershipContextChanged();
      },
      onError: (error) {
        if (_isStale(generation)) return;
        membershipsStreamError = error;
        _complete(membershipsReady);
        _emit();
      },
    );
    final assignmentsSub = _listenSafely<GroupAssignment>(
      source: () =>
          assignmentRepository.watchTeacherAssignments(teacherId: teacherId),
      onData: (value) {
        if (_isStale(generation)) return;
        assignments = value;
        assignmentsStreamError = null;
        _complete(assignmentsReady);
        _rebuildFromCachedSessions();
        _emit();
      },
      onError: (error) {
        if (_isStale(generation)) return;
        assignmentsStreamError = error;
        _complete(assignmentsReady);
        _emit();
      },
    );
    final attemptsSub = _listenSafely<AssignmentAttempt>(
      source: () =>
          assignmentRepository.watchAttemptsForTeacher(teacherId: teacherId),
      onData: (value) {
        if (_isStale(generation)) return;
        attempts = value;
        attemptsStreamError = null;
        _complete(attemptsReady);
        _rebuildFromCachedSessions();
        _emit();
      },
      onError: (error) {
        if (_isStale(generation)) return;
        attemptsStreamError = error;
        _complete(attemptsReady);
        _emit();
      },
    );
    if (_isStale(generation)) {
      await _cancelAll(groupsSub, membershipsSub, assignmentsSub, attemptsSub);
      return;
    }
    _groupsSub = groupsSub;
    _membershipsSub = membershipsSub;
    _assignmentsSub = assignmentsSub;
    _attemptsSub = attemptsSub;

    await Future.wait([
      groupsReady.future,
      membershipsReady.future,
      assignmentsReady.future,
      attemptsReady.future,
    ]);
    if (_isStale(generation)) return;
    _streamsReady = true;
    loading = false;
    _emit();
    await _reloadSessions();
  }

  Future<void> retry() => start();

  Future<void> refresh() async {
    if (_disposed) return;
    if (!_streamsReady) {
      await start();
      return;
    }
    await _reloadSessions();
  }

  Future<void> setSelectedGroupId(String? groupId) async {
    if (_disposed) return;
    final normalized = groupId?.trim();
    scope = normalized == null || normalized.isEmpty
        ? const AnalyticsScope.allClasses()
        : AnalyticsScope.group(normalized);
    await _reloadSessions();
  }

  Future<void> setScope(AnalyticsScope next) =>
      setSelectedGroupId(next.groupId);

  Future<void> setPeriod(AnalyticsPeriod next) async {
    if (_disposed) return;
    period = next;
    if (next != AnalyticsPeriod.custom) {
      filterError = null;
    }
    await _reloadSessions();
  }

  Future<void> setCustomRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (_disposed) return;
    period = AnalyticsPeriod.custom;
    customStartDate = DateTime(startDate.year, startDate.month, startDate.day);
    customEndDate = DateTime(endDate.year, endDate.month, endDate.day);
    await _reloadSessions();
  }

  AnalyticsPeriodWindow? resolvePeriod({DateTime? now}) {
    try {
      return AnalyticsPeriodWindow.resolve(
        period: period,
        nowUtc: (now ?? _nowUtc()).toUtc(),
        customStartDate: customStartDate,
        customEndDate: customEndDate,
      );
    } on AnalyticsRangeException {
      return null;
    }
  }

  Future<void> _reloadSessions() async {
    if (_disposed || !_streamsReady) return;
    final generation = ++_reloadGeneration;
    final now = _nowUtc().toUtc();
    late final AnalyticsPeriodWindow window;
    try {
      window = AnalyticsPeriodWindow.resolve(
        period: period,
        nowUtc: now,
        customStartDate: customStartDate,
        customEndDate: customEndDate,
      );
    } on AnalyticsRangeException catch (error) {
      if (_isReloadStale(generation)) return;
      filterError = error.message;
      snapshot = null;
      _periodWindow = null;
      sessionLoading = false;
      _emit();
      return;
    }

    filterError = null;
    _periodWindow = window;
    sessionLoading = true;
    partialDataWarning = null;
    _emit();

    // Fetch the all-class roster even when the selected filter is one group so
    // the comparison table can always include every active group.
    final students = AnalyticsCalculator.eligibleStudents(
      teacherId: teacherId,
      groups: groups,
      memberships: memberships,
      scope: const AnalyticsScope.allClasses(),
    );
    final current = <String, List<PublicProfileSession>>{};
    final comparison = <String, List<PublicProfileSession>>{};
    final failures = <String>{};
    final requests = <_SessionReadRequest>[];
    for (final student in students) {
      current[student.traineeId] = const [];
      comparison[student.traineeId] = const [];
      if (!window.current.isEmpty) {
        requests.add(
          _SessionReadRequest(
            traineeId: student.traineeId,
            range: window.current,
            target: _SessionReadTarget.current,
          ),
        );
      }
      if (!window.comparison.isEmpty) {
        requests.add(
          _SessionReadRequest(
            traineeId: student.traineeId,
            range: window.comparison,
            target: _SessionReadTarget.comparison,
          ),
        );
      }
    }

    var nextRequest = 0;
    Future<void> worker() async {
      while (true) {
        if (nextRequest >= requests.length) return;
        final request = requests[nextRequest++];
        try {
          final sessions = await progressRepository.fetchSessionsInRange(
            traineeId: request.traineeId,
            startUtc: request.range.startUtc,
            endUtc: request.range.endUtc,
          );
          if (request.target == _SessionReadTarget.current) {
            current[request.traineeId] = sessions;
          } else {
            comparison[request.traineeId] = sessions;
          }
        } on Object catch (error, stackTrace) {
          failures.add('${request.traineeId}:${request.target.name}');
          _logSessionReadFailure(request, error, stackTrace);
        }
      }
    }

    final workerCount = requests.length < _maxConcurrentSessionReads
        ? requests.length
        : _maxConcurrentSessionReads;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    if (_isReloadStale(generation)) return;

    _currentSessionsByTrainee = current;
    _comparisonSessionsByTrainee = comparison;
    partialDataWarning = failures.isEmpty
        ? null
        : 'Some student practice history could not be loaded. Some numbers may be incomplete.';
    _rebuildFromCachedSessions(nowUtc: now, window: window);
    sessionLoading = false;
    lastUpdated = now;
    _emit();
  }

  void _rebuildFromCachedSessions({
    DateTime? nowUtc,
    AnalyticsPeriodWindow? window,
  }) {
    final resolved = window ?? _periodWindow;
    if (resolved == null || _disposed) return;
    final nextSnapshot = AnalyticsCalculator.calculate(
      teacherId: teacherId,
      groups: groups,
      memberships: memberships,
      assignments: assignments,
      attempts: attempts,
      currentSessionsByTrainee: _currentSessionsByTrainee,
      comparisonSessionsByTrainee: _comparisonSessionsByTrainee,
      scope: scope,
      periodWindow: resolved,
      nowUtc: (nowUtc ?? _nowUtc()).toUtc(),
    );
    snapshot = nextSnapshot;
  }

  void _onMembershipContextChanged() {
    if (!_streamsReady || _disposed) return;
    _purgeUnauthorizedSessionData();
    _rebuildFromCachedSessions();
    _emit();
    unawaited(_reloadSessions());
  }

  void _purgeUnauthorizedSessionData() {
    final ids = AnalyticsCalculator.eligibleStudents(
      teacherId: teacherId,
      groups: groups,
      memberships: memberships,
      scope: const AnalyticsScope.allClasses(),
    ).map((student) => student.traineeId).toSet();
    _currentSessionsByTrainee.removeWhere((id, _) => !ids.contains(id));
    _comparisonSessionsByTrainee.removeWhere((id, _) => !ids.contains(id));
  }

  StreamSubscription<List<T>>? _listenSafely<T>({
    required Stream<List<T>> Function() source,
    required void Function(List<T>) onData,
    required void Function(Object) onError,
  }) {
    try {
      return source().listen(
        onData,
        onError: (Object error, StackTrace stackTrace) => onError(error),
      );
    } on Object catch (error) {
      onError(error);
      return null;
    }
  }

  void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;
  bool _isReloadStale(int generation) =>
      _disposed || generation != _reloadGeneration;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _logSessionReadFailure(
    _SessionReadRequest request,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint(
      '[TeacherAnalytics] ${request.traineeId} ${request.target.name} '
      'read failed: $error\n$stackTrace',
    );
  }

  Future<void> _cancelAll(
    StreamSubscription<dynamic>? groups,
    StreamSubscription<dynamic>? memberships,
    StreamSubscription<dynamic>? assignments,
    StreamSubscription<dynamic>? attempts,
  ) async {
    await Future.wait([
      if (groups != null) groups.cancel(),
      if (memberships != null) memberships.cancel(),
      if (assignments != null) assignments.cancel(),
      if (attempts != null) attempts.cancel(),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _reloadGeneration++;
    _complete(_groupsReady);
    _complete(_membershipsReady);
    _complete(_assignmentsReady);
    _complete(_attemptsReady);
    unawaited(
      _cancelAll(_groupsSub, _membershipsSub, _assignmentsSub, _attemptsSub),
    );
    super.dispose();
  }

  static int _validateConcurrency(int value) {
    if (value < 1 || value > 5) {
      throw ArgumentError.value(
        value,
        'maxConcurrentSessionReads',
        'must be 1..5',
      );
    }
    return value;
  }
}

enum _SessionReadTarget { current, comparison }

class _SessionReadRequest {
  const _SessionReadRequest({
    required this.traineeId,
    required this.range,
    required this.target,
  });

  final String traineeId;
  final AnalyticsRange range;
  final _SessionReadTarget target;
}
