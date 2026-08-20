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
  int dailySessionsCompleted = 0,
  double dailyScoreSum = 0,
  double dailyAverageScore = 0,
  String? dailyKey,
  int monthlyXp = 0,
  int monthlyBest = 0,
  int monthlySessionsCompleted = 0,
  String? monthlyKey,
  String? profilePictureUrl,
  String? equippedBorderId,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: best,
    dailyKey: dailyKey,
    dailyXp: dailyXp,
    dailySessionsCompleted: dailySessionsCompleted,
    dailyScoreSum: dailyScoreSum,
    dailyAverageScore: dailyAverageScore,
    dailyBestScore: dailyBest,
    monthlyKey: monthlyKey,
    monthlyXp: monthlyXp,
    monthlySessionsCompleted: monthlySessionsCompleted,
    monthlyBestScore: monthlyBest,
    profilePictureUrl: profilePictureUrl,
    equippedBorderId: equippedBorderId,
  );
}

final _nowUtc = DateTime.utc(2026, 8, 19, 16);
const _todayKey = '20260820';
const _yesterdayKey = '20260819';
const _monthKey = '202608';
const _previousMonthKey = '202607';

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

  test('period ranking uses current-period XP fields', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {
        'a': entry(
          id: 'a',
          name: 'A',
          xp: 100,
          dailyKey: _todayKey,
          dailyXp: 10,
          dailyBest: 3,
        ),
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 25,
          dailyKey: _todayKey,
          dailyXp: 25,
          dailyBest: 2,
        ),
      },
      period: LeaderboardPeriod.today,
      nowUtc: _nowUtc,
    );
    expect(ranked.map((row) => row.userId), ['b', 'a']);
  });

  test('yesterday daily_key with 100 XP counts as 0 for Today', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A'},
      fetched: {
        'a': entry(
          id: 'a',
          name: 'A',
          xp: 100,
          dailyKey: _yesterdayKey,
          dailyXp: 100,
          dailySessionsCompleted: 4,
          dailyScoreSum: 40,
          dailyAverageScore: 10,
          dailyBest: 12,
          profilePictureUrl: 'https://example.test/a.png',
          equippedBorderId: 'starter_glow',
        ),
      },
      period: LeaderboardPeriod.today,
      nowUtc: _nowUtc,
    );
    final row = ranked.single;
    expect(row.userId, 'a');
    expect(row.displayName, 'A');
    expect(row.profilePictureUrl, 'https://example.test/a.png');
    expect(row.equippedBorderId, 'starter_glow');
    expect(row.totalXp, 100);
    expect(row.xpFor(LeaderboardPeriod.today), 0);
    expect(row.sessionsCompletedFor(LeaderboardPeriod.today), 0);
    expect(row.scoreSumFor(LeaderboardPeriod.today), 0);
    expect(row.averageScoreFor(LeaderboardPeriod.today), 0);
    expect(row.bestScoreFor(LeaderboardPeriod.today), 0);
  });

  test("today's daily_key with 25 XP is retained for Today", () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'b': 'B'},
      fetched: {
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 25,
          dailyKey: _todayKey,
          dailyXp: 25,
          dailySessionsCompleted: 1,
          dailyBest: 8,
        ),
      },
      period: LeaderboardPeriod.today,
      nowUtc: _nowUtc,
    );
    expect(ranked.single.xpFor(LeaderboardPeriod.today), 25);
    expect(ranked.single.sessionsCompletedFor(LeaderboardPeriod.today), 1);
  });

  test('previous month 500 XP counts as 0 for This month', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A'},
      fetched: {
        'a': entry(
          id: 'a',
          name: 'A',
          xp: 500,
          monthlyKey: _previousMonthKey,
          monthlyXp: 500,
          monthlySessionsCompleted: 20,
          monthlyBest: 12,
        ),
      },
      period: LeaderboardPeriod.thisMonth,
      nowUtc: _nowUtc,
    );
    expect(ranked.single.xpFor(LeaderboardPeriod.thisMonth), 0);
    expect(ranked.single.sessionsCompletedFor(LeaderboardPeriod.thisMonth), 0);
    expect(ranked.single.bestScoreFor(LeaderboardPeriod.thisMonth), 0);
    expect(ranked.single.totalXp, 500);
  });

  test('current month XP is retained for This month', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'b': 'B'},
      fetched: {
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 75,
          monthlyKey: _monthKey,
          monthlyXp: 50,
          monthlySessionsCompleted: 2,
          monthlyBest: 9,
        ),
      },
      period: LeaderboardPeriod.thisMonth,
      nowUtc: _nowUtc,
    );
    expect(ranked.single.xpFor(LeaderboardPeriod.thisMonth), 50);
    expect(ranked.single.sessionsCompletedFor(LeaderboardPeriod.thisMonth), 2);
  });

  test('stale high Today XP cannot outrank current-period lower XP', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {
        'a': entry(
          id: 'a',
          name: 'A',
          xp: 200,
          dailyKey: _yesterdayKey,
          dailyXp: 100,
          dailyBest: 12,
        ),
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 25,
          dailyKey: _todayKey,
          dailyXp: 25,
          dailyBest: 4,
        ),
      },
      period: LeaderboardPeriod.today,
      nowUtc: _nowUtc,
    );
    expect(ranked.map((row) => row.userId), ['b', 'a']);
    expect(ranked.first.xpFor(LeaderboardPeriod.today), 25);
    expect(ranked.last.xpFor(LeaderboardPeriod.today), 0);
  });

  test('zero-XP approved member remains present on Today', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'zero': 'Zero XP', 'b': 'B'},
      fetched: {
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 25,
          dailyKey: _todayKey,
          dailyXp: 25,
        ),
      },
      period: LeaderboardPeriod.today,
      nowUtc: _nowUtc,
    );
    expect(ranked.map((row) => row.userId), ['b', 'zero']);
    expect(ranked.last.displayName, 'Zero XP');
    expect(ranked.last.totalXp, 0);
    expect(ranked.last.xpFor(LeaderboardPeriod.today), 0);
  });

  test('All Time ignores stale period keys', () {
    final ranked = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {
        'a': entry(
          id: 'a',
          name: 'A',
          xp: 200,
          dailyKey: _yesterdayKey,
          dailyXp: 100,
          monthlyKey: _previousMonthKey,
          monthlyXp: 500,
        ),
        'b': entry(
          id: 'b',
          name: 'B',
          xp: 25,
          dailyKey: _todayKey,
          dailyXp: 25,
          monthlyKey: _monthKey,
          monthlyXp: 25,
        ),
      },
      period: LeaderboardPeriod.allTime,
      nowUtc: _nowUtc,
    );
    expect(ranked.map((row) => row.userId), ['a', 'b']);
    expect(ranked.first.totalXp, 200);
    expect(ranked.first.xpFor(LeaderboardPeriod.allTime), 200);
  });

  test('Asia/Manila day boundary decides Today XP', () {
    final stale = entry(
      id: 'a',
      name: 'A',
      xp: 100,
      dailyKey: '20260819',
      dailyXp: 100,
    );
    final current = entry(
      id: 'b',
      name: 'B',
      xp: 25,
      dailyKey: '20260820',
      dailyXp: 25,
    );
    final beforeMidnight = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {'a': stale, 'b': current},
      period: LeaderboardPeriod.today,
      nowUtc: DateTime.utc(2026, 8, 19, 15, 59, 59),
    );
    expect(beforeMidnight.map((row) => row.userId), ['a', 'b']);
    expect(beforeMidnight.first.xpFor(LeaderboardPeriod.today), 100);

    final afterMidnight = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {'a': stale, 'b': current},
      period: LeaderboardPeriod.today,
      nowUtc: DateTime.utc(2026, 8, 19, 16),
    );
    expect(afterMidnight.map((row) => row.userId), ['b', 'a']);
    expect(afterMidnight.first.xpFor(LeaderboardPeriod.today), 25);
    expect(afterMidnight.last.xpFor(LeaderboardPeriod.today), 0);
  });

  test('Asia/Manila month boundary decides This month XP', () {
    final july = entry(
      id: 'a',
      name: 'A',
      xp: 500,
      monthlyKey: '202607',
      monthlyXp: 500,
    );
    final august = entry(
      id: 'b',
      name: 'B',
      xp: 25,
      monthlyKey: '202608',
      monthlyXp: 25,
    );
    final beforeAugust = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {'a': july, 'b': august},
      period: LeaderboardPeriod.thisMonth,
      nowUtc: DateTime.utc(2026, 7, 31, 15, 59, 59),
    );
    expect(beforeAugust.map((row) => row.userId), ['a', 'b']);
    expect(beforeAugust.first.xpFor(LeaderboardPeriod.thisMonth), 500);

    final afterAugust = TeacherLeaderboardModels.rankScoped(
      trainees: const {'a': 'A', 'b': 'B'},
      fetched: {'a': july, 'b': august},
      period: LeaderboardPeriod.thisMonth,
      nowUtc: DateTime.utc(2026, 7, 31, 16),
    );
    expect(afterAugust.map((row) => row.userId), ['b', 'a']);
    expect(afterAugust.first.xpFor(LeaderboardPeriod.thisMonth), 25);
    expect(afterAugust.last.xpFor(LeaderboardPeriod.thisMonth), 0);
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
