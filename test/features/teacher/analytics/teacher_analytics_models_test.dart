import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_models.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _teacherId = 'teacher';
final _approval = DateTime.utc(2026, 8, 10, 16);

ElixrGroup _group({
  String id = 'group-1',
  String teacherId = _teacherId,
  String name = 'Group 1',
  ElixrGroupStatus status = ElixrGroupStatus.active,
}) => ElixrGroup(
  id: id,
  teacherId: teacherId,
  name: name,
  status: status,
  createdAt: _approval,
  updatedAt: _approval,
);

GroupMembership _membership({
  required String groupId,
  required String traineeId,
  String name = 'Student',
  GroupMembershipStatus status = GroupMembershipStatus.approved,
  DateTime? updatedAt,
  String teacherId = _teacherId,
}) => GroupMembership(
  id: GroupMembership.documentId(groupId: groupId, traineeId: traineeId),
  groupId: groupId,
  teacherId: teacherId,
  traineeId: traineeId,
  traineeDisplayName: name,
  teacherDisplayName: 'Teacher',
  status: status,
  createdAt: _approval,
  updatedAt: updatedAt ?? _approval,
);

RubricAssessment _rubric(int total) {
  var remaining = total;
  int take() {
    final value = remaining < RubricAssessment.maxCriterionScore
        ? remaining
        : RubricAssessment.maxCriterionScore;
    remaining -= value;
    return value;
  }

  return RubricAssessment(
    technique: take(),
    stability: take(),
    completion: take(),
    propPositioning: take(),
  );
}

PublicProfileSession _session({
  required String id,
  required String userId,
  required DateTime createdAt,
  String movementName = 'Hand Stall',
  int? rubricTotal,
}) => PublicProfileSession(
  sessionId: id,
  userId: userId,
  movementName: movementName,
  difficulty: 'Medium',
  legacyScore: rubricTotal == null ? 80 : null,
  rubric: rubricTotal == null ? null : _rubric(rubricTotal),
  assessmentVersion: rubricTotal == null ? 1 : 2,
  durationSeconds: 60,
  propType: TrainingProp.bottle,
  createdAt: createdAt.toIso8601String(),
);

GroupAssignment _assignment({
  required String id,
  String teacherId = _teacherId,
  String groupId = 'group-1',
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
  DateTime? dueAt,
  DateTime? createdAt,
}) => GroupAssignment(
  id: id,
  teacherId: teacherId,
  groupId: groupId,
  movementId: 'movement-$id',
  revisionId: 'revision-$id',
  origin: MovementOrigin.officialElixr,
  assessmentMode: AssessmentMode.officialGuided,
  status: status,
  displayTitle: 'Hand Stall',
  teacherDisplayName: 'Teacher',
  groupName: 'Group 1',
  officialMovementName: 'Hand Stall',
  dueAt: dueAt,
  createdAt: createdAt,
);

AssignmentAttempt _attempt({
  required String id,
  required String assignmentId,
  required String traineeId,
  required AssignmentAttemptKind kind,
  required AssignmentAttemptStatus status,
  DateTime? createdAt,
  DateTime? abandonedAt,
}) {
  final isReview =
      kind == AssignmentAttemptKind.teacherReviewDraft ||
      kind == AssignmentAttemptKind.teacherReviewSubmission;
  return AssignmentAttempt(
    id: id,
    traineeId: traineeId,
    teacherId: _teacherId,
    groupId: 'group-1',
    assignmentId: assignmentId,
    movementId: 'movement-$assignmentId',
    revisionId: 'revision-$assignmentId',
    origin: isReview
        ? MovementOrigin.teacherCreated
        : MovementOrigin.officialElixr,
    assessmentMode: kind == AssignmentAttemptKind.templateScore
        ? AssessmentMode.templateScored
        : isReview
        ? AssessmentMode.teacherReviewed
        : AssessmentMode.officialGuided,
    attemptKind: kind,
    status: status,
    createdAt: createdAt,
    abandonedAt: abandonedAt,
  );
}

AnalyticsPeriodWindow _customWindow({
  DateTime? nowUtc,
  DateTime? start,
  DateTime? end,
}) => AnalyticsPeriodWindow.resolve(
  period: AnalyticsPeriod.custom,
  nowUtc: nowUtc ?? DateTime.utc(2026, 8, 20, 12),
  customStartDate: start ?? DateTime(2026, 8, 10),
  customEndDate: end ?? DateTime(2026, 8, 16),
);

