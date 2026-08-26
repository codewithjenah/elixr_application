import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher_access/trainee_class_detail_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher/teacher_phase3_test_support.dart';

GroupAssignment _assignment({required String id, required String groupId}) {
  return GroupAssignment(
    id: id,
    teacherId: 'teacher-1',
    groupId: groupId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: id == 'asg-a' ? 'Hand Stall' : 'Other Move',
    teacherDisplayName: 'Grace Hopper',
    groupName: groupId == 'g1' ? 'BSHM 4A' : 'BSHM 4B',
    officialMovementName: 'Hand Stall',
  );
}

void main() {
  late InMemoryGroupRepository groupRepository;
  late InMemoryClassroomAssignmentRepository assignmentRepository;

  setUp(() {
    var groupCodeIndex = 0;
    var groupIdIndex = 0;
    const groupCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          groupCodes[groupCodeIndex++ % groupCodes.length],
      generateGroupId: () => 'group-${groupIdIndex++}',
      now: () => DateTime.utc(2026, 8, 16),
    );
    assignmentRepository = InMemoryClassroomAssignmentRepository();
  });

  tearDown(() {
    groupRepository.dispose();
    assignmentRepository.dispose();
  });

  Future<ElixrGroup> approvedClass({
    required String name,
    required String traineeId,
    List<String> extraTraineeIds = const [],
  }) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: name,
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final self = await groupRepository.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: self.id,
      teacherId: 'teacher-1',
    );
    for (final extraId in extraTraineeIds) {
      final extra = await groupRepository.requestGroupJoin(
        traineeId: extraId,
        traineeDisplayName: 'Alan Turing',
        code: invite.normalizedCode,
      );
      await groupRepository.approveMembership(
        membershipId: extra.id,
        teacherId: 'teacher-1',
      );
    }
    return group;
  }

  test('approved membership loads classmates for that class only', () async {
    final groupA = await approvedClass(
      name: 'BSHM 4A',
      traineeId: 'trainee-1',
      extraTraineeIds: ['trainee-2'],
    );
    await approvedClass(name: 'BSHM 4B', traineeId: 'trainee-1');

    final controller = TraineeClassDetailController(
      groupId: groupA.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    expect(controller.unauthorized, isFalse);
    expect(controller.className, 'BSHM 4A');
    expect(controller.classmates.map((member) => member.traineeId).toSet(), {
      'trainee-1',
      'trainee-2',
    });
  });

  test('maps classmate public profile pictures', () async {
    final profiles = FakePublicProfileRepository();
    final group = await approvedClass(name: 'BSHM 4A', traineeId: 'trainee-1');
    final controller = TraineeClassDetailController(
      groupId: group.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
      publicProfileRepository: profiles,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    expect(profiles.watchedUserIds, contains('trainee-1'));
    expect(controller.profilePictureUrlFor('trainee-1'), isNull);

    profiles.emitProfile(
      'trainee-1',
      const PublicProfile(
        userId: 'trainee-1',
        displayName: 'Ada Lovelace',
        visibility: ProfileVisibility.public,
        profilePictureUrl: 'https://example.test/ada.png',
      ),
    );
    await pumpEventQueue();

    expect(
      controller.profilePictureUrlFor('trainee-1'),
      'https://example.test/ada.png',
    );
  });

  test('assignments stay scoped to the opened class', () async {
    final groupA = await approvedClass(name: 'BSHM 4A', traineeId: 'trainee-1');
    final groupB = await approvedClass(name: 'BSHM 4B', traineeId: 'trainee-1');
    assignmentRepository.seedAssignment(
      _assignment(id: 'asg-a', groupId: groupA.id),
    );
    assignmentRepository.seedAssignment(
      _assignment(id: 'asg-b', groupId: groupB.id),
    );

    final controller = TraineeClassDetailController(
      groupId: groupA.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    expect(controller.assignments?.items.map((item) => item.assignment.id), [
      'asg-a',
    ]);
  });

  test('missing membership is unauthorized', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final controller = TraineeClassDetailController(
      groupId: group.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    expect(controller.unauthorized, isTrue);
    expect(controller.classmates, isEmpty);
  });
}
