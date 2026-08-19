import 'package:elixr_application/services/join_code_resolver.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository relationshipRepository;
  late InMemoryGroupRepository groupRepository;
  late JoinCodeResolver resolver;

  setUp(() {
    relationshipRepository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => 'RSTU23456ABC',
      now: () => DateTime.utc(2026, 8, 19),
    );
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 19),
    );
    resolver = JoinCodeResolver(
      groupRepository: groupRepository,
      relationshipRepository: relationshipRepository,
    );
  });

  tearDown(() {
    relationshipRepository.dispose();
    groupRepository.dispose();
  });

  test('prefers group invite over legacy roster invite', () async {
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final resolved = await resolver.resolve(invite!.normalizedCode);
    expect(resolved.kind, JoinCodeKind.groupInvite);
  });

  test('falls back to legacy roster invite', () async {
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final resolved = await resolver.resolve('RSTU23456ABC');
    expect(resolved.kind, JoinCodeKind.teacherRosterInvite);
  });

  test('invalid code is rejected', () async {
    await expectLater(
      resolver.resolve('bad-code'),
      throwsA(isA<GroupException>()),
    );
  });

  test(
    'supported write paths cannot leave the same code in both namespaces',
    () async {
      var rosterCodeAttempt = 0;
      final collisionAwareRelationshipRepository =
          InMemoryTeacherRelationshipRepository(
            generateNormalizedCode: () =>
                ['RSTU23456ABC', 'ABCD2345EFGH'][rosterCodeAttempt++],
            now: () => DateTime.utc(2026, 8, 19),
          );
      addTearDown(collisionAwareRelationshipRepository.dispose);
      collisionAwareRelationshipRepository.groupInviteCodes = {'RSTU23456ABC'};
      final rosterInvite = await collisionAwareRelationshipRepository
          .createOrRotateRosterInvite(
            teacherId: 'teacher-1',
            teacherDisplayName: 'Grace Hopper',
          );
      expect(rosterInvite.normalizedCode, 'ABCD2345EFGH');
      expect(
        collisionAwareRelationshipRepository.invites.containsKey(
          'RSTU23456ABC',
        ),
        isFalse,
      );

      var groupCodeAttempt = 0;
      final collisionAwareGroupRepository = InMemoryGroupRepository(
        generateNormalizedCode: () =>
            ['7KPMXR4DQ2WT', 'ABCD2345EFGH'][groupCodeAttempt++],
        now: () => DateTime.utc(2026, 8, 19),
        generateGroupId: () => 'group-collision',
      );
      addTearDown(collisionAwareGroupRepository.dispose);
      collisionAwareGroupRepository.legacyTeacherInviteCodes = {'7KPMXR4DQ2WT'};
      final group = await collisionAwareGroupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      final groupInvite = await collisionAwareGroupRepository
          .getActiveGroupInvite(groupId: group.id);
      expect(groupInvite?.normalizedCode, 'ABCD2345EFGH');
      expect(
        collisionAwareGroupRepository.invites.containsKey('7KPMXR4DQ2WT'),
        isFalse,
      );
    },
  );
}
