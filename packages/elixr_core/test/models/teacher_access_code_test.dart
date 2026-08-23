import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/models/teacher_access_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeacherAccessCode.tryFromMap', () {
    test('parses an unconsumed bootstrap document', () {
      final code = TeacherAccessCode.tryFromMap({
        'consumed': false,
        'created_at': DateTime.utc(2026, 8, 23),
        'note': 'Capstone bootstrap',
      }, id: '7KPMXR4DQ2WT');
      expect(code, isNotNull);
      expect(code!.normalizedCode, '7KPMXR4DQ2WT');
      expect(code.consumed, isFalse);
      expect(code.displayCode, '7KPM-XR4D-Q2WT');
      expect(code.note, 'Capstone bootstrap');
      expect(code.createdBy, isNull);
    });

    test('rejects consumed flag that is not a bool and invalid ids', () {
      expect(
        TeacherAccessCode.tryFromMap(const {'consumed': false}, id: 'short'),
        isNull,
      );
      expect(
        TeacherAccessCode.tryFromMap(const {
          'consumed': 'false',
        }, id: '7KPMXR4DQ2WT'),
        isNull,
      );
    });

    test('parses a consumed document', () {
      final code = TeacherAccessCode.tryFromMap({
        'consumed': true,
        'consumed_by': 'uid-1',
        'created_by': 'teacher-1',
      }, id: CoachCode.tryNormalize('7kpm-xr4d-q2wt')!);
      expect(code!.consumed, isTrue);
      expect(code.consumedBy, 'uid-1');
      expect(code.createdBy, 'teacher-1');
    });
  });
}
