import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/coach_code.dart';
import '../models/teacher_invite.dart';
import '../models/teacher_relationship_exception.dart';
import '../models/teacher_student_link.dart';
import 'teacher_relationship_repository.dart';

/// Firestore-backed [TeacherRelationshipRepository].
class FirebaseTeacherRelationshipRepository
    implements TeacherRelationshipRepository {
  FirebaseTeacherRelationshipRepository({
    FirebaseFirestore? firestore,
    String Function()? generateNormalizedCode,
    this.maxCodeAttempts = 8,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized;

  final FirebaseFirestore _firestore;
  final String Function() _generateNormalizedCode;
  final int maxCodeAttempts;

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection(FirestoreCollections.teacherInvites);

  CollectionReference<Map<String, dynamic>> get _links =>
      _firestore.collection(FirestoreCollections.teacherStudentLinks);

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _firestore.collection(FirestoreCollections.users).doc(userId);

  @override
  Future<TeacherInvite> createOrRotateInvite({
    required String traineeId,
    required String traineeDisplayName,
  }) async {
    final userRef = _userRef(traineeId);
    final userSnap = await userRef.get();
    final previousCode = userSnap.data()?['teacher_invite_code'];

    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = _generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized)) continue;

      final inviteRef = _invites.doc(normalized);
      final existing = await inviteRef.get();
      if (existing.exists) continue;

      final expiresAt = Timestamp.fromDate(
        DateTime.now().toUtc().add(CoachCode.lifetime),
      );
      final batch = _firestore.batch();
      if (previousCode is String &&
          previousCode.isNotEmpty &&
          previousCode != normalized) {
        batch.delete(_invites.doc(previousCode));
      }
      batch.set(inviteRef, {
        'trainee_id': traineeId,
        'trainee_display_name': traineeDisplayName,
        'created_at': FieldValue.serverTimestamp(),
        'expires_at': expiresAt,
      });
      batch.update(userRef, {'teacher_invite_code': normalized});
      try {
        await batch.commit();
      } on FirebaseException {
        // Exact-doc create is denied when the code is already taken; try again.
        continue;
      }

      return TeacherInvite(
        normalizedCode: normalized,
        traineeId: traineeId,
        traineeDisplayName: traineeDisplayName,
        createdAt: DateTime.now().toUtc(),
        expiresAt: expiresAt.toDate().toUtc(),
      );
    }

    throw const TeacherRelationshipException(
      TeacherRelationshipError.collisionExhausted,
      'Could not allocate a unique coach code.',
    );
  }

  @override
  Future<void> revokeInvite({required String traineeId}) async {
    final userRef = _userRef(traineeId);
    final userSnap = await userRef.get();
    final code = userSnap.data()?['teacher_invite_code'];
    final batch = _firestore.batch();
    if (code is String && code.isNotEmpty) {
      batch.delete(_invites.doc(code));
    }
    batch.update(userRef, {'teacher_invite_code': FieldValue.delete()});
    await batch.commit();
  }

  @override
  Future<TeacherInvite?> getActiveInvite({required String traineeId}) async {
    final userSnap = await _userRef(traineeId).get();
    final code = userSnap.data()?['teacher_invite_code'];
    if (code is! String || code.isEmpty) return null;
    final snap = await _invites.doc(code).get();
    if (!snap.exists) return null;
    return TeacherInvite.tryFromMap(snap.data() ?? const {}, id: snap.id);
  }

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) {
    return _links
        .where('trainee_id', isEqualTo: traineeId)
        .snapshots()
        .map(_linksFromSnapshot);
  }

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) {
    return _links
        .where('teacher_id', isEqualTo: teacherId)
        .snapshots()
        .map(_linksFromSnapshot);
  }

  @override
  Future<TeacherInvite> resolveCoachCode(String code) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.malformedCode,
        'That coach code is not valid.',
      );
    }
    final snap = await _invites.doc(normalized).get();
    final invite = snap.exists
        ? TeacherInvite.tryFromMap(snap.data() ?? const {}, id: snap.id)
        : null;
    if (invite == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.inviteNotFound,
        'No trainee is using that coach code.',
      );
    }
    if (invite.isExpired) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.inviteExpired,
        'That coach code has expired.',
      );
    }
    return invite;
  }

  @override
  Future<TeacherStudentLink> requestLink({
    required String teacherId,
    required String teacherDisplayName,
    required String code,
  }) async {
    final invite = await resolveCoachCode(code);
    if (invite.traineeId == teacherId) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
        'You cannot link to your own coach code.',
      );
    }

    final id = TeacherStudentLink.documentId(
      teacherId: teacherId,
      traineeId: invite.traineeId,
    );
    final ref = _links.doc(id);
    final existingSnap = await ref.get();
    if (existingSnap.exists) {
      final existing = TeacherStudentLink.tryFromMap(
        existingSnap.data() ?? const {},
        id: existingSnap.id,
      );
      if (existing?.isApproved ?? false) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.alreadyLinked,
          'This trainee is already on your roster.',
        );
      }
      if (existing?.isPending ?? false) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.alreadyPending,
          'A request is already waiting for this trainee.',
        );
      }

      await ref.update({
        'teacher_display_name': teacherDisplayName,
        'trainee_display_name': invite.traineeDisplayName,
        'status': TeacherStudentLinkStatus.pending.name,
        'invite_id': invite.normalizedCode,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        'teacher_id': teacherId,
        'trainee_id': invite.traineeId,
        'teacher_display_name': teacherDisplayName,
        'trainee_display_name': invite.traineeDisplayName,
        'status': TeacherStudentLinkStatus.pending.name,
        'invite_id': invite.normalizedCode,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }

    final written = await ref.get();
    return TeacherStudentLink.tryFromMap(
          written.data() ?? const {},
          id: written.id,
        ) ??
        TeacherStudentLink(
          id: id,
          teacherId: teacherId,
          traineeId: invite.traineeId,
          teacherDisplayName: teacherDisplayName,
          traineeDisplayName: invite.traineeDisplayName,
          status: TeacherStudentLinkStatus.pending,
          inviteId: invite.normalizedCode,
        );
  }

  @override
  Future<void> approveLink({
    required String linkId,
    required String traineeId,
  }) {
    return _updateOwnLink(
      linkId: linkId,
      expectedField: 'trainee_id',
      expectedId: traineeId,
      status: TeacherStudentLinkStatus.approved,
    );
  }

  @override
  Future<void> rejectLink({required String linkId, required String traineeId}) {
    return _updateOwnLink(
      linkId: linkId,
      expectedField: 'trainee_id',
      expectedId: traineeId,
      status: TeacherStudentLinkStatus.rejected,
    );
  }

  @override
  Future<void> revokeLink({required String linkId, required String traineeId}) {
    return _updateOwnLink(
      linkId: linkId,
      expectedField: 'trainee_id',
      expectedId: traineeId,
      status: TeacherStudentLinkStatus.revoked,
    );
  }

  @override
  Future<void> cancelLink({required String linkId, required String teacherId}) {
    return _updateOwnLink(
      linkId: linkId,
      expectedField: 'teacher_id',
      expectedId: teacherId,
      status: TeacherStudentLinkStatus.cancelled,
    );
  }

  Future<void> _updateOwnLink({
    required String linkId,
    required String expectedField,
    required String expectedId,
    required TeacherStudentLinkStatus status,
  }) async {
    final ref = _links.doc(linkId);
    final snap = await ref.get();
    final link = snap.exists
        ? TeacherStudentLink.tryFromMap(snap.data() ?? const {}, id: snap.id)
        : null;
    if (link == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    final actualId = expectedField == 'trainee_id'
        ? link.traineeId
        : link.teacherId;
    if (actualId != expectedId) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    await ref.update({
      'status': status.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  List<TeacherStudentLink> _linksFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final result = <TeacherStudentLink>[];
    for (final doc in snapshot.docs) {
      final link = TeacherStudentLink.tryFromMap(doc.data(), id: doc.id);
      if (link != null) result.add(link);
    }
    result.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return result;
  }
}
