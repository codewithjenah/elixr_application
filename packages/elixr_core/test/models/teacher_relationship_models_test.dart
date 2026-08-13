import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TeacherInvite.tryFromMap reads timestamps and display code', () {
    final invite = TeacherInvite.tryFromMap({
      'trainee_id': 't1',
      'trainee_display_name': 'Ada Lovelace',
      'created_at': DateTime.utc(2026, 8, 13),
      'expires_at': DateTime.utc(2026, 8, 20),
    }, id: '7KPMXR4DQ2WT');

    expect(invite, isNotNull);
    expect(invite!.displayCode, '7KPM-XR4D-Q2WT');
    expect(invite.isExpiredAt(DateTime.utc(2026, 8, 21)), isTrue);
    expect(invite.isExpiredAt(DateTime.utc(2026, 8, 19)), isFalse);
  });

  test('TeacherStudentLink.documentId is deterministic', () {
    expect(
      TeacherStudentLink.documentId(
        teacherId: 'teacherA',
        traineeId: 'traineeB',
      ),
      'teacherA_traineeB',
    );
  });

  test('TeacherStudentLink.tryFromMap requires a known status', () {
    expect(
      TeacherStudentLink.tryFromMap({
        'teacher_id': 'a',
        'trainee_id': 'b',
        'teacher_display_name': 'A',
        'trainee_display_name': 'B',
        'status': 'unknown',
      }, id: 'a_b'),
      isNull,
    );

    final link = TeacherStudentLink.tryFromMap({
      'teacher_id': 'a',
      'trainee_id': 'b',
      'teacher_display_name': 'A',
      'trainee_display_name': 'B',
      'status': 'pending',
      'invite_id': '7KPMXR4DQ2WT',
    }, id: 'a_b');
    expect(link, isNotNull);
    expect(link!.isPending, isTrue);
  });
}
