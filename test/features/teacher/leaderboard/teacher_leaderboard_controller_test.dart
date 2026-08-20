import 'dart:async';

import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/features/teacher/leaderboard/teacher_leaderboard_controller.dart';
import 'package:elixr_application/features/teacher/leaderboard/teacher_leaderboard_models.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher_phase3_test_support.dart';

LeaderboardEntry _entry(String id, {int xp = 0, String? name}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name ?? id,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: 0,
  );
}

void main() {
  late InMemoryGroupRepository repository;
  late TeacherLeaderboardController controller;
  late Map<String, LeaderboardEntry> fetched;
  late List<List<String>> fetchCalls;
  var disposeController = true;

  setUp(() {
    repository = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 20));
    fetched = {};
    fetchCalls = [];
    disposeController = true;
    controller = TeacherLeaderboardController(
      groupRepository: repository,
      teacherId: 'teacher',
      fetchEntriesByUserIds: (ids) async {
        fetchCalls.add(List<String>.from(ids));
        return {
          for (final id in ids)
            if (fetched[id] != null) id: fetched[id]!,
        };
      },
      fetchGlobalPage: ({required period, startAfter}) async {
        return LeaderboardPage(
          entries: [
            _entry('stranger', xp: 75, name: 'Global Stranger'),
            _entry('t1', xp: 50, name: 'Ada Lovelace'),
          ],
          nextCursor: null,
          hasMore: false,
        );
      },
    );
  });

  tearDown(() {
    if (disposeController) {
      controller.dispose();
    }
    repository.dispose();
  });

  Future<void> boot() async {
    await controller.start();
    await pumpEventQueue();
  }

  test(
    'global rows include strangers and authorized classroom members',
    () async {
      repository.seedGroup(activeGroup());
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      );
      await boot();

      expect(controller.globalList.entries.map((e) => e.userId), [
        'stranger',
        't1',
      ]);
      expect(controller.canOpenStudentDetail('stranger'), isFalse);
      expect(controller.canOpenStudentDetail('t1'), isTrue);
      expect(controller.drillDownGroupId('t1'), 'group-1');
    },
  );

  test('My Students includes only approved authorized trainees', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'pending',
        status: GroupMembershipStatus.pending,
        traineeName: 'Pending',
      ),
    );
    fetched['t1'] = _entry('t1', xp: 50, name: 'Ada Lovelace');
    await boot();
    await controller.setScope(TeacherLeaderboardScope.myStudents);

    expect(controller.scopedEntries.map((e) => e.userId), ['t1']);
    expect(controller.canOpenStudentDetail('pending'), isFalse);
  });

  test(
    'same trainee in multiple groups is deduplicated in My Students',
    () async {
      repository.seedGroup(activeGroup(id: 'group-1', name: 'A'));
      repository.seedGroup(activeGroup(id: 'group-2', name: 'B'));
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      );
      repository.seedMembership(
        membership(groupId: 'group-2', teacherId: 'teacher', traineeId: 't1'),
      );
      await boot();
      await controller.setScope(TeacherLeaderboardScope.myStudents);

      expect(controller.scopedEntries, hasLength(1));
      expect(controller.scopedEntries.single.userId, 't1');
      expect(controller.scopedEntries.single.totalXp, 0);
    },
  );

  test('removed membership drops the trainee from My Students', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    await boot();
    await controller.setScope(TeacherLeaderboardScope.myStudents);
    expect(controller.scopedEntries, hasLength(1));

    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.removed,
      ),
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(controller.scopedEntries, isEmpty);
    expect(controller.canOpenStudentDetail('t1'), isFalse);
  });

  test(
    'group scope contains only approved members of the selected group',
    () async {
      repository.seedGroup(activeGroup(id: 'group-1', name: 'BSHM 4A'));
      repository.seedGroup(activeGroup(id: 'group-2', name: 'BSHM 4B'));
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      );
      repository.seedMembership(
        membership(
          groupId: 'group-2',
          teacherId: 'teacher',
          traineeId: 't2',
          traineeName: 'Alan Turing',
        ),
      );
      await boot();
      await controller.setScope(TeacherLeaderboardScope.group);
      await controller.setSelectedGroupId('group-1');

      expect(controller.scopedEntries.map((e) => e.userId), ['t1']);
      expect(
        controller.activeGroups.map((g) => g.name),
        containsAll(['BSHM 4A', 'BSHM 4B']),
      );
      expect(controller.groupNamesById()['group-1'], 'BSHM 4A');
    },
  );

  test('group picker recovers when the selected group is archived', () async {
    repository.seedGroup(activeGroup(id: 'group-1', name: 'A'));
    repository.seedGroup(activeGroup(id: 'group-2', name: 'B'));
    await boot();
    await controller.setScope(TeacherLeaderboardScope.group);
    await controller.setSelectedGroupId('group-2');
    expect(controller.selectedGroupId, 'group-2');

    repository.seedGroup(
      activeGroup(
        id: 'group-2',
        name: 'B',
      ).copyWith(status: ElixrGroupStatus.archived),
    );
    await pumpEventQueue();

    expect(controller.selectedGroupId, 'group-1');
    expect(controller.hasNoActiveGroups, isFalse);
  });

  test('no active groups produces the empty-group state', () async {
    await boot();
    await controller.setScope(TeacherLeaderboardScope.group);
    expect(controller.hasNoActiveGroups, isTrue);
    expect(controller.selectedGroupId, isNull);
  });

  test('private profile is not required for a scoped 0 XP row', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'private',
        traineeName: 'Private Player',
      ),
    );
    await boot();
    await controller.setScope(TeacherLeaderboardScope.myStudents);
    expect(controller.scopedEntries.single.userId, 'private');
    expect(controller.scopedEntries.single.totalXp, 0);
  });

  test(
    'start is ready even if the global leaderboard fetch has not completed',
    () async {
      disposeController = false;
      controller.dispose();
      final hanging = Completer<LeaderboardPage>();
      controller = TeacherLeaderboardController(
        groupRepository: repository,
        teacherId: 'teacher',
        fetchEntriesByUserIds: (ids) async => const {},
        fetchGlobalPage: ({required period, startAfter}) => hanging.future,
      );
      await controller.start();
      expect(controller.loading, isFalse);
      expect(controller.errorMessage, isNull);
      hanging.complete(
        const LeaderboardPage(entries: [], nextCursor: null, hasMore: false),
      );
      await pumpEventQueue();
    },
  );

  test(
    'dispose cancels subscriptions and ignores later membership updates',
    () async {
      repository.seedGroup(activeGroup());
      await boot();
      disposeController = false;
      controller.dispose();
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      );
      await pumpEventQueue();
      expect(fetchCalls, isEmpty);
    },
  );
}
