import 'dart:convert';
import 'dart:io';

import 'package:elixr_core/models/group_membership.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../classwork/teacher_gradebook.dart';
import 'teacher_csv_export.dart';

enum TeacherGradebookExportFormat { csv, xlsx }

/// A read-only, presentation-safe snapshot of a single gradebook cell.
class GradebookExportRow {
  const GradebookExportRow({
    required this.traineeName,
    required this.activity,
    required this.topic,
    required this.type,
    required this.status,
    required this.score,
    required this.maximumScore,
    required this.percentage,
    required this.submittedAt,
    required this.checkedAt,
    required this.dueAt,
    required this.timing,
  });

  final String traineeName;
  final String activity;
  final String? topic;
  final String type;
  final String status;
  final num? score;
  final num? maximumScore;
  final double? percentage;
  final DateTime? submittedAt;
  final DateTime? checkedAt;
  final DateTime? dueAt;
  final String? timing;
}

abstract final class TeacherGradebookExportService {
  static const headers = [
    'Trainee',
    'Activity',
    'Topic',
    'Type',
    'Status',
    'Score',
    'Maximum Score',
    'Percentage',
    'Submitted',
    'Checked',
    'Due Date',
    'Timing',
  ];

  static List<GradebookExportRow> rows({
    required Iterable<GroupMembership> students,
    required Iterable<GroupAssignment> assignments,
    required AssignmentAttempt? Function(String assignmentId, String traineeId)
    attemptFor,
    required bool Function(String assignmentId) attemptUnavailable,
    required DateTime referenceNow,
  }) => [
    for (final student in students)
      for (final assignment in assignments)
        _row(
          student: student,
          assignment: assignment,
          attempt: attemptFor(assignment.id, student.traineeId),
          unavailable: attemptUnavailable(assignment.id),
          now: referenceNow,
        ),
  ];

  static GradebookExportRow _row({
    required GroupMembership student,
    required GroupAssignment assignment,
    required AssignmentAttempt? attempt,
    required bool unavailable,
    required DateTime now,
  }) {
    final cell = TeacherGradebookSemantics.cellFor(
      membership: student,
      assignment: assignment,
      attempt: attempt,
      attemptUnavailable: unavailable,
      now: now,
    );
    num? score;
    num? maximum;
    if (cell.state == TeacherGradebookCellState.scored && attempt != null) {
      if (assignment.isTeacherCreated &&
          attempt.isChecked &&
          attempt.gradeScore != null &&
          attempt.gradeMaxScore != null &&
          attempt.gradeMaxScore! > 0) {
        score = attempt.gradeScore;
        maximum = attempt.gradeMaxScore;
      } else if ((assignment.isOfficial || assignment.isRetiredTemplate) &&
          attempt.rubricTotal != null &&
          attempt.rubricTotal! >= 0 &&
          attempt.rubricTotal! <= 12) {
        score = attempt.rubricTotal;
        maximum = 12;
      }
    }
    final percentage = score != null && maximum != null && maximum > 0
        ? (score / maximum * 100).toDouble()
        : null;
    final submitted = attempt?.submittedAt;
    final due = assignment.dueAt;
    final timing = submitted == null || due == null
        ? null
        : submitted.toUtc().isAfter(due.toUtc())
        ? 'Late'
        : 'On time';
    return GradebookExportRow(
      traineeName: student.traineeDisplayName,
      activity: assignment.displayTitle,
      topic: assignment.topic,
      type: assignment.isOfficial ? 'Official ELIXR' : 'Teacher-created',
      status: cell.label,
      score: score,
      maximumScore: maximum,
      percentage: percentage,
      submittedAt: submitted,
      checkedAt: attempt?.checkedAt,
      dueAt: due,
      timing: timing,
    );
  }

