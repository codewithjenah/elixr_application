import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/features/teacher/leaderboard/teacher_leaderboard_models.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher_phase3_test_support.dart';

LeaderboardEntry entry({
  required String id,
  required String name,
  int xp = 0,
  int best = 0,
  int dailyXp = 0,
  int dailyBest = 0,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: best,
    dailyXp: dailyXp,
    dailyBestScore: dailyBest,
  );
}

void main() {
  test('My Students deduplicates a trainee in multiple groups', () {
    final trainees = TeacherLeaderboardModels.uniqueApprovedTrainees([
      membership(
        groupId: 'g1',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada',
      ),
      membership(
        groupId: 'g2',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada Lovelace',
      ),
    ]);
    expect(trainees.keys, ['t1']);
  });

  test('pending membership is not included', () {
    final approved = TeacherLeaderboardModels.approvedMemberships([
      membership(
        groupId: 'g1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.pending,
      ),
      membership(groupId: 'g1', teacherId: 'teacher', traineeId: 't2'),
    ]);
    expect(TeacherLeaderboardModels.uniqueApprovedTrainees(approved).keys, [
      't2',
    ]);
  });

  test('removed membership ceases authorization', () {
    final memberships = [
      membership(
        groupId: 'g1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.removed,
      ),
    ];
    expect(
      TeacherLeaderboardModels.hasClassroomAuthorization(
        traineeId: 't1',
        memberships: memberships,
      ),
      isFalse,
    );
    expect(
      TeacherLeaderboardModels.drillDownGroupId(
        traineeId: 't1',
        memberships: memberships,
      ),
      isNull,
    );
  });

  test('group scope contains only the selected group', () {
    final approved = TeacherLeaderboardModels.approvedMemberships([
      membership(groupId: 'g1', teacherId: 'teacher', traineeId: 't1'),
      membership(groupId: 'g2', teacherId: 'teacher', traineeId: 't2'),
    ], groupId: 'g1');
    expect(TeacherLeaderboardModels.uniqueApprovedTrainees(approved).keys, [
      't1',
    ]);
  });

  test('approved member without a leaderboard document is 0 XP', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'t1': 'Ada Lovelace'},
      fetched: const {},
      period: LeaderboardPeriod.allTime,
    );
    expect(ranked, hasLength(1));
    expect(ranked.single.userId, 't1');
    expect(ranked.single.displayName, 'Ada Lovelace');
    expect(ranked.single.totalXp, 0);
  });

  test('locked profile state is not consulted when ranking', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'private': 'Private Player'},
      fetched: {
        'private': entry(id: 'private', name: 'Private Player', xp: 50),
      },
      period: LeaderboardPeriod.allTime,
    );
    expect(ranked.single.userId, 'private');
    expect(ranked.single.totalXp, 50);
  });

  test('scoped ranking follows XP, best score, then UID', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'z': 'Z', 'a': 'A', 'b': 'B', 'c': 'C'},
      fetched: {
        'z': entry(id: 'z', name: 'Z', xp: 25, best: 12),
        'a': entry(id: 'a', name: 'A', xp: 50, best: 8),
        'b': entry(id: 'b', name: 'B', xp: 50, best: 10),
        'c': entry(id: 'c', name: 'C', xp: 50, best: 10),
      },
      period: LeaderboardPeriod.allTime,
    );
    expect(ranked.map((row) => row.userId), ['b', 'c', 'a', 'z']);
  });

  test('period ranking uses period-specific XP fields', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {
        'a': entry(id: 'a', name: 'A', xp: 100, dailyXp: 10, dailyBest: 3),
        'b': entry(id: 'b', name: 'B', xp: 25, dailyXp: 25, dailyBest: 2),
      },
      period: LeaderboardPeriod.today,
    );
    expect(ranked.map((row) => row.userId), ['b', 'a']);
  });

  test('authorized drill-down prefers the selected group when valid', () {
    final memberships = [
      membership(groupId: 'g1', teacherId: 'teacher', traineeId: 't1'),
      membership(groupId: 'g2', teacherId: 'teacher', traineeId: 't1'),
    ];
    expect(
      TeacherLeaderboardModels.hasClassroomAuthorization(
        traineeId: 't1',
        memberships: memberships,
      ),
      isTrue,
    );
    expect(
      TeacherLeaderboardModels.drillDownGroupId(
        traineeId: 't1',
        memberships: memberships,
        preferredGroupId: 'g2',
      ),
      'g2',
    );
    expect(
      TeacherLeaderboardModels.drillDownGroupId(
        traineeId: 'stranger',
        memberships: memberships,
      ),
      isNull,
    );
  });

  test(
    'group picker recovery uses remaining active names, never stale IDs',
    () {
      final groups = [
        activeGroup(id: 'g1', name: 'BSHM 4A'),
        activeGroup(id: 'g2', name: 'BSHM 4B'),
      ];
      expect(
        TeacherLeaderboardModels.recoverSelectedGroupId(
          selectedGroupId: 'g2',
          activeGroups: groups,
        ),
        'g2',
      );
      expect(
        TeacherLeaderboardModels.recoverSelectedGroupId(
          selectedGroupId: 'archived',
          activeGroups: groups,
        ),
        'g1',
      );
      expect(
        TeacherLeaderboardModels.recoverSelectedGroupId(
          selectedGroupId: 'g1',
          activeGroups: const [],
        ),
        isNull,
      );
    },
  );

  test('human-readable group names stay on the group model', () {
    final group = activeGroup(id: 'group-firestore-id', name: 'BSHM 4A');
    expect(group.name, 'BSHM 4A');
    expect(group.name, isNot(group.id));
  });
}
