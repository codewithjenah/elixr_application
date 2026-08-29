import 'dart:async';

import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_controller.dart';
import 'package:elixr_application/features/teacher/analytics/teacher_analytics_models.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _teacherId = 'teacher';
final _now = DateTime.utc(2026, 8, 19, 10);

ElixrGroup _group() => ElixrGroup(
  id: 'group-1',
  teacherId: _teacherId,
  name: 'Group 1',
  status: ElixrGroupStatus.active,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

GroupMembership _membership(String traineeId) => GroupMembership(
  id: GroupMembership.documentId(groupId: 'group-1', traineeId: traineeId),
  groupId: 'group-1',
  teacherId: _teacherId,
  traineeId: traineeId,
  traineeDisplayName: traineeId,
  teacherDisplayName: 'Teacher',
  status: GroupMembershipStatus.approved,
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

class _FakeProgressRepository extends TeacherProgressRepository {
  _FakeProgressRepository({this.delayFor, this.waitBeforeReturn});

  final Duration Function(DateTime startUtc)? delayFor;
  final Future<void> Function()? waitBeforeReturn;
  final List<String> calls = [];
  int activeCalls = 0;
  int maxActiveCalls = 0;
  bool failReads = false;

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) =>
      const Stream<PublicProfileSummary?>.empty();

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) async => const TeacherProgressPage(sessions: [], hasMore: false);

  @override
  Future<List<PublicProfileSession>> fetchSessionsInRange({
    required String traineeId,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    calls.add('$traineeId:${startUtc.toIso8601String()}');
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      final delay = delayFor?.call(startUtc) ?? Duration.zero;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      await waitBeforeReturn?.call();
      if (failReads) throw StateError('permission denied');
      return const [];
    } finally {
      activeCalls--;
    }
  }
}

Future<void> _settle() => pumpEventQueue(times: 20);

TeacherAnalyticsController _controller({
  required InMemoryGroupRepository groups,
  required InMemoryClassroomAssignmentRepository assignments,
  required TeacherProgressRepository progress,
}) => TeacherAnalyticsController(
  groupRepository: groups,
  assignmentRepository: assignments,
  progressRepository: progress,
  teacherId: _teacherId,
  nowUtc: () => _now,
);

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;

  setUp(() {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    groups.seedGroup(_group());
    for (var index = 0; index < 4; index++) {
      groups.seedMembership(_membership('student-$index'));
    }
  });

  tearDown(() {
    groups.dispose();
    assignments.dispose();
  });

  test(
    'bounds session reads at five and exposes retryable partial data',
    () async {
      final progress = _FakeProgressRepository(
        delayFor: (_) => const Duration(milliseconds: 2),
      )..failReads = true;
      final controller = _controller(
        groups: groups,
        assignments: assignments,
        progress: progress,
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(progress.maxActiveCalls, lessThanOrEqualTo(5));
      expect(progress.calls, hasLength(8));
      expect(controller.partialDataWarning, isNotNull);
      expect(controller.snapshot, isNotNull);

      progress.failReads = false;
      await controller.refresh();
      expect(controller.partialDataWarning, isNull);
      expect(controller.lastUpdated, _now);
    },
  );

  test(
    'discards stale filter results that finish after the latest filter',
    () async {
      final progress = _FakeProgressRepository(
        delayFor: (startUtc) => startUtc == DateTime.utc(2026, 7, 31, 16)
            ? const Duration(milliseconds: 40)
            : Duration.zero,
      );
      final controller = _controller(
        groups: groups,
        assignments: assignments,
        progress: progress,
      );
      addTearDown(controller.dispose);
      await controller.start();

      final stale = controller.setCustomRange(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final latest = controller.setCustomRange(
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 12),
      );
      await Future.wait([stale, latest]);

      expect(controller.snapshot, isNotNull);
      expect(controller.snapshot!.periodWindow.period, AnalyticsPeriod.custom);
      expect(
        controller.snapshot!.periodWindow.current.startUtc,
        DateTime.utc(2026, 8, 9, 16),
      );
    },
  );

  test(
    'removes session data when an approved member loses authorization',
    () async {
      final progress = _FakeProgressRepository();
      final controller = _controller(
        groups: groups,
        assignments: assignments,
        progress: progress,
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.snapshot!.eligibleStudentCount, 4);

      await groups.removeMembership(
        membershipId: GroupMembership.documentId(
          groupId: 'group-1',
          traineeId: 'student-0',
        ),
        teacherId: _teacherId,
      );
      await _settle();

      expect(controller.snapshot!.eligibleStudentCount, 3);
      expect(
        controller.snapshot!.groupComparisons.single.eligibleStudentCount,
        3,
      );
    },
  );

  test('dispose prevents late reads from publishing state', () async {
    final release = Completer<void>();
    final progress = _FakeProgressRepository(
      waitBeforeReturn: () => release.future,
    );
    final controller = _controller(
      groups: groups,
      assignments: assignments,
      progress: progress,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    final pending = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final notificationsBeforeDispose = notifications;
    controller.dispose();
    release.complete();
    await pending;

    expect(controller.snapshot, isNull);
    expect(progress.activeCalls, 0);
    expect(notifications, notificationsBeforeDispose);
  });
}
