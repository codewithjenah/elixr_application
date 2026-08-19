import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/coach_code.dart';
import '../models/teacher_relationship_exception.dart';
import '../models/teacher_roster_invite.dart';
import '../models/teacher_student_link.dart';
import 'teacher_relationship_repository.dart';

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
  CollectionReference<Map<String, dynamic>> get _groupInvites =>
      _firestore.collection(FirestoreCollections.groupInvites);
  CollectionReference<Map<String, dynamic>> get _links =>
      _firestore.collection(FirestoreCollections.teacherStudentLinks);
  DocumentReference<Map<String, dynamic>> _userRef(String id) =>
      _firestore.collection(FirestoreCollections.users).doc(id);

  @override
  Future<TeacherRosterInvite> createOrRotateRosterInvite({
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final userRef = _userRef(teacherId);
    final user = await userRef.get();
    final previous = user.data()?['teacher_roster_invite_code'];
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = _generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized)) continue;
      final inviteRef = _invites.doc(normalized);
      if ((await inviteRef.get()).exists) continue;
      if ((await _groupInvites.doc(normalized).get()).exists) continue;
      final batch = _firestore.batch();
      if (previous is String && previous.isNotEmpty && previous != normalized) {
        batch.delete(_invites.doc(previous));
      }
      batch.set(inviteRef, {
        'teacher_id': teacherId,
        'teacher_display_name': teacherDisplayName,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(userRef, {
        'teacher_roster_invite_code': normalized,
        // Retire a legacy Trainee-owned pointer if it is encountered.
        'teacher_invite_code': FieldValue.delete(),
      });
      try {
        await batch.commit();
      } on FirebaseException {
        continue;
      }
      return TeacherRosterInvite(
        normalizedCode: normalized,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        createdAt: DateTime.now().toUtc(),
      );
    }
    throw const TeacherRelationshipException(
      TeacherRelationshipError.collisionExhausted,
      'Could not allocate a unique roster code.',
    );
  }

  @override
  Future<TeacherRosterInvite?> getActiveRosterInvite({
    required String teacherId,
  }) async {
    final user = await _userRef(teacherId).get();
    final code = user.data()?['teacher_roster_invite_code'];
    if (code is! String || !CoachCode.isNormalized(code)) return null;
    final invite = await _invites.doc(code).get();
    if (!invite.exists) return null;
    final parsed = TeacherRosterInvite.tryFromMap(
      invite.data() ?? const {},
      id: invite.id,
    );
    return parsed?.teacherId == teacherId ? parsed : null;
  }

  @override
  Future<void> revokeRosterInvite({required String teacherId}) async {
    final userRef = _userRef(teacherId);
    final user = await userRef.get();
    final code = user.data()?['teacher_roster_invite_code'];
    final batch = _firestore.batch();
    if (code is String && code.isNotEmpty) batch.delete(_invites.doc(code));
    batch.update(userRef, {'teacher_roster_invite_code': FieldValue.delete()});
    await batch.commit();
  }

  @override
  Future<TeacherRosterInvite> resolveRosterCode(String code) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.malformedCode,
        'That roster code is not valid.',
      );
    }
    final snapshot = await _invites.doc(normalized).get();
    final invite = snapshot.exists
        ? TeacherRosterInvite.tryFromMap(
            snapshot.data() ?? const {},
            id: snapshot.id,
          )
        : null;
    if (invite == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.inviteNotFound,
        'No Teacher is using that roster code.',
      );
    }
    return invite;
  }

  @override
  Future<TeacherStudentLink> requestTeacherJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) async {
    final invite = await resolveRosterCode(code);
    if (invite.teacherId == traineeId) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
        'You cannot join your own roster.',
      );
    }
    final id = TeacherStudentLink.documentId(
      teacherId: invite.teacherId,
      traineeId: traineeId,
    );
    final ref = _links.doc(id);
    final existing = await _findOwnLink(
      teacherId: invite.teacherId,
      traineeId: traineeId,
    );
    if (existing?.isApproved == true) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.alreadyLinked,
        'This Teacher is already linked.',
      );
    }
    if (existing?.isPending == true && existing?.isV2Request == true) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.alreadyPending,
        'A request is already waiting for this Teacher.',
      );
    }
    final payload = <String, Object?>{
      'teacher_id': invite.teacherId,
      'trainee_id': traineeId,
      'teacher_display_name': invite.teacherDisplayName,
      'trainee_display_name': traineeDisplayName,
      'status': TeacherStudentLinkStatus.pending.name,
      'invite_id': invite.normalizedCode,
      'request_version': TeacherStudentLink.currentRequestVersion,
      'updated_at': FieldValue.serverTimestamp(),
      'progress_access': TeacherProgressAccess.none.name,
      'progress_access_version': FieldValue.delete(),
      'progress_access_granted_at': FieldValue.delete(),
      'evidence_access': FieldValue.delete(),
      'evidence_access_version': FieldValue.delete(),
      'evidence_access_granted_at': FieldValue.delete(),
      if (existing == null) 'created_at': FieldValue.serverTimestamp(),
    };
    if (existing == null) {
      await ref.set(payload);
    } else {
      await ref.update(payload);
    }
    final written = await ref.get();
    return TeacherStudentLink.tryFromMap(
          written.data() ?? const {},
          id: written.id,
        ) ??
        TeacherStudentLink(
          id: id,
          teacherId: invite.teacherId,
          traineeId: traineeId,
          teacherDisplayName: invite.teacherDisplayName,
          traineeDisplayName: traineeDisplayName,
          status: TeacherStudentLinkStatus.pending,
          inviteId: invite.normalizedCode,
          requestVersion: TeacherStudentLink.currentRequestVersion,
        );
  }

  @override
  Future<void> approveJoin({
    required String linkId,
    required String teacherId,
  }) => _updateStatus(
    linkId: linkId,
    participantField: 'teacher_id',
    participantId: teacherId,
    expected: TeacherStudentLinkStatus.pending,
    next: TeacherStudentLinkStatus.approved,
  );

  @override
  Future<void> rejectJoin({
    required String linkId,
    required String teacherId,
  }) => _updateStatus(
    linkId: linkId,
    participantField: 'teacher_id',
    participantId: teacherId,
    expected: TeacherStudentLinkStatus.pending,
    next: TeacherStudentLinkStatus.rejected,
  );

  @override
  Future<void> cancelJoin({
    required String linkId,
    required String traineeId,
  }) => _updateStatus(
    linkId: linkId,
    participantField: 'trainee_id',
    participantId: traineeId,
    expected: TeacherStudentLinkStatus.pending,
    next: TeacherStudentLinkStatus.cancelled,
  );

  @override
  Future<void> revokeLink({
    required String linkId,
    required String traineeId,
  }) => _updateStatus(
    linkId: linkId,
    participantField: 'trainee_id',
    participantId: traineeId,
    expected: TeacherStudentLinkStatus.approved,
    next: TeacherStudentLinkStatus.revoked,
  );

  Future<void> _updateStatus({
    required String linkId,
    required String participantField,
    required String participantId,
    required TeacherStudentLinkStatus expected,
    required TeacherStudentLinkStatus next,
  }) async {
    final ref = _links.doc(linkId);
    final snapshot = await ref.get();
    final link = snapshot.exists
        ? TeacherStudentLink.tryFromMap(
            snapshot.data() ?? const {},
            id: snapshot.id,
          )
        : null;
    final actual = participantField == 'teacher_id'
        ? link?.teacherId
        : link?.traineeId;
    final requiresV2Request = expected == TeacherStudentLinkStatus.pending;
    if (link == null ||
        actual != participantId ||
        link.status != expected ||
        (requiresV2Request && !link.isV2Request)) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    await ref.update({
      'status': next.name,
      'updated_at': FieldValue.serverTimestamp(),
      'progress_access': TeacherProgressAccess.none.name,
      'progress_access_version': FieldValue.delete(),
      'progress_access_granted_at': FieldValue.delete(),
      'evidence_access': FieldValue.delete(),
      'evidence_access_version': FieldValue.delete(),
      'evidence_access_granted_at': FieldValue.delete(),
    });
  }

  @override
  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  }) => _setProgress(linkId, traineeId, true);

  @override
  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  }) => _setProgress(linkId, traineeId, false);

  Future<void> _setProgress(
    String linkId,
    String traineeId,
    bool granted,
  ) async {
    final ref = _links.doc(linkId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final link = snapshot.exists
          ? TeacherStudentLink.tryFromMap(
              snapshot.data() ?? const {},
              id: snapshot.id,
            )
          : null;
      if (link == null || link.traineeId != traineeId || !link.isApproved) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.notFound,
        );
      }
      transaction.update(ref, {
        'progress_access': granted ? 'granted' : 'none',
        'updated_at': FieldValue.serverTimestamp(),
        'progress_access_version': granted ? 1 : FieldValue.delete(),
        'progress_access_granted_at': granted
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
        if (!granted) 'evidence_access': FieldValue.delete(),
        if (!granted) 'evidence_access_version': FieldValue.delete(),
        if (!granted) 'evidence_access_granted_at': FieldValue.delete(),
      });
    });
  }

  @override
  Future<void> grantEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => _setEvidence(linkId, traineeId, true);

  @override
  Future<void> removeEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => _setEvidence(linkId, traineeId, false);

  Future<void> _setEvidence(
    String linkId,
    String traineeId,
    bool granted,
  ) async {
    final ref = _links.doc(linkId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final link = snapshot.exists
          ? TeacherStudentLink.tryFromMap(
              snapshot.data() ?? const {},
              id: snapshot.id,
            )
          : null;
      if (link == null ||
          link.traineeId != traineeId ||
          !link.hasEffectiveProgressAccess) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.notFound,
        );
      }
      transaction.update(ref, {
        'updated_at': FieldValue.serverTimestamp(),
        'evidence_access': granted ? 'granted' : FieldValue.delete(),
        'evidence_access_version': granted ? 1 : FieldValue.delete(),
        'evidence_access_granted_at': granted
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
      });
    });
  }

  @override
  Future<void> revokeAllEvidenceAccess({required String traineeId}) async {
    final snapshot = await _links
        .where('trainee_id', isEqualTo: traineeId)
        .get();
    for (var offset = 0; offset < snapshot.docs.length; offset += 400) {
      final batch = _firestore.batch();
      for (final document in snapshot.docs.skip(offset).take(400)) {
        if (!document.data().containsKey('evidence_access')) continue;
        batch.update(document.reference, {
          'updated_at': FieldValue.serverTimestamp(),
          'evidence_access': FieldValue.delete(),
          'evidence_access_version': FieldValue.delete(),
          'evidence_access_granted_at': FieldValue.delete(),
        });
      }
      await batch.commit();
    }
  }

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) => _links
      .where('trainee_id', isEqualTo: traineeId)
      .snapshots()
      .map(_linksFromSnapshot);

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) => _links
      .where('teacher_id', isEqualTo: teacherId)
      .snapshots()
      .map(_linksFromSnapshot);

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) {
    final id = TeacherStudentLink.documentId(
      teacherId: teacherId,
      traineeId: traineeId,
    );
    return _links.doc(id).snapshots(includeMetadataChanges: true).map((doc) {
      return TeacherStudentLinkSnapshot(
        link: doc.exists
            ? TeacherStudentLink.tryFromMap(doc.data() ?? const {}, id: id)
            : null,
        isServerVerified: !doc.metadata.isFromCache,
      );
    });
  }

  Future<TeacherStudentLink?> _findOwnLink({
    required String teacherId,
    required String traineeId,
  }) async {
    final snapshot = await _links
        .where('trainee_id', isEqualTo: traineeId)
        .where('teacher_id', isEqualTo: teacherId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return TeacherStudentLink.tryFromMap(doc.data(), id: doc.id);
  }

  List<TeacherStudentLink> _linksFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final result = snapshot.docs
        .map((doc) => TeacherStudentLink.tryFromMap(doc.data(), id: doc.id))
        .whereType<TeacherStudentLink>()
        .where((link) => !link.isPending || link.isV2Request)
        .toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }
}
