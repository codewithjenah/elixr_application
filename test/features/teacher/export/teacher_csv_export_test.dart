import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_models.dart';
import 'package:elixr_application/features/teacher/export/teacher_csv_export.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 4);
  const student = GroupMembership(
    id: 'm',
    groupId: 'g',
    teacherId: 't',
    traineeId: 's',
    traineeDisplayName: 'Ada, "Ace"\nÅngström',
    teacherDisplayName: 'Teacher',
    status: GroupMembershipStatus.approved,
  );

  GroupAssignment assignment({
    required String id,
    required String title,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? dueAt,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => GroupAssignment(
    id: id,
    teacherId: 't',
    groupId: 'g',
    movementId: 'move',
    revisionId: 'rev',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    status: status,
    displayTitle: title,
    teacherDisplayName: 'Teacher',
    groupName: 'Class',
    maxScore: 20,
    audience: audience,
    dueAt: dueAt,
  );

  AssignmentAttempt checked(String assignmentId) => AssignmentAttempt(
    id: 'attempt',
    traineeId: 's',
    teacherId: 't',
    groupId: 'g',
    assignmentId: assignmentId,
    movementId: 'move',
    revisionId: 'rev',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.checked,
    gradeScore: 18,
    gradeMaxScore: 20,
    checkedAt: now,
    reviewUpdatedAt: now,
    reviewRevision: 1,
  );

  String gradebook(
    List<GroupAssignment> assignments, {
    Set<String> unavailable = const {},
  }) => TeacherCsvExport.gradebook(
    students: [student],
    assignments: assignments,
    attemptFor: (assignmentId, _) {
      if (assignmentId == 'scored') return checked(assignmentId);
      if (assignmentId == 'review') {
        return AssignmentAttempt(
          id: 'submitted',
          traineeId: 's',
          teacherId: 't',
          groupId: 'g',
          assignmentId: assignmentId,
          movementId: 'move',
          revisionId: 'rev',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          submittedAt: now,
        );
      }
      return null;
    },
    attemptUnavailable: unavailable.contains,
    referenceNow: now,
  );

  test(
    'exports canonical scored and review states without replacing them by zero',
    () {
      final csv = gradebook(
        [
          assignment(id: 'scored', title: 'Scored'),
          assignment(id: 'review', title: 'Review'),
          assignment(
            id: 'missing',
            title: 'Missing',
            dueAt: DateTime.utc(2026, 9, 5),
          ),
          assignment(
            id: 'overdue',
            title: 'Overdue',
            dueAt: DateTime.utc(2026, 9, 3),
          ),
          assignment(id: 'unavailable', title: 'Unavailable'),
        ],
        unavailable: {'unavailable'},
      );

      expect(csv, contains('18/20 (90%)'));
      expect(csv, contains('To Review'));
      expect(csv, contains('Missing'));
      expect(csv, contains('Overdue'));
      expect(csv, contains('Unavailable'));
      expect(csv, isNot(contains(',0,')));
    },
  );

  test('exports targeted non-recipients as Not assigned', () {
    final csv = gradebook([
      assignment(
        id: 'targeted',
        title: 'Targeted',
        audience: AssignmentAudience.selectedStudents(const ['other']),
      ),
    ]);
    expect(csv, contains('Not assigned'));
  });

  test(
    'escapes CSV-sensitive, Unicode, multiline, and formula-capable text',
    () {
      final csv = gradebook([
        assignment(id: 'one', title: '=SUM(A1:A2), "quoted"\n日本語'),
        assignment(id: 'two', title: '+cmd'),
        assignment(id: 'three', title: '-1+1'),
        assignment(id: 'four', title: '@value'),
      ]);

      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains("'=SUM(A1:A2), \"\"quoted\"\"\n日本語"));
      expect(csv, contains('"Ada, ""Ace""\nÅngström"'));
      expect(csv, contains("'+cmd"));
      expect(csv, contains("'-1+1"));
      expect(csv, contains("'@value"));
    },
  );

  test('scope-selected assignments alone are included by the caller', () {
    final active = assignment(id: 'active', title: 'Active');
    final archived = assignment(
      id: 'archived',
      title: 'Archived',
      status: GroupAssignmentStatus.archived,
    );
    final csv = gradebook([active]);
    expect(csv, contains('Active'));
    expect(csv, isNot(contains('Archived')));
    expect(archived.isActive, isFalse);
  });

  test(
    'analytics export retains selected filter and does not turn nulls into zeroes',
    () {
      const group = ElixrGroup(
        id: 'g',
        teacherId: 't',
        name: 'Class, A',
        status: ElixrGroupStatus.active,
      );
      final range = AnalyticsRange(
        startUtc: now.subtract(const Duration(days: 7)),
        endUtc: now,
      );
      final snapshot = AnalyticsSnapshot(
        scope: const AnalyticsScope.group('g'),
        periodWindow: AnalyticsPeriodWindow(
          current: range,
          comparison: range,
          period: AnalyticsPeriod.thisWeek,
        ),
        eligibleStudentCount: 1,
        sessionCount: 0,
        rubricSessionCount: 0,
        rubricStudentCount: 0,
        averageScore: null,
        averagePracticeSessions: null,
        completionRate: null,
        expectedSubmissionCount: 0,
        turnedInSubmissionCount: 0,
        improvement: -1.2,
        matchedStudentCount: 0,
        trendBuckets: const [],
        mostPracticed: null,
        hardest: null,
        groupComparisons: const [
          GroupComparison(
            group: group,
            eligibleStudentCount: 1,
            sessionCount: 2,
            averageScore: 8.5,
            averagePracticeSessions: 2,
            completionRate: 0.5,
            improvement: -2.3,
            expectedSubmissionCount: 2,
            turnedInSubmissionCount: 1,
            matchedStudentCount: 1,
          ),
        ],
      );
      final csv = TeacherCsvExport.analytics(
        snapshot: snapshot,
        classLabel: group.name,
        periodLabel: 'This Week',
      );

      expect(csv, contains('"Class, A"'));
      expect(csv, contains('This Week'));
      expect(csv, contains('N/A'));
      expect(csv, contains('Score change / improvement,-1.2'));
      expect(csv, isNot(contains("Score change / improvement,'-1.2")));
      expect(csv, contains(',-2.3\r\n'));
      expect(csv, isNot(contains(",'-2.3")));
      expect(csv, isNot(contains('Average class score (out of 12),0.0')));
    },
  );
}
