import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const teacherId = 'teacher-1';
  const traineeId = 'trainee-1';
  const groupId = 'group-1';
  const code = '7KPMXR4DQ2WT';
  final membershipId = GroupMembership.documentId(
    groupId: groupId,
    traineeId: traineeId,
  );
  final originalCreatedAt = DateTime.utc(2026, 1, 15, 10);

  late FakeFirebaseFirestore firestore;
  late FirebaseGroupRepository repository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = FirebaseGroupRepository(firestore: firestore);
    await _seedActiveGroupAndInvite(firestore);
  });

  test('first-time requestGroupJoin creates pending membership', () async {
    final membership = await repository.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: 'Ada Lovelace',
      code: code,
    );

    expect(membership.id, membershipId);
    expect(membership.isPending, isTrue);
    expect(membership.groupId, groupId);
    expect(membership.teacherId, teacherId);
    expect(membership.traineeId, traineeId);
    expect(membership.inviteId, code);
    expect(membership.requestVersion, GroupMembership.currentRequestVersion);

    final stored = await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc(membershipId)
        .get();
    expect(stored.exists, isTrue);
    expect(stored.data()?['status'], GroupMembershipStatus.pending.name);
  });

  test('second request returns alreadyPending', () async {
    await repository.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: 'Ada Lovelace',
      code: code,
    );

    await expectLater(
      repository.requestGroupJoin(
        traineeId: traineeId,
        traineeDisplayName: 'Ada Lovelace',
        code: code,
      ),
      throwsA(
        predicate<GroupException>(
          (error) => error.code == GroupError.alreadyPending,
        ),
      ),
    );
  });

  test('approved existing membership returns alreadyMember', () async {
    await _seedMembership(
      firestore,
      status: GroupMembershipStatus.approved,
      createdAt: originalCreatedAt,
    );

    await expectLater(
      repository.requestGroupJoin(
        traineeId: traineeId,
        traineeDisplayName: 'Ada Lovelace',
        code: code,
      ),
      throwsA(
        predicate<GroupException>(
          (error) => error.code == GroupError.alreadyMember,
        ),
      ),
    );
  });

  test('rejected membership can re-request and preserves created_at', () async {
    await _seedMembership(
      firestore,
      status: GroupMembershipStatus.rejected,
      createdAt: originalCreatedAt,
    );

    final second = await repository.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: 'Ada Lovelace',
      code: code,
    );

    expect(second.id, membershipId);
    expect(second.isPending, isTrue);
    expect(second.createdAt, originalCreatedAt);
  });

  test(
    'cancelled membership can re-request and preserves created_at',
    () async {
      await _seedMembership(
        firestore,
        status: GroupMembershipStatus.cancelled,
        createdAt: originalCreatedAt,
      );

      final second = await repository.requestGroupJoin(
        traineeId: traineeId,
        traineeDisplayName: 'Ada Lovelace',
        code: code,
      );

      expect(second.id, membershipId);
      expect(second.isPending, isTrue);
      expect(second.createdAt, originalCreatedAt);
    },
  );

  test('removed membership can re-request and preserves created_at', () async {
    await _seedMembership(
      firestore,
      status: GroupMembershipStatus.removed,
      createdAt: originalCreatedAt,
    );

    final second = await repository.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: 'Ada Lovelace',
      code: code,
    );

    expect(second.id, membershipId);
    expect(second.isPending, isTrue);
    expect(second.createdAt, originalCreatedAt);
  });

  test(
    'own-membership lookup does not confuse another group membership',
    () async {
      await firestore
          .collection(FirestoreCollections.groupMemberships)
          .doc('other-group_$traineeId')
          .set({
            'group_id': 'other-group',
            'teacher_id': teacherId,
            'trainee_id': traineeId,
            'teacher_display_name': 'Grace Hopper',
            'trainee_display_name': 'Ada Lovelace',
            'status': GroupMembershipStatus.pending.name,
            'invite_id': 'ABCD2345EFGH',
            'request_version': GroupMembership.currentRequestVersion,
            'created_at': Timestamp.fromDate(originalCreatedAt),
            'updated_at': Timestamp.fromDate(originalCreatedAt),
          });

      final membership = await repository.requestGroupJoin(
        traineeId: traineeId,
        traineeDisplayName: 'Ada Lovelace',
        code: code,
      );

      expect(membership.id, membershipId);
      expect(membership.isPending, isTrue);
      expect(membership.groupId, groupId);
    },
  );
}

Future<void> _seedActiveGroupAndInvite(FakeFirebaseFirestore firestore) async {
  await firestore.collection(FirestoreCollections.groups).doc('group-1').set({
    'teacher_id': 'teacher-1',
    'name': 'BSHM 4A',
    'status': ElixrGroupStatus.active.name,
    'invite_code': '7KPMXR4DQ2WT',
    'schema_version': ElixrGroup.currentSchemaVersion,
  });
  await firestore
      .collection(FirestoreCollections.groupInvites)
      .doc('7KPMXR4DQ2WT')
      .set({
        'group_id': 'group-1',
        'teacher_id': 'teacher-1',
        'teacher_display_name': 'Grace Hopper',
      });
}

Future<void> _seedMembership(
  FakeFirebaseFirestore firestore, {
  required GroupMembershipStatus status,
  required DateTime createdAt,
}) async {
  await firestore
      .collection(FirestoreCollections.groupMemberships)
      .doc(
        GroupMembership.documentId(groupId: 'group-1', traineeId: 'trainee-1'),
      )
      .set({
        'group_id': 'group-1',
        'teacher_id': 'teacher-1',
        'trainee_id': 'trainee-1',
        'teacher_display_name': 'Grace Hopper',
        'trainee_display_name': 'Ada Lovelace',
        'status': status.name,
        'invite_id': '7KPMXR4DQ2WT',
        'request_version': GroupMembership.currentRequestVersion,
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(createdAt),
      });
}