AnalyticsSnapshot _calculate({
  required AnalyticsPeriodWindow window,
  required List<ElixrGroup> groups,
  required List<GroupMembership> memberships,
  List<GroupAssignment> assignments = const [],
  List<AssignmentAttempt> attempts = const [],
  Map<String, List<PublicProfileSession>> current = const {},
  Map<String, List<PublicProfileSession>> comparison = const {},
  AnalyticsScope scope = const AnalyticsScope.allClasses(),
  DateTime? nowUtc,
}) => AnalyticsCalculator.calculate(
  teacherId: _teacherId,
  groups: groups,
  memberships: memberships,
  assignments: assignments,
  attempts: attempts,
  currentSessionsByTrainee: current,
  comparisonSessionsByTrainee: comparison,
  scope: scope,
  periodWindow: window,
  nowUtc: nowUtc ?? DateTime.utc(2026, 8, 20, 12),
);

void main() {
  group('analytics period windows', () {
    test(
      'uses Manila calendar boundaries and equivalent elapsed comparisons',
      () {
        final now = DateTime.utc(2026, 8, 19, 10);
        final week = AnalyticsPeriodWindow.resolve(
          period: AnalyticsPeriod.thisWeek,
          nowUtc: now,
        );
        expect(week.current.startUtc, DateTime.utc(2026, 8, 16, 16));
        expect(week.current.endUtc, now);
        expect(week.comparison.startUtc, DateTime.utc(2026, 8, 9, 16));
        expect(week.comparison.endUtc, DateTime.utc(2026, 8, 12, 10));

        final month = AnalyticsPeriodWindow.resolve(
          period: AnalyticsPeriod.thisMonth,
          nowUtc: now,
        );
        expect(month.current.startUtc, DateTime.utc(2026, 7, 31, 16));
        expect(month.comparison.startUtc, DateTime.utc(2026, 6, 30, 16));
        expect(month.comparison.endUtc, DateTime.utc(2026, 7, 19, 10));

        final custom = _customWindow();
        expect(custom.current.startUtc, DateTime.utc(2026, 8, 9, 16));
        expect(custom.current.endUtc, DateTime.utc(2026, 8, 16, 16));
        expect(custom.comparison.startUtc, DateTime.utc(2026, 8, 2, 16));
        expect(custom.comparison.endUtc, DateTime.utc(2026, 8, 9, 16));
      },
    );

    test('validates future, reversed, and overlong custom ranges', () {
      final now = DateTime.utc(2026, 8, 19, 10);
      expect(
        () => AnalyticsPeriodWindow.resolve(
          period: AnalyticsPeriod.custom,
          nowUtc: now,
          customStartDate: DateTime(2026, 8, 12),
          customEndDate: DateTime(2026, 8, 11),
        ),
        throwsA(isA<AnalyticsRangeException>()),
      );
      expect(
        () => AnalyticsPeriodWindow.resolve(
          period: AnalyticsPeriod.custom,
          nowUtc: now,
          customStartDate: DateTime(2026, 8, 1),
          customEndDate: DateTime(2026, 10, 30),
        ),
        throwsA(isA<AnalyticsRangeException>()),
      );
      expect(
        () => AnalyticsPeriodWindow.resolve(
          period: AnalyticsPeriod.custom,
          nowUtc: now,
          customStartDate: DateTime(2026, 8, 18),
          customEndDate: DateTime(2026, 8, 20),
        ),
        throwsA(isA<AnalyticsRangeException>()),
      );
    });

    test('handles leap-day custom ranges', () {
      final window = AnalyticsPeriodWindow.resolve(
        period: AnalyticsPeriod.custom,
        nowUtc: DateTime.utc(2028, 3, 2, 12),
        customStartDate: DateTime(2028, 2, 1),
        customEndDate: DateTime(2028, 2, 29),
      );
      expect(window.current.duration, const Duration(days: 29));
      expect(window.current.endUtc, DateTime.utc(2028, 2, 29, 16));
      expect(window.comparison.duration, const Duration(days: 29));
    });
  });

  test(
    'weights students equally, includes zero-session students, and uses V2 only',
    () {
      final window = _customWindow();
      final snapshot = _calculate(
        window: window,
        groups: [_group()],
        memberships: [
          _membership(groupId: 'group-1', traineeId: 'a', name: 'Ada'),
          _membership(groupId: 'group-1', traineeId: 'b', name: 'Bea'),
          _membership(groupId: 'group-1', traineeId: 'c', name: 'Cleo'),
        ],
        current: {
          'a': [
            _session(
              id: 'a-before-approval',
              userId: 'a',
              createdAt: DateTime.utc(2026, 8, 9, 17),
              rubricTotal: 0,
            ),
            _session(
              id: 'a-1',
              userId: 'a',
              createdAt: DateTime.utc(2026, 8, 10, 17),
              rubricTotal: 12,
            ),
            _session(
              id: 'a-2',
              userId: 'a',
              createdAt: DateTime.utc(2026, 8, 11, 17),
              rubricTotal: 12,
            ),
            _session(
              id: 'a-legacy',
              userId: 'a',
              createdAt: DateTime.utc(2026, 8, 12, 17),
            ),
          ],
          'b': [
            _session(
              id: 'b-1',
              userId: 'b',
              createdAt: DateTime.utc(2026, 8, 13, 17),
              rubricTotal: 4,
            ),
          ],
        },
        comparison: {
          'a': [
            _session(
              id: 'a-prior',
              userId: 'a',
              createdAt: DateTime.utc(2026, 8, 3, 17),
              rubricTotal: 8,
            ),
          ],
          'b': [
            _session(
              id: 'b-prior-legacy',
              userId: 'b',
              createdAt: DateTime.utc(2026, 8, 4, 17),
            ),
          ],
        },
      );

      expect(snapshot.eligibleStudentCount, 3);
      expect(snapshot.sessionCount, 4);
      expect(snapshot.rubricSessionCount, 3);
      expect(snapshot.rubricStudentCount, 2);
      expect(snapshot.averageScore, closeTo(8, 0.0001));
      expect(snapshot.averagePracticeSessions, closeTo(4 / 3, 0.0001));
      expect(snapshot.improvement, isNull);
      expect(snapshot.matchedStudentCount, 0);
    },
  );

  test('computes improvement from the matched V2 student cohort', () {
    final window = _customWindow();
    final snapshot = _calculate(
      window: window,
      groups: [_group()],
      memberships: [
        _membership(
          groupId: 'group-1',
          traineeId: 'a',
          name: 'Ada',
          updatedAt: DateTime.utc(2026, 7, 1, 16),
        ),
        _membership(
          groupId: 'group-1',
          traineeId: 'b',
          name: 'Bea',
          updatedAt: DateTime.utc(2026, 7, 1, 16),
        ),
      ],
      current: {
        'a': [
          _session(
            id: 'a-current',
            userId: 'a',
            createdAt: DateTime.utc(2026, 8, 10, 17),
            rubricTotal: 10,
          ),
        ],
        'b': [
          _session(
            id: 'b-current-legacy',
            userId: 'b',
            createdAt: DateTime.utc(2026, 8, 11, 17),
          ),
        ],
      },
      comparison: {
        'a': [
          _session(
            id: 'a-prior',
            userId: 'a',
            createdAt: DateTime.utc(2026, 8, 3, 17),
            rubricTotal: 6,
          ),
        ],
        'b': [
          _session(
            id: 'b-prior-legacy',
            userId: 'b',
            createdAt: DateTime.utc(2026, 8, 4, 17),
          ),
        ],
      },
    );

    expect(snapshot.improvement, closeTo(4, 0.0001));
    expect(snapshot.matchedStudentCount, 1);
  });

  test(
    'deduplicates all-class roster and keeps group comparisons independent',
    () {
      final groups = [
        _group(id: 'group-1', name: 'Alpha'),
        _group(id: 'group-2', name: 'Beta'),
        _group(
          id: 'archived',
          name: 'Archived',
          status: ElixrGroupStatus.archived,
        ),
        _group(id: 'other-teacher', teacherId: 'other', name: 'Other'),
      ];
      final memberships = [
        _membership(groupId: 'group-1', traineeId: 'shared', name: 'Shared'),
        _membership(groupId: 'group-2', traineeId: 'shared', name: 'Shared'),
        _membership(
          groupId: 'group-1',
          traineeId: 'pending',
          status: GroupMembershipStatus.pending,
        ),
        _membership(groupId: 'archived', traineeId: 'archived'),
        _membership(
          groupId: 'other-teacher',
          traineeId: 'other',
          teacherId: 'other',
        ),
        _membership(
          groupId: 'group-1',
          traineeId: 'removed',
          status: GroupMembershipStatus.removed,
        ),
      ];

      final all = AnalyticsCalculator.eligibleStudents(
        teacherId: _teacherId,
        groups: groups,
        memberships: memberships,
        scope: const AnalyticsScope.allClasses(),
      );
      expect(all.map((student) => student.traineeId), ['shared']);
      expect(
        AnalyticsCalculator.eligibleStudents(
          teacherId: _teacherId,
          groups: groups,
          memberships: memberships,
          scope: const AnalyticsScope.group('group-1'),
        ).map((student) => student.traineeId),
        ['shared'],
      );

      final snapshot = _calculate(
        window: _customWindow(),
        groups: groups,
        memberships: memberships,
      );
      expect(snapshot.groupComparisons, hasLength(2));
      expect(
        snapshot.groupComparisons.map((comparison) => comparison.group.id),
        ['group-1', 'group-2'],
      );
      expect(
        snapshot.groupComparisons.map(
          (comparison) => comparison.eligibleStudentCount,
        ),
        [1, 1],
      );
    },
  );

  test(
    'uses due-date fallback, archived assignments, and shared completion semantics',
    () {
      final period = _customWindow();
      final due = DateTime.utc(2026, 8, 12, 17);
      final assignments = [
        _assignment(id: 'dated', dueAt: due),
        _assignment(
          id: 'archived',
          status: GroupAssignmentStatus.archived,
          dueAt: DateTime.utc(2026, 8, 13, 17),
        ),
        _assignment(
          id: 'undated',
          dueAt: null,
          createdAt: DateTime.utc(2026, 8, 14, 17),
        ),
        _assignment(id: 'future', dueAt: DateTime.utc(2026, 8, 21, 17)),
        _assignment(id: 'outside', dueAt: DateTime.utc(2026, 8, 1, 17)),
        _assignment(id: 'foreign', teacherId: 'other', dueAt: due),
      ];
      final attempts = [
        _attempt(
          id: 'dated-a',
          assignmentId: 'dated',
          traineeId: 'a',
          kind: AssignmentAttemptKind.practicePointer,
          status: AssignmentAttemptStatus.submitted,
        ),
        _attempt(
          id: 'dated-b-draft',
          assignmentId: 'dated',
          traineeId: 'b',
          kind: AssignmentAttemptKind.teacherReviewDraft,
          status: AssignmentAttemptStatus.draft,
        ),
        _attempt(
          id: 'archived-a',
          assignmentId: 'archived',
          traineeId: 'a',
          kind: AssignmentAttemptKind.templateScore,
          status: AssignmentAttemptStatus.submitted,
        ),
        _attempt(
          id: 'archived-b',
          assignmentId: 'archived',
          traineeId: 'b',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.needsRetry,
        ),
        _attempt(
          id: 'undated-a',
          assignmentId: 'undated',
          traineeId: 'a',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.checked,
        ),
      ];
      final snapshot = _calculate(
        window: period,
        groups: [_group()],
        memberships: [
          _membership(groupId: 'group-1', traineeId: 'a', name: 'Ada'),
          _membership(groupId: 'group-1', traineeId: 'b', name: 'Bea'),
        ],
        assignments: assignments,
        attempts: attempts,
      );

      expect(snapshot.expectedSubmissionCount, 6);
      expect(snapshot.turnedInSubmissionCount, 4);
      expect(snapshot.completionRate, closeTo(2 / 3, 0.0001));
    },
  );

  test('returns no completion percentage without expected work', () {
    final snapshot = _calculate(
      window: _customWindow(),
      groups: [_group()],
      memberships: [_membership(groupId: 'group-1', traineeId: 'a')],
    );
    expect(snapshot.completionRate, isNull);
    expect(snapshot.expectedSubmissionCount, 0);
    expect(snapshot.averagePracticeSessions, 0);
    expect(snapshot.averageScore, isNull);
  });

  test('completion counts only the private targeted recipient set', () {
    final snapshot = _calculate(
      window: _customWindow(),
      groups: [_group()],
      memberships: [
        _membership(groupId: 'group-1', traineeId: 'a', name: 'Ada'),
        _membership(groupId: 'group-1', traineeId: 'b', name: 'Bea'),
        _membership(groupId: 'group-1', traineeId: 'c', name: 'Cleo'),
      ],
      assignments: [
        _assignment(
          id: 'targeted',
          dueAt: DateTime.utc(2026, 8, 12, 17),
        ).copyWith(
          audience: AssignmentAudience.selectedStudents(const ['a', 'b']),
        ),
      ],
      attempts: [
        _attempt(
          id: 'targeted-a',
          assignmentId: 'targeted',
          traineeId: 'a',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.checked,
        ),
      ],
    );

    expect(snapshot.expectedSubmissionCount, 2);
    expect(snapshot.turnedInSubmissionCount, 1);
    expect(snapshot.completionRate, closeTo(0.5, 0.0001));
  });

  test(
    'finds most-practiced and hardest movements with deterministic ties',
    () {
      final sessions = <String, List<PublicProfileSession>>{
        'a': [
          for (var index = 0; index < 2; index++)
            _session(
              id: 'alpha-a-$index',
              userId: 'a',
              movementName: 'Alpha',
              createdAt: DateTime.utc(2026, 8, 10, 17 + index),
              rubricTotal: 4,
            ),
          for (var index = 0; index < 2; index++)
            _session(
              id: 'beta-a-$index',
              userId: 'a',
              movementName: 'Beta',
              createdAt: DateTime.utc(2026, 8, 11, 17 + index),
              rubricTotal: 4,
            ),
          _session(
            id: 'gamma-a',
            userId: 'a',
            movementName: 'Gamma',
            createdAt: DateTime.utc(2026, 8, 12, 17),
            rubricTotal: 0,
          ),
          _session(
            id: 'gamma-a-2',
            userId: 'a',
            movementName: 'Gamma',
            createdAt: DateTime.utc(2026, 8, 12, 18),
            rubricTotal: 0,
          ),
        ],
        'b': [
          _session(
            id: 'alpha-b',
            userId: 'b',
            movementName: 'Alpha',
            createdAt: DateTime.utc(2026, 8, 13, 17),
            rubricTotal: 4,
          ),
          _session(
            id: 'beta-b',
            userId: 'b',
            movementName: 'Beta',
            createdAt: DateTime.utc(2026, 8, 13, 18),
            rubricTotal: 4,
          ),
        ],
      };
      final snapshot = _calculate(
        window: _customWindow(),
        groups: [_group()],
        memberships: [
          _membership(groupId: 'group-1', traineeId: 'a'),
          _membership(groupId: 'group-1', traineeId: 'b'),
        ],
        current: sessions,
      );

      expect(snapshot.mostPracticed?.movementName, 'Alpha');
      expect(snapshot.mostPracticed?.sessionCount, 3);
      expect(snapshot.mostPracticed?.distinctStudentCount, 2);
      expect(snapshot.hardest?.movementName, 'Alpha');
      expect(snapshot.hardest?.averageScore, closeTo(4, 0.0001));
      expect(snapshot.hardest?.sessionCount, 3);
      expect(snapshot.hardest?.distinctStudentCount, 2);
    },
  );

  test('classifies all supported attempt states consistently', () {
    for (final status in [
      AssignmentAttemptStatus.draft,
      AssignmentAttemptStatus.inProgress,
      AssignmentAttemptStatus.unsubmitting,
    ]) {
      expect(
        isAssignmentAttemptTurnedIn(
          _attempt(
            id: 'pointer-${status.name}',
            assignmentId: 'assignment',
            traineeId: 'a',
            kind: AssignmentAttemptKind.practicePointer,
            status: status,
          ),
        ),
        isFalse,
      );
    }
    for (final status in [
      AssignmentAttemptStatus.submitted,
      AssignmentAttemptStatus.checked,
      AssignmentAttemptStatus.approved,
      AssignmentAttemptStatus.needsRetry,
    ]) {
      expect(
        isAssignmentAttemptTurnedIn(
          _attempt(
            id: 'pointer-${status.name}',
            assignmentId: 'assignment',
            traineeId: 'a',
            kind: AssignmentAttemptKind.practicePointer,
            status: status,
          ),
        ),
        isTrue,
      );
      expect(
        isAssignmentAttemptTurnedIn(
          _attempt(
            id: 'review-${status.name}',
            assignmentId: 'assignment',
            traineeId: 'a',
            kind: AssignmentAttemptKind.teacherReviewSubmission,
            status: status,
          ),
        ),
        isTrue,
      );
    }
    expect(
      isAssignmentAttemptTurnedIn(
        _attempt(
          id: 'abandoned',
          assignmentId: 'assignment',
          traineeId: 'a',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.draft,
          abandonedAt: _approval,
        ),
      ),
      isFalse,
    );
  });

  test('uses daily buckets through 31 days and weekly buckets afterwards', () {
    final daily = _calculate(
      window: _customWindow(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        nowUtc: DateTime.utc(2026, 9, 2, 12),
      ),
      groups: [_group()],
      memberships: [_membership(groupId: 'group-1', traineeId: 'a')],
    );
    expect(daily.trendBuckets, hasLength(31));

    final weekly = _calculate(
      window: _customWindow(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 8, 31),
        nowUtc: DateTime.utc(2026, 9, 2, 12),
      ),
      groups: [_group()],
      memberships: [_membership(groupId: 'group-1', traineeId: 'a')],
    );
    expect(weekly.trendBuckets, hasLength(9));
  });
}
