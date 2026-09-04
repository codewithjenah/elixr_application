import 'dart:convert';
import 'dart:io';

import 'package:elixr_core/models/group_membership.dart';
import 'package:file_selector/file_selector.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../analytics/teacher_analytics_models.dart';
import '../classwork/teacher_gradebook.dart';

/// Pure CSV serialization for teacher-owned data already loaded by the UI.
abstract final class TeacherCsvExport {
  static String gradebook({
    required Iterable<GroupMembership> students,
    required Iterable<GroupAssignment> assignments,
    required AssignmentAttempt? Function(String assignmentId, String traineeId)
    attemptFor,
    required bool Function(String assignmentId) attemptUnavailable,
    required DateTime referenceNow,
  }) {
    final rows = <List<String>>[
      [
        'Student name',
        for (final assignment in assignments) assignment.displayTitle,
      ],
      for (final student in students)
        [
          student.traineeDisplayName,
          for (final assignment in assignments)
            _gradebookCell(
              TeacherGradebookSemantics.cellFor(
                membership: student,
                assignment: assignment,
                attempt: attemptFor(assignment.id, student.traineeId),
                attemptUnavailable: attemptUnavailable(assignment.id),
                now: referenceNow,
              ),
            ),
        ],
    ];
    return _csv(rows);
  }

  static String analytics({
    required AnalyticsSnapshot snapshot,
    required String classLabel,
    required String periodLabel,
  }) {
    String optional(double? value, {int digits = 1}) =>
        value == null ? 'N/A' : value.toStringAsFixed(digits);
    String percent(double? value) =>
        value == null ? 'N/A' : '${(value * 100).toStringAsFixed(1)}%';
    final rows = <List<String>>[
      ['ELIXR Analytics'],
      ['Class', classLabel],
      ['Period', periodLabel],
      [
        'Period start (UTC)',
        snapshot.periodWindow.current.startUtc.toIso8601String(),
      ],
      [
        'Period end (UTC)',
        snapshot.periodWindow.current.endUtc.toIso8601String(),
      ],
      [],
      ['Summary'],
      ['Metric', 'Value'],
      ['Eligible students', '${snapshot.eligibleStudentCount}'],
      ['Practice sessions', '${snapshot.sessionCount}'],
      ['Average class score (out of 12)', optional(snapshot.averageScore)],
      [
        'Average practice sessions per student',
        optional(snapshot.averagePracticeSessions),
      ],
      ['Assignment completion rate', percent(snapshot.completionRate)],
      ['Expected submissions', '${snapshot.expectedSubmissionCount}'],
      ['Turned in submissions', '${snapshot.turnedInSubmissionCount}'],
      ['Score change / improvement', optional(snapshot.improvement)],
      ['Students compared', '${snapshot.matchedStudentCount}'],
      [],
      ['Score progress'],
      ['Period', 'Sessions', 'Students', 'Average score (out of 12)'],
      for (final trend in snapshot.trendBuckets)
        [
          trend.label,
          '${trend.sessionCount}',
          '${trend.distinctStudentCount}',
          optional(trend.averageScore),
        ],
      [],
      ['Movement insights'],
      [
        'Insight',
        'Movement',
        'Sessions',
        'Students',
        'Average score (out of 12)',
      ],
      _insightRow('Most practiced', snapshot.mostPracticed, optional),
      _insightRow('Most challenging', snapshot.hardest, optional),
      [],
      ['Class comparison'],
      [
        'Class',
        'Students',
        'Sessions',
        'Average score (out of 12)',
        'Practice sessions per student',
        'Completion rate',
        'Score change / improvement',
      ],
      for (final comparison in snapshot.groupComparisons)
        [
          comparison.group.name,
          '${comparison.eligibleStudentCount}',
          '${comparison.sessionCount}',
          optional(comparison.averageScore),
          optional(comparison.averagePracticeSessions),
          percent(comparison.completionRate),
          optional(comparison.improvement),
        ],
    ];
    return _csv(rows);
  }

  static List<String> _insightRow(
    String label,
    MovementInsight? insight,
    String Function(double?, {int digits}) optional,
  ) => insight == null
      ? [label, 'N/A', 'N/A', 'N/A', 'N/A']
      : [
          label,
          insight.movementName,
          '${insight.sessionCount}',
          '${insight.distinctStudentCount}',
          optional(insight.averageScore),
        ];

  static String _gradebookCell(TeacherGradebookCell cell) =>
      cell.detail == null || cell.detail!.isEmpty
      ? cell.label
      : '${cell.label} (${cell.detail})';

  static String _csv(Iterable<List<String>> rows) =>
      '\uFEFF${rows.map((row) => row.map(_field).join(',')).join('\r\n')}\r\n';

  static String _field(String value) {
    final sanitized = _neutralizeFormula(value);
    if (!sanitized.contains(RegExp('[,\\"\\r\\n]'))) return sanitized;
    return '"${sanitized.replaceAll('"', '""')}"';
  }

  static String _neutralizeFormula(String value) {
    if (value.isNotEmpty && '=+-@'.contains(value[0])) return "'$value";
    return value;
  }

  static String safeFilenamePart(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    return cleaned.isEmpty ? 'Export' : cleaned;
  }
}

abstract interface class TeacherCsvFileSaver {
  Future<String?> save({required String suggestedName, required String csv});
}

class WindowsTeacherCsvFileSaver implements TeacherCsvFileSaver {
  const WindowsTeacherCsvFileSaver();

  @override
  Future<String?> save({
    required String suggestedName,
    required String csv,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV files', extensions: ['csv']),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsBytes(utf8.encode(csv), flush: true);
    return location.path;
  }
}
