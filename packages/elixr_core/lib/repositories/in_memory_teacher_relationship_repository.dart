import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coach_code.dart';
import '../models/teacher_relationship_exception.dart';
import '../models/teacher_roster_invite.dart';
import '../models/teacher_student_link.dart';
import 'teacher_relationship_repository.dart';

typedef RosterCodeGenerator = String Function();

class InMemoryTeacherRelationshipRepository
    implements TeacherRelationshipRepository {
  InMemoryTeacherRelationshipRepository({
    RosterCodeGenerator? generateNormalizedCode,
    DateTime Function()? now,
    this.maxCodeAttempts = 8,
  }) : generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized,
       _now = now;

  final RosterCodeGenerator generateNormalizedCode;
  final DateTime Function()? _now;
  final int maxCodeAttempts;
  final Map<String, TeacherRosterInvite> invites = {};
  final Map<String, String> activeInviteByTeacher = {};
  final Map<String, TeacherStudentLink> links = {};
  final _traineeControllers =
      <String, StreamController<List<TeacherStudentLink>>>{};
  final _teacherControllers =
      <String, StreamController<List<TeacherStudentLink>>>{};

  /// `group_invites` codes reserved for cross-namespace collision tests.
  @visibleForTesting
  Set<String> groupInviteCodes = {};

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  @visibleForTesting
  void seedInvite(TeacherRosterInvite invite) {
    invites[invite.normalizedCode] = invite;
    activeInviteByTeacher[invite.teacherId] = invite.normalizedCode;
  }

  @visibleForTesting
  void seedLink(TeacherStudentLink link) {
    links[link.id] = link;
    _emit();
  }

  void dispose() {
    for (final controller in _traineeControllers.values) {
      controller.close();
    }
    for (final controller in _teacherControllers.values) {
      controller.close();
    }
  }

  @override
  Future<TeacherRosterInvite> createOrRotateRosterInvite({
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final previous = activeInviteByTeacher[teacherId];
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized) ||
          groupInviteCodes.contains(normalized) ||
          (invites.containsKey(normalized) && previous != normalized)) {
        continue;
      }
      if (previous != null && previous != normalized) invites.remove(previous);
      final invite = TeacherRosterInvite(
        normalizedCode: normalized,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        createdAt: now,
      );
      invites[normalized] = invite;
      activeInviteByTeacher[teacherId] = normalized;
      return invite;
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
    final code = activeInviteByTeacher[teacherId];
    return code == null ? null : invites[code];
  }

  @override
  Future<void> revokeRosterInvite({required String teacherId}) async {
    final code = activeInviteByTeacher.remove(teacherId);
    if (code != null) invites.remove(code);
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
    final invite = invites[normalized];
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
    final existing = links[id];
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
    final timestamp = now;
    final link = TeacherStudentLink(
      id: id,
      teacherId: invite.teacherId,
      traineeId: traineeId,
      teacherDisplayName: invite.teacherDisplayName,
      traineeDisplayName: traineeDisplayName,
      status: TeacherStudentLinkStatus.pending,
      inviteId: invite.normalizedCode,
      requestVersion: TeacherStudentLink.currentRequestVersion,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    links[id] = link;
    _emit();
    return link;
  }

  @override
  Future<void> approveJoin({
    required String linkId,
    required String teacherId,
  }) => _transition(
    linkId: linkId,
    participantId: teacherId,
    teacherOwned: true,
    from: TeacherStudentLinkStatus.pending,
    to: TeacherStudentLinkStatus.approved,
  );

  @override
  Future<void> rejectJoin({
    required String linkId,
    required String teacherId,
  }) => _transition(
    linkId: linkId,
    participantId: teacherId,
    teacherOwned: true,
    from: TeacherStudentLinkStatus.pending,
    to: TeacherStudentLinkStatus.rejected,
  );

  @override
  Future<void> cancelJoin({
    required String linkId,
    required String traineeId,
  }) => _transition(
    linkId: linkId,
    participantId: traineeId,
    teacherOwned: false,
    from: TeacherStudentLinkStatus.pending,
    to: TeacherStudentLinkStatus.cancelled,
  );

  @override
  Future<void> revokeLink({
    required String linkId,
    required String traineeId,
  }) => _transition(
    linkId: linkId,
    participantId: traineeId,
    teacherOwned: false,
    from: TeacherStudentLinkStatus.approved,
    to: TeacherStudentLinkStatus.revoked,
  );

  Future<void> _transition({
    required String linkId,
    required String participantId,
    required bool teacherOwned,
    required TeacherStudentLinkStatus from,
    required TeacherStudentLinkStatus to,
  }) async {
    final link = links[linkId];
    final matches = teacherOwned
        ? link?.teacherId == participantId
        : link?.traineeId == participantId;
    final requiresV2Request = from == TeacherStudentLinkStatus.pending;
    if (link == null ||
        !matches ||
        link.status != from ||
        (requiresV2Request && !link.isV2Request)) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    links[linkId] = link.copyWith(
      status: to,
      updatedAt: now,
      progressAccess: TeacherProgressAccess.none,
      clearProgressVersion: true,
      clearProgressGrantedAt: true,
      evidenceAccess: TeacherProgressAccess.none,
      clearEvidenceVersion: true,
      clearEvidenceGrantedAt: true,
    );
    _emit();
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
    final link = links[linkId];
    if (link == null || link.traineeId != traineeId || !link.isApproved) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    links[linkId] = link.copyWith(
      updatedAt: now,
      progressAccess: granted
          ? TeacherProgressAccess.granted
          : TeacherProgressAccess.none,
      progressAccessVersion: granted ? 1 : null,
      clearProgressVersion: !granted,
      progressAccessGrantedAt: granted ? now : null,
      clearProgressGrantedAt: !granted,
      evidenceAccess: granted
          ? link.evidenceAccess
          : TeacherProgressAccess.none,
      clearEvidenceVersion: !granted,
      clearEvidenceGrantedAt: !granted,
    );
    _emit();
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
    final link = links[linkId];
    if (link == null ||
        link.traineeId != traineeId ||
        !link.hasEffectiveProgressAccess) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    links[linkId] = link.copyWith(
      updatedAt: now,
      evidenceAccess: granted
          ? TeacherProgressAccess.granted
          : TeacherProgressAccess.none,
      evidenceAccessVersion: granted ? 1 : null,
      clearEvidenceVersion: !granted,
      evidenceAccessGrantedAt: granted ? now : null,
      clearEvidenceGrantedAt: !granted,
    );
    _emit();
  }

  @override
  Future<void> revokeAllEvidenceAccess({required String traineeId}) async {
    for (final entry in links.entries.toList()) {
      if (entry.value.traineeId != traineeId ||
          entry.value.evidenceAccess == TeacherProgressAccess.none) {
        continue;
      }
      links[entry.key] = entry.value.copyWith(
        updatedAt: now,
        evidenceAccess: TeacherProgressAccess.none,
        clearEvidenceVersion: true,
        clearEvidenceGrantedAt: true,
      );
    }
    _emit();
  }

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) =>
      _watch(_traineeControllers, traineeId, () => _linksForTrainee(traineeId));

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) =>
      _watch(_teacherControllers, teacherId, () => _linksForTeacher(teacherId));

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) {
    final id = TeacherStudentLink.documentId(
      teacherId: teacherId,
      traineeId: traineeId,
    );
    return Stream<TeacherStudentLinkSnapshot>.multi((controller) {
      void emit() => controller.add(
        TeacherStudentLinkSnapshot(link: links[id], isServerVerified: true),
      );
      emit();
      final subscription = watchTeacherLinks(
        teacherId: teacherId,
      ).listen((_) => emit());
      controller.onCancel = subscription.cancel;
    });
  }

  Stream<List<TeacherStudentLink>> _watch(
    Map<String, StreamController<List<TeacherStudentLink>>> controllers,
    String key,
    List<TeacherStudentLink> Function() current,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<TeacherStudentLink>> controller;
    controller = StreamController<List<TeacherStudentLink>>.broadcast(
      onListen: () => controller.add(current()),
    );
    controllers[key] = controller;
    return controller.stream;
  }

  List<TeacherStudentLink> _linksForTrainee(String id) =>
      _sorted(links.values.where((link) => link.traineeId == id));
  List<TeacherStudentLink> _linksForTeacher(String id) =>
      _sorted(links.values.where((link) => link.teacherId == id));
  List<TeacherStudentLink> _sorted(Iterable<TeacherStudentLink> values) {
    final result = values.toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  void _emit() {
    for (final entry in _traineeControllers.entries) {
      if (!entry.value.isClosed) entry.value.add(_linksForTrainee(entry.key));
    }
    for (final entry in _teacherControllers.entries) {
      if (!entry.value.isClosed) entry.value.add(_linksForTeacher(entry.key));
    }
  }
}
