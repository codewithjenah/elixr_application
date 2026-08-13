import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coach_code.dart';
import '../models/teacher_invite.dart';
import '../models/teacher_relationship_exception.dart';
import '../models/teacher_student_link.dart';
import 'teacher_relationship_repository.dart';

typedef CoachCodeGenerator = String Function();

/// In-memory [TeacherRelationshipRepository] for tests and local UI work.
class InMemoryTeacherRelationshipRepository
    implements TeacherRelationshipRepository {
  InMemoryTeacherRelationshipRepository({
    CoachCodeGenerator? generateNormalizedCode,
    DateTime Function()? now,
    this.maxCodeAttempts = 8,
  }) : generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized,
       _now = now;

  final CoachCodeGenerator generateNormalizedCode;
  final DateTime Function()? _now;
  final int maxCodeAttempts;

  final Map<String, TeacherInvite> invites = {};
  final Map<String, String> activeInviteByTrainee = {};
  final Map<String, TeacherStudentLink> links = {};

  final _traineeControllers =
      <String, StreamController<List<TeacherStudentLink>>>{};
  final _teacherControllers =
      <String, StreamController<List<TeacherStudentLink>>>{};

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  @visibleForTesting
  void seedInvite(TeacherInvite invite) {
    invites[invite.normalizedCode] = invite;
    activeInviteByTrainee[invite.traineeId] = invite.normalizedCode;
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
    _traineeControllers.clear();
    _teacherControllers.clear();
  }

  @override
  Future<TeacherInvite> createOrRotateInvite({
    required String traineeId,
    required String traineeDisplayName,
  }) async {
    final previous = activeInviteByTrainee[traineeId];
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized)) {
        continue;
      }
      if (invites.containsKey(normalized) && previous != normalized) {
        continue;
      }

      if (previous != null && previous != normalized) {
        invites.remove(previous);
      }

      final createdAt = now;
      final invite = TeacherInvite(
        normalizedCode: normalized,
        traineeId: traineeId,
        traineeDisplayName: traineeDisplayName,
        createdAt: createdAt,
        expiresAt: createdAt.add(CoachCode.lifetime),
      );
      invites[normalized] = invite;
      activeInviteByTrainee[traineeId] = normalized;
      return invite;
    }

    throw const TeacherRelationshipException(
      TeacherRelationshipError.collisionExhausted,
      'Could not allocate a unique coach code.',
    );
  }

  @override
  Future<void> revokeInvite({required String traineeId}) async {
    final code = activeInviteByTrainee.remove(traineeId);
    if (code != null) {
      invites.remove(code);
    }
  }

  @override
  Future<TeacherInvite?> getActiveInvite({required String traineeId}) async {
    final code = activeInviteByTrainee[traineeId];
    if (code == null) return null;
    return invites[code];
  }

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) {
    return _watch(
      _traineeControllers,
      traineeId,
      () => _linksForTrainee(traineeId),
    );
  }

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) {
    return _watch(
      _teacherControllers,
      teacherId,
      () => _linksForTeacher(teacherId),
    );
  }

  Stream<List<TeacherStudentLink>> _watch(
    Map<String, StreamController<List<TeacherStudentLink>>> controllers,
    String key,
    List<TeacherStudentLink> Function() current,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) {
      return existing.stream;
    }
    late final StreamController<List<TeacherStudentLink>> controller;
    controller = StreamController<List<TeacherStudentLink>>.broadcast(
      onListen: () => controller.add(current()),
    );
    controllers[key] = controller;
    return controller.stream;
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
    final invite = invites[normalized];
    if (invite == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.inviteNotFound,
        'No trainee is using that coach code.',
      );
    }
    if (invite.isExpiredAt(now)) {
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
    if (teacherId.isEmpty) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
      );
    }
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
    final existing = _findOwnLink(
      teacherId: teacherId,
      traineeId: invite.traineeId,
    );
    if (existing != null) {
      if (existing.isApproved) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.alreadyLinked,
          'This trainee is already on your roster.',
        );
      }
      if (existing.isPending) {
        throw const TeacherRelationshipException(
          TeacherRelationshipError.alreadyPending,
          'A request is already waiting for this trainee.',
        );
      }
    }

    final timestamp = now;
    final link = TeacherStudentLink(
      id: id,
      teacherId: teacherId,
      traineeId: invite.traineeId,
      teacherDisplayName: teacherDisplayName,
      traineeDisplayName: invite.traineeDisplayName,
      status: TeacherStudentLinkStatus.pending,
      inviteId: invite.normalizedCode,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    links[id] = link;
    _emit();
    return link;
  }

  @override
  Future<void> approveLink({
    required String linkId,
    required String traineeId,
  }) {
    return _traineeTransition(
      linkId: linkId,
      traineeId: traineeId,
      from: TeacherStudentLinkStatus.pending,
      to: TeacherStudentLinkStatus.approved,
    );
  }

  @override
  Future<void> rejectLink({required String linkId, required String traineeId}) {
    return _traineeTransition(
      linkId: linkId,
      traineeId: traineeId,
      from: TeacherStudentLinkStatus.pending,
      to: TeacherStudentLinkStatus.rejected,
    );
  }

  @override
  Future<void> revokeLink({required String linkId, required String traineeId}) {
    return _traineeTransition(
      linkId: linkId,
      traineeId: traineeId,
      from: TeacherStudentLinkStatus.approved,
      to: TeacherStudentLinkStatus.revoked,
    );
  }

  @override
  Future<void> cancelLink({
    required String linkId,
    required String teacherId,
  }) async {
    final link = links[linkId];
    if (link == null || link.teacherId != teacherId) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    if (!link.isPending) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
      );
    }
    links[linkId] = TeacherStudentLink(
      id: link.id,
      teacherId: link.teacherId,
      traineeId: link.traineeId,
      teacherDisplayName: link.teacherDisplayName,
      traineeDisplayName: link.traineeDisplayName,
      status: TeacherStudentLinkStatus.cancelled,
      inviteId: link.inviteId,
      createdAt: link.createdAt,
      updatedAt: now,
    );
    _emit();
  }

  Future<void> _traineeTransition({
    required String linkId,
    required String traineeId,
    required TeacherStudentLinkStatus from,
    required TeacherStudentLinkStatus to,
  }) async {
    final link = links[linkId];
    if (link == null || link.traineeId != traineeId) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      );
    }
    if (link.status != from) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
      );
    }
    links[linkId] = TeacherStudentLink(
      id: link.id,
      teacherId: link.teacherId,
      traineeId: link.traineeId,
      teacherDisplayName: link.teacherDisplayName,
      traineeDisplayName: link.traineeDisplayName,
      status: to,
      inviteId: link.inviteId,
      createdAt: link.createdAt,
      updatedAt: now,
    );
    _emit();
  }

  TeacherStudentLink? _findOwnLink({
    required String teacherId,
    required String traineeId,
  }) {
    for (final link in links.values) {
      if (link.teacherId == teacherId && link.traineeId == traineeId) {
        return link;
      }
    }
    return null;
  }

  List<TeacherStudentLink> _linksForTrainee(String traineeId) {
    final result = links.values
        .where((link) => link.traineeId == traineeId)
        .toList();
    result.sort(_byCreatedAt);
    return result;
  }

  List<TeacherStudentLink> _linksForTeacher(String teacherId) {
    final result = links.values
        .where((link) => link.teacherId == teacherId)
        .toList();
    result.sort(_byCreatedAt);
    return result;
  }

  int _byCreatedAt(TeacherStudentLink a, TeacherStudentLink b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }

  void _emit() {
    for (final entry in _traineeControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_linksForTrainee(entry.key));
      }
    }
    for (final entry in _teacherControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_linksForTeacher(entry.key));
      }
    }
  }
}
