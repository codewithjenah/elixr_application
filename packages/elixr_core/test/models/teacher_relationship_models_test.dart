import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TeacherRosterInvite parses only Teacher-owned shape', () {
    final invite = TeacherRosterInvite.tryFromMap({
      'teacher_id': 'teacher-1',
      'teacher_display_name': 'Grace Hopper',
      'created_at': DateTime.utc(2026, 8, 16),
    }, id: '7KPMXR4DQ2WT');
    expect(invite?.displayCode, '7KPM-XR4D-Q2WT');
    expect(
      TeacherRosterInvite.tryFromMap({
        'trainee_id': 'legacy',
        'trainee_display_name': 'Legacy',
      }, id: '7KPMXR4DQ2WT'),
      isNull,
    );
  });

  test('effective evidence requires approved progress and evidence grants', () {
    final link = TeacherStudentLink.tryFromMap({
      'teacher_id': 'teacher',
      'trainee_id': 'trainee',
      'teacher_display_name': 'Teacher',
      'trainee_display_name': 'Trainee',
      'status': 'approved',
      'request_version': 2,
      'progress_access': 'granted',
      'progress_access_version': 1,
      'progress_access_granted_at': DateTime.utc(2026, 8, 16),
      'evidence_access': 'granted',
      'evidence_access_version': 1,
      'evidence_access_granted_at': DateTime.utc(2026, 8, 16),
    }, id: 'teacher_trainee');
    expect(link?.hasEffectiveEvidenceAccess, isTrue);
  });
}