  static String csv(Iterable<GradebookExportRow> rows) =>
      TeacherCsvExport.rows(headers: headers, rows: rows.map(_csvValues));
  static List<int> csvBytes(Iterable<GradebookExportRow> rows) =>
      utf8.encode(csv(rows));

  static List<int> xlsx(Iterable<GradebookExportRow> rows) {
    final excel = Excel.createExcel();
    final sheet = excel['Gradebook'];
    excel.delete('Sheet1');
    sheet.appendRow(headers.map((value) => TextCellValue(value)).toList());
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
    );
    for (var column = 0; column < headers.length; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
              )
              .cellStyle =
          headerStyle;
    }
    for (final row in rows) {
      sheet.appendRow(_xlsxValues(row));
    }
    for (var column = 0; column < headers.length; column++) {
      sheet.setColumnWidth(column, column < 5 ? 22 : 18);
    }
    return excel.encode()!;
  }

  static List<String> _csvValues(GradebookExportRow row) => [
    row.traineeName,
    row.activity,
    row.topic ?? '',
    row.type,
    row.status,
    _number(row.score),
    _number(row.maximumScore),
    _percentage(row.percentage),
    _date(row.submittedAt),
    _date(row.checkedAt),
    _date(row.dueAt),
    row.timing ?? '',
  ];

  static List<CellValue> _xlsxValues(GradebookExportRow row) => [
    TextCellValue(row.traineeName),
    TextCellValue(row.activity),
    TextCellValue(row.topic ?? ''),
    TextCellValue(row.type),
    TextCellValue(row.status),
    _numberCell(row.score),
    _numberCell(row.maximumScore),
    _numberCell(row.percentage),
    TextCellValue(_date(row.submittedAt)),
    TextCellValue(_date(row.checkedAt)),
    TextCellValue(_date(row.dueAt)),
    TextCellValue(row.timing ?? ''),
  ];

  static CellValue _numberCell(num? value) => value == null
      ? TextCellValue('')
      : value is int
      ? IntCellValue(value)
      : DoubleCellValue(value.toDouble());
  static String _number(num? value) => value?.toString() ?? '';
  static String _percentage(double? value) =>
      value == null ? '' : '${value.toStringAsFixed(1)}%';
  static String _date(DateTime? value) {
    if (value == null) return '';
    final manila = value.toUtc().add(const Duration(hours: 8));
    return DateFormat('yyyy-MM-dd h:mm a', 'en_US').format(manila);
  }

  static String filename({
    required String className,
    required DateTime now,
    required TeacherGradebookExportFormat format,
  }) {
    final stem = TeacherCsvExport.safeFilenamePart(className, fallback: '');
    final date = DateFormat(
      'yyyy-MM-dd',
    ).format(now.toUtc().add(const Duration(hours: 8)));
    final prefix = stem.isEmpty ? 'ELIXR_Gradebook' : 'ELIXR_${stem}_Gradebook';
    return '${prefix}_$date.${format.name}';
  }
}

abstract interface class TeacherGradebookFileSaver {
  Future<String?> save({
    required String suggestedName,
    required List<int> bytes,
    required TeacherGradebookExportFormat format,
  });
}

class WindowsTeacherGradebookFileSaver implements TeacherGradebookFileSaver {
  const WindowsTeacherGradebookFileSaver();
  @override
  Future<String?> save({
    required String suggestedName,
    required List<int> bytes,
    required TeacherGradebookExportFormat format,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: format == TeacherGradebookExportFormat.csv
              ? 'CSV files'
              : 'Excel files',
          extensions: [format.name],
        ),
      ],
    );
    if (location == null) return null;
    final extension = '.${format.name}';
    if (!location.path.toLowerCase().endsWith(extension)) {
      throw FileSystemException(
        'The selected filename has the wrong extension.',
      );
    }
    if (await File(location.path).exists()) {
      throw FileSystemException('Refusing to overwrite an existing export.');
    }
    await File(location.path).writeAsBytes(bytes, flush: true);
    return location.path;
  }
}
