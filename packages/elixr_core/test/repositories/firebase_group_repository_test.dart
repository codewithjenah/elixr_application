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
    'approving membership atomically writes classroom access context',
    () async {
      await _seedMembership(
        firestore,
        status: GroupMembershipStatus.pending,
        createdAt: originalCreatedAt,
      );

      await repository.approveMembership(
        membershipId: membershipId,
        teacherId: teacherId,
      );

      final membership = await firestore
          .collection(FirestoreCollections.groupMemberships)
          .doc(membershipId)
          .get();
      final context = await firestore
          .collection(FirestoreCollections.classroomTeacherAccess)
          .doc(
            ClassroomTeacherAccessContext.documentId(
              teacherId: teacherId,
              traineeId: traineeId,
            ),
          )
          .get();
      expect(membership.data()?['status'], GroupMembershipStatus.approved.name);
      expect(context.data()?['teacher_id'], teacherId);
      expect(context.data()?['trainee_id'], traineeId);
      expect(context.data()?['group_id'], groupId);
      expect(
        context.data()?['schema_version'],
        ClassroomTeacherAccessContext.currentSchemaVersion,
      );
    },
  );

  test(
    'approved membership can repair a missing classroom access context',
    () async {
      await _seedMembership(
        firestore,
        status: GroupMembershipStatus.approved,
        createdAt: originalCreatedAt,
      );

      await repository.prepareClassroomAccessContext(
        teacherId: teacherId,
        traineeId: traineeId,
        groupId: groupId,
      );

      final context = await firestore
          .collection(FirestoreCollections.classroomTeacherAccess)
          .doc(
            ClassroomTeacherAccessContext.documentId(
              teacherId: teacherId,
              traineeId: traineeId,
            ),
          )
          .get();
      expect(context.exists, isTrue);
      expect(context.data()?['group_id'], groupId);
    },
  );

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

  test('watchGroupMemberships scopes by teacher and group', () async {
    await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc('group-1_trainee-1')
        .set({
          'group_id': 'group-1',
          'teacher_id': 'teacher-1',
          'trainee_id': 'trainee-1',
          'teacher_display_name': 'Grace Hopper',
          'trainee_display_name': 'Ada Lovelace',
          'status': GroupMembershipStatus.approved.name,
          'invite_id': code,
          'request_version': GroupMembership.currentRequestVersion,
          'created_at': Timestamp.fromDate(DateTime.utc(2026, 1, 15, 10)),
          'updated_at': Timestamp.fromDate(DateTime.utc(2026, 1, 15, 10)),
        });
    await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc('group-1_trainee-2')
        .set({
          'group_id': 'group-1',
          'teacher_id': 'teacher-2',
          'trainee_id': 'trainee-2',
          'teacher_display_name': 'Other Teacher',
          'trainee_display_name': 'Other Trainee',
          'status': GroupMembershipStatus.approved.name,
          'invite_id': code,
          'request_version': GroupMembership.currentRequestVersion,
          'created_at': Timestamp.fromDate(DateTime.utc(2026, 1, 16, 10)),
          'updated_at': Timestamp.fromDate(DateTime.utc(2026, 1, 16, 10)),
        });
    await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc('group-2_trainee-1')
        .set({
          'group_id': 'group-2',
          'teacher_id': 'teacher-1',
          'trainee_id': 'trainee-1',
          'teacher_display_name': 'Grace Hopper',
          'trainee_display_name': 'Ada Lovelace',
          'status': GroupMembershipStatus.pending.name,
          'invite_id': code,
          'request_version': GroupMembership.currentRequestVersion,
          'created_at': Timestamp.fromDate(DateTime.utc(2026, 1, 17, 10)),
          'updated_at': Timestamp.fromDate(DateTime.utc(2026, 1, 17, 10)),
        });

    final approved = await repository
        .watchGroupMemberships(
          groupId: groupId,
          teacherId: teacherId,
          status: GroupMembershipStatus.approved,
        )
        .first;
    expect(approved.map((m) => m.id), ['group-1_trainee-1']);

    final otherTeacher = await repository
        .watchGroupMemberships(
          groupId: groupId,
          teacherId: 'teacher-2',
          status: GroupMembershipStatus.approved,
        )
        .first;
    expect(otherTeacher.map((m) => m.id), ['group-1_trainee-2']);

    final otherGroup = await repository
        .watchGroupMemberships(
          groupId: 'group-2',
          teacherId: teacherId,
          status: GroupMembershipStatus.pending,
        )
        .first;
    expect(otherGroup.map((m) => m.id), ['group-2_trainee-1']);
  });
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
