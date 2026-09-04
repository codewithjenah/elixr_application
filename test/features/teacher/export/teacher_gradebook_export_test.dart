import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/export/teacher_gradebook_export.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const student = GroupMembership(
    id: 'm',
    groupId: 'g',
    teacherId: 't',
    traineeId: 's',
    traineeDisplayName: 'Ada, "Ace"',
    teacherDisplayName: 'T',
    status: GroupMembershipStatus.approved,
  );
  final assignment = GroupAssignment(
    id: 'a',
    teacherId: 't',
    groupId: 'g',
    movementId: 'move',
    revisionId: 'r',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Spin\nPractice',
    teacherDisplayName: 'T',
    groupName: 'Class',
    topic: 'Control',
    maxScore: 20,
    dueAt: DateTime.utc(2026, 9, 4, 10),
  );
  final attempt = AssignmentAttempt(
    id: 'a',
    traineeId: 's',
    teacherId: 't',
    groupId: 'g',
    assignmentId: 'a',
    movementId: 'move',
    revisionId: 'r',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.checked,
    gradeScore: 18,
    gradeMaxScore: 20,
    submittedAt: DateTime.utc(2026, 9, 4, 9),
    checkedAt: DateTime.utc(2026, 9, 4, 11),
  );

  List<GradebookExportRow> rows(AssignmentAttempt? value) =>
      TeacherGradebookExportService.rows(
        students: [student],
        assignments: [assignment],
        attemptFor: (_, _) => value,
        attemptUnavailable: (_) => false,
        referenceNow: DateTime.utc(2026, 9, 4),
      );

  test(
    'maps checked scores, optional topic, Manila timestamps, and timing',
    () {
      final row = rows(attempt).single;
      expect(row.score, 18);
      expect(row.maximumScore, 20);
      expect(row.percentage, 90);
      expect(row.status, '18/20');
      expect(row.timing, 'On time');
      expect(
        TeacherGradebookExportService.csv([row]),
        contains('2026-09-04 5:00 PM'),
      );
    },
  );

  test('ungraded values stay blank and CSV escapes untrusted text', () {
    final csv = TeacherGradebookExportService.csv(rows(null));
    expect(csv, contains('"Ada, ""Ace"""'));
    expect(csv, contains('"Spin\nPractice"'));
    expect(csv, contains('Missing'));
    expect(csv, isNot(contains('NaN')));
  });

  test('creates a readable Gradebook workbook with numeric scores', () {
    final bytes = TeacherGradebookExportService.xlsx(rows(attempt));
    expect(bytes, isNotEmpty);
    final workbook = Excel.decodeBytes(bytes);
    final sheet = workbook.tables['Gradebook'];
    expect(sheet, isNotNull);
    expect(
      sheet!.cell(CellIndex.indexByString('A1')).value?.toString(),
      contains('Trainee'),
    );
    expect(
      sheet.cell(CellIndex.indexByString('A2')).value?.toString(),
      contains('Ada'),
    );
    expect(
      sheet.cell(CellIndex.indexByString('F2')).value?.toString(),
      contains('18'),
    );
  });

  test('sanitizes Windows filenames and preserves format extension', () {
    final now = DateTime.utc(2026, 9, 4);
    expect(
      TeacherGradebookExportService.filename(
        className: ' .<>Bad? ',
        now: now,
        format: TeacherGradebookExportFormat.csv,
      ),
      endsWith('.csv'),
    );
    expect(
      TeacherGradebookExportService.filename(
        className: '...',
        now: now,
        format: TeacherGradebookExportFormat.xlsx,
      ),
      contains('Gradebook_2026-09-04.xlsx'),
    );
  });
}
