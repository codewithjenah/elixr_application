import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group challenge watch keeps group and Teacher ownership filters', () {
    final source = File(
      'lib/data/repositories/firebase_class_challenge_repository.dart',
    ).readAsStringSync();
    final methodStart = source.indexOf(
      'Stream<List<ClassChallenge>> watchChallengesForGroup',
    );
    final methodEnd = source.indexOf(
      'Stream<List<ClassChallengeLeaderboardEntry>>',
      methodStart,
    );

    expect(methodStart, isNonNegative);
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains(".where('group_id', isEqualTo: groupId)"));
    expect(method, contains(".where('teacher_id', isEqualTo: teacherId)"));
  });
}
