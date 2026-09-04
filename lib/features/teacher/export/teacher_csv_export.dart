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
    final rows = <List<_CsvCell>>[
      [
        _generated('Student name'),
        for (final assignment in assignments) _text(assignment.displayTitle),
      ],
      for (final student in students)
        [
          _text(student.traineeDisplayName),
          for (final assignment in assignments)
            _generated(
              _gradebookCell(
                TeacherGradebookSemantics.cellFor(
                  membership: student,
                  assignment: assignment,
                  attempt: attemptFor(assignment.id, student.traineeId),
                  attemptUnavailable: attemptUnavailable(assignment.id),
                  now: referenceNow,
                ),
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
    final rows = <List<_CsvCell>>[
      [_generated('ELIXR Analytics')],
      [_generated('Class'), _text(classLabel)],
      [_generated('Period'), _text(periodLabel)],
      [
        _generated('Period start (UTC)'),
        _generated(snapshot.periodWindow.current.startUtc.toIso8601String()),
      ],
      [
        _generated('Period end (UTC)'),
        _generated(snapshot.periodWindow.current.endUtc.toIso8601String()),
      ],
      [],
      [_generated('Summary')],
      [_generated('Metric'), _generated('Value')],
      [
        _generated('Eligible students'),
        _generated('${snapshot.eligibleStudentCount}'),
      ],
      [_generated('Practice sessions'), _generated('${snapshot.sessionCount}')],
      [
        _generated('Average class score (out of 12)'),
        _generated(optional(snapshot.averageScore)),
      ],
      [
        _generated('Average practice sessions per student'),
        _generated(optional(snapshot.averagePracticeSessions)),
      ],
      [
        _generated('Assignment completion rate'),
        _generated(percent(snapshot.completionRate)),
      ],
      [
        _generated('Expected submissions'),
        _generated('${snapshot.expectedSubmissionCount}'),
      ],
      [
        _generated('Turned in submissions'),
        _generated('${snapshot.turnedInSubmissionCount}'),
      ],
      [
        _generated('Score change / improvement'),
        _generated(optional(snapshot.improvement)),
      ],
      [
        _generated('Students compared'),
        _generated('${snapshot.matchedStudentCount}'),
      ],
      [],
      [_generated('Score progress')],
      [
        _generated('Period'),
        _generated('Sessions'),
        _generated('Students'),
        _generated('Average score (out of 12)'),
      ],
      for (final trend in snapshot.trendBuckets)
        [
          _generated(trend.label),
          _generated('${trend.sessionCount}'),
          _generated('${trend.distinctStudentCount}'),
          _generated(optional(trend.averageScore)),
        ],
      [],
      [_generated('Movement insights')],
      [
        _generated('Insight'),
        _generated('Movement'),
        _generated('Sessions'),
        _generated('Students'),
        _generated('Average score (out of 12)'),
      ],
      _insightRow('Most practiced', snapshot.mostPracticed, optional),
      _insightRow('Most challenging', snapshot.hardest, optional),
      [],
      [_generated('Class comparison')],
      [
        _generated('Class'),
        _generated('Students'),
        _generated('Sessions'),
        _generated('Average score (out of 12)'),
        _generated('Practice sessions per student'),
        _generated('Completion rate'),
        _generated('Score change / improvement'),
      ],
      for (final comparison in snapshot.groupComparisons)
        [
          _text(comparison.group.name),
          _generated('${comparison.eligibleStudentCount}'),
          _generated('${comparison.sessionCount}'),
          _generated(optional(comparison.averageScore)),
          _generated(optional(comparison.averagePracticeSessions)),
          _generated(percent(comparison.completionRate)),
          _generated(optional(comparison.improvement)),
        ],
    ];
    return _csv(rows);
  }

  static List<_CsvCell> _insightRow(
    String label,
    MovementInsight? insight,
    String Function(double?, {int digits}) optional,
  ) => insight == null
      ? [
          _generated(label),
          _generated('N/A'),
          _generated('N/A'),
          _generated('N/A'),
          _generated('N/A'),
        ]
      : [
          _generated(label),
          _text(insight.movementName),
          _generated('${insight.sessionCount}'),
          _generated('${insight.distinctStudentCount}'),
          _generated(optional(insight.averageScore)),
        ];

  static String _gradebookCell(TeacherGradebookCell cell) =>
      cell.detail == null || cell.detail!.isEmpty
      ? cell.label
      : '${cell.label} (${cell.detail})';

  static _CsvCell _text(String value) => _CsvCell.text(value);

  static _CsvCell _generated(String value) => _CsvCell.generated(value);

  static String _csv(Iterable<List<_CsvCell>> rows) =>
      '\uFEFF${rows.map((row) => row.map(_field).join(',')).join('\r\n')}\r\n';

  static String _field(_CsvCell cell) {
    final sanitized = cell.isUntrustedText
        ? _neutralizeFormula(cell.value)
        : cell.value;
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

class _CsvCell {
  const _CsvCell.text(this.value) : isUntrustedText = true;
  const _CsvCell.generated(this.value) : isUntrustedText = false;

  final String value;
  final bool isUntrustedText;
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
