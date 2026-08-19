import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/coach_code.dart';
import '../models/elixr_group.dart';
import '../models/group_exception.dart';
import '../models/group_invite.dart';
import '../models/group_membership.dart';
import 'group_repository.dart';

class FirebaseGroupRepository implements GroupRepository {
  FirebaseGroupRepository({
    FirebaseFirestore? firestore,
    String Function()? generateNormalizedCode,
    this.maxCodeAttempts = 8,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized;

  final FirebaseFirestore _firestore;
  final String Function() _generateNormalizedCode;
  final int maxCodeAttempts;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection(FirestoreCollections.groups);
  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection(FirestoreCollections.groupInvites);
  CollectionReference<Map<String, dynamic>> get _legacyTeacherInvites =>
      _firestore.collection(FirestoreCollections.teacherInvites);
  CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection(FirestoreCollections.groupMemberships);

  @override
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    final ref = _groups.doc();
    await ref.set({
      'teacher_id': teacherId,
      'name': trimmed,
      'status': ElixrGroupStatus.active.name,
      'schema_version': ElixrGroup.currentSchemaVersion,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    try {
      await createOrRotateGroupInvite(
        groupId: ref.id,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
      );
    } catch (e) {
      try {
        await ref.delete();
      } on FirebaseException {
        // Best-effort rollback when invite provisioning fails.
      }
      rethrow;
    }
    final snapshot = await ref.get();
    return ElixrGroup.tryFromMap(
          snapshot.data() ?? const {},
          id: snapshot.id,
        ) ??
        ElixrGroup(
          id: ref.id,
          teacherId: teacherId,
          name: trimmed,
          status: ElixrGroupStatus.active,
        );
  }

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    return _groups
        .where('teacher_id', isEqualTo: teacherId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              if (ElixrGroup.tryFromMap(doc.data(), id: doc.id)
                  case final group?)
                group,
          ],
        );
  }

  @override
  Future<ElixrGroup?> getGroup({required String groupId}) async {
    final snapshot = await _groups.doc(groupId).get();
    if (!snapshot.exists) return null;
    return ElixrGroup.tryFromMap(snapshot.data() ?? const {}, id: snapshot.id);
  }

  @override
  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    await _groups.doc(groupId).update({
      'name': trimmed,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  }) async {
    await _groups.doc(groupId).update({
      'status': ElixrGroupStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final groupRef = _groups.doc(groupId);
    final groupSnapshot = await groupRef.get();
    final group = groupSnapshot.exists
        ? ElixrGroup.tryFromMap(groupSnapshot.data() ?? const {}, id: groupId)
        : null;
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    if (!group.isActive) {
      throw const GroupException(
        GroupError.groupInactive,
        'Cannot rotate invite for an archived group.',
      );
    }
    final previous = group.inviteCode;
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = _generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized)) continue;
      final inviteRef = _invites.doc(normalized);
      if ((await inviteRef.get()).exists) continue;
      if ((await _legacyTeacherInvites.doc(normalized).get()).exists) continue;
      final batch = _firestore.batch();
      if (previous != null && previous.isNotEmpty && previous != normalized) {
        batch.delete(_invites.doc(previous));
      }
      batch.set(inviteRef, {
        'group_id': groupId,
        'teacher_id': teacherId,
        'teacher_display_name': teacherDisplayName,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(groupRef, {
        'invite_code': normalized,
        'updated_at': FieldValue.serverTimestamp(),
      });
      try {
        await batch.commit();
      } on FirebaseException {
        continue;
      }
      return GroupInvite(
        normalizedCode: normalized,
        groupId: groupId,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        createdAt: DateTime.now().toUtc(),
      );
    }
    throw const GroupException(
      GroupError.collisionExhausted,
      'Could not allocate a unique group invite code.',
    );
  }

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) async {
    final group = await getGroup(groupId: groupId);
    final code = group?.inviteCode;
    if (code == null || !CoachCode.isNormalized(code)) return null;
    final snapshot = await _invites.doc(code).get();
    if (!snapshot.exists) return null;
    final parsed = GroupInvite.tryFromMap(
      snapshot.data() ?? const {},
      id: snapshot.id,
    );
    return parsed?.groupId == groupId ? parsed : null;
  }

  @override
  Future<GroupInvite> resolveGroupInviteCode(String code) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const GroupException(
        GroupError.malformedCode,
        'That group code is not valid.',
      );
    }
    final snapshot = await _invites.doc(normalized).get();
    final invite = snapshot.exists
        ? GroupInvite.tryFromMap(snapshot.data() ?? const {}, id: snapshot.id)
        : null;
    if (invite == null) {
      throw const GroupException(
        GroupError.inviteNotFound,
        'No group is using that invite code.',
      );
    }
    return invite;
  }

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    GroupMembershipStatus? status,
  }) {
    Query<Map<String, dynamic>> query = _memberships.where(
      'group_id',
      isEqualTo: groupId,
    );
    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }
    return query
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              if (GroupMembership.tryFromMap(doc.data(), id: doc.id)
                  case final membership?)
                membership,
          ],
        );
  }

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) {
    return _memberships
        .where('trainee_id', isEqualTo: traineeId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              if (GroupMembership.tryFromMap(doc.data(), id: doc.id)
                  case final membership?)
                membership,
          ],
        );
  }

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) async {
    final invite = await resolveGroupInviteCode(code);
    final group = await getGroup(groupId: invite.groupId);
    if (group == null) {
      throw const GroupException(GroupError.groupNotFound);
    }
    if (!group.isActive) {
      throw const GroupException(
        GroupError.groupInactive,
        'That group is no longer accepting members.',
      );
    }
    if (invite.teacherId == traineeId) {
      throw const GroupException(
        GroupError.invalidParticipant,
        'You cannot join your own group.',
      );
    }
    final id = GroupMembership.documentId(
      groupId: invite.groupId,
      traineeId: traineeId,
    );
    final ref = _memberships.doc(id);
    final parsedExisting = await _findOwnMembership(
      groupId: invite.groupId,
      traineeId: traineeId,
    );
    if (parsedExisting?.isApproved == true) {
      throw const GroupException(
        GroupError.alreadyMember,
        'You are already a member of this group.',
      );
    }
    if (parsedExisting?.isPending == true) {
      throw const GroupException(
        GroupError.alreadyPending,
        'A request is already waiting for this group.',
      );
    }
    final payload = <String, Object?>{
      'group_id': invite.groupId,
      'teacher_id': invite.teacherId,
      'trainee_id': traineeId,
      'teacher_display_name': invite.teacherDisplayName,
      'trainee_display_name': traineeDisplayName,
      'status': GroupMembershipStatus.pending.name,
      'invite_id': invite.normalizedCode,
      'request_version': GroupMembership.currentRequestVersion,
      'updated_at': FieldValue.serverTimestamp(),
      if (parsedExisting == null) 'created_at': FieldValue.serverTimestamp(),
    };
    if (parsedExisting == null) {
      await ref.set(payload);
    } else {
      await ref.update(payload);
    }
    final written = await ref.get();
    return GroupMembership.tryFromMap(written.data() ?? const {}, id: id) ??
        GroupMembership(
          id: id,
          groupId: invite.groupId,
          teacherId: invite.teacherId,
          traineeId: traineeId,
          traineeDisplayName: traineeDisplayName,
          teacherDisplayName: invite.teacherDisplayName,
          status: GroupMembershipStatus.pending,
          inviteId: invite.normalizedCode,
          requestVersion: GroupMembership.currentRequestVersion,
        );
  }

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) => _updateStatus(
    membershipId: membershipId,
    teacherId: teacherId,
    from: GroupMembershipStatus.pending,
    to: GroupMembershipStatus.approved,
  );

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) => _updateStatus(
    membershipId: membershipId,
    teacherId: teacherId,
    from: GroupMembershipStatus.pending,
    to: GroupMembershipStatus.rejected,
  );

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) => _updateStatus(
    membershipId: membershipId,
    teacherId: teacherId,
    from: GroupMembershipStatus.approved,
    to: GroupMembershipStatus.removed,
  );

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) async {
    final ref = _memberships.doc(membershipId);
    final snapshot = await ref.get();
    final membership = snapshot.exists
        ? GroupMembership.tryFromMap(
            snapshot.data() ?? const {},
            id: membershipId,
          )
        : null;
    if (membership == null ||
        membership.traineeId != traineeId ||
        membership.status != GroupMembershipStatus.pending) {
      throw const GroupException(GroupError.notFound);
    }
    await ref.update({
      'status': GroupMembershipStatus.cancelled.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateStatus({
    required String membershipId,
    required String teacherId,
    required GroupMembershipStatus from,
    required GroupMembershipStatus to,
  }) async {
    final ref = _memberships.doc(membershipId);
    final snapshot = await ref.get();
    final membership = snapshot.exists
        ? GroupMembership.tryFromMap(
            snapshot.data() ?? const {},
            id: membershipId,
          )
        : null;
    if (membership == null ||
        membership.teacherId != teacherId ||
        membership.status != from) {
      throw const GroupException(GroupError.notFound);
    }
    await ref.update({
      'status': to.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Discovers the caller's membership with a Trainee-scoped query.
  ///
  /// Exact GET of `group_memberships/{groupId}_{traineeId}` is denied when the
  /// document does not exist because `isMembershipParticipant()` requires
  /// `resource.data`. A `trainee_id == caller` query is authorized even when
  /// empty and does not create a missing-document existence oracle.
  Future<GroupMembership?> _findOwnMembership({
    required String groupId,
    required String traineeId,
  }) async {
    final snapshot = await _memberships
        .where('trainee_id', isEqualTo: traineeId)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final expectedId = GroupMembership.documentId(
      groupId: groupId,
      traineeId: traineeId,
    );
    for (final doc in snapshot.docs) {
      if (doc.id != expectedId) continue;
      return GroupMembership.tryFromMap(doc.data(), id: doc.id);
    }
    for (final doc in snapshot.docs) {
      final parsed = GroupMembership.tryFromMap(doc.data(), id: doc.id);
      if (parsed?.groupId == groupId && parsed?.traineeId == traineeId) {
        return parsed;
      }
    }
    return null;
  }
}
