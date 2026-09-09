import 'package:elixr_application/features/class_challenges/class_challenges_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Teacher challenge subscription requires the active Teacher identity',
    () {
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: 'teacher-1',
          teacherId: 'teacher-1',
        ),
        isTrue,
      );
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: 'teacher-2',
          teacherId: 'teacher-1',
        ),
        isFalse,
      );
      expect(
        canStartTeacherChallengeSubscription(
          currentUserId: '',
          teacherId: 'teacher-1',
        ),
        isFalse,
      );
    },
  );
}
