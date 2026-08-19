import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

import '../../services/join_code_resolver.dart';

enum JoinTeacherStep { enterCode, confirm }

class TeacherAccessController extends ChangeNotifier {
  TeacherAccessController({
    required this.relationshipRepository,
    required this.groupRepository,
    required this.joinCodeResolver,
    required this.traineeId,
    required this.traineeDisplayName,
    this.privateImageSavingEnabled = false,
    this.reconcileEvidenceAvailability,
    this.onJoinCompleted,
  });

  final TeacherRelationshipRepository relationshipRepository;
  final GroupRepository groupRepository;
  final JoinCodeResolver joinCodeResolver;
  final String traineeId;
  final String traineeDisplayName;
  final bool privateImageSavingEnabled;
  final Future<void> Function(String traineeId)? reconcileEvidenceAvailability;
  final VoidCallback? onJoinCompleted;

  List<TeacherStudentLink> pending = const [];
  List<TeacherStudentLink> approved = const [];
  List<GroupMembership> pendingGroupMemberships = const [];
  List<GroupMembership> approvedGroupMemberships = const [];
  final Map<String, ElixrGroup> groupNamesById = {};
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  String codeInput = '';
  JoinTeacherStep joinStep = JoinTeacherStep.enterCode;
  JoinCodeKind? resolvedKind;
  TeacherRosterInvite? resolvedTeacherInvite;
  GroupInvite? resolvedGroupInvite;
  String? joinError;
  StreamSubscription<List<TeacherStudentLink>>? _linksSub;
  StreamSubscription<List<GroupMembership>>? _groupMembershipsSub;
  bool _disposed = false;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _linksSub?.cancel();
      await _groupMembershipsSub?.cancel();
      final firstLinks = Completer<void>();
      final firstGroups = Completer<void>();
      _linksSub = relationshipRepository
          .watchTraineeLinks(traineeId: traineeId)
          .listen(
            (links) {
              pending = [
                for (final link in links)
                  if (link.isPending && link.isV2Request) link,
              ];
              approved = [
                for (final link in links)
                  if (link.isApproved) link,
              ];
              if (!firstLinks.isCompleted) firstLinks.complete();
              notifyListeners();
            },
            onError: (Object error) {
              errorMessage = 'Could not load Teacher Access.';
              if (!firstLinks.isCompleted) firstLinks.completeError(error);
              notifyListeners();
            },
          );
      _groupMembershipsSub = groupRepository
          .watchTraineeMemberships(traineeId: traineeId)
          .listen(
            (memberships) {
              pendingGroupMemberships = [
                for (final membership in memberships)
                  if (membership.isPending) membership,
              ];
              approvedGroupMemberships = [
                for (final membership in memberships)
                  if (membership.isApproved) membership,
              ];
              if (!firstGroups.isCompleted) firstGroups.complete();
              _safeNotifyListeners();
              unawaited(_refreshGroupNames(memberships));
            },
            onError: (Object error) {
              errorMessage = 'Could not load group memberships.';
              if (!firstGroups.isCompleted) firstGroups.completeError(error);
              notifyListeners();
            },
          );
      await Future.wait([firstLinks.future, firstGroups.future]);
    } catch (_) {
      errorMessage = 'Could not load Teacher Access.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void prefillCode(String code) {
    codeInput = code;
    joinStep = JoinTeacherStep.enterCode;
    resolvedKind = null;
    resolvedTeacherInvite = null;
    resolvedGroupInvite = null;
    joinError = null;
    notifyListeners();
  }

  void setCodeInput(String value) {
    codeInput = value;
    joinError = null;
    notifyListeners();
  }

  void resetJoin() {
    codeInput = '';
    joinStep = JoinTeacherStep.enterCode;
    resolvedKind = null;
    resolvedTeacherInvite = null;
    resolvedGroupInvite = null;
    joinError = null;
    notifyListeners();
  }

  Future<void> resolveCode() async {
    if (busy) return;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      final resolved = await joinCodeResolver.resolve(codeInput);
      resolvedKind = resolved.kind;
      switch (resolved) {
        case ResolvedGroupJoinCode(:final invite):
          resolvedGroupInvite = invite;
          resolvedTeacherInvite = null;
        case ResolvedTeacherRosterJoinCode(:final invite):
          resolvedTeacherInvite = invite;
          resolvedGroupInvite = null;
      }
      joinStep = JoinTeacherStep.confirm;
    } on GroupException catch (error) {
      joinError = switch (error.code) {
        GroupError.malformedCode => 'That code is not valid.',
        GroupError.inviteNotFound =>
          'No group or Teacher roster is using that code.',
        _ => error.message ?? 'Could not look up that code.',
      };
    } catch (_) {
      joinError = 'Could not look up that code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> confirmJoin() async {
    if (busy) return false;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      switch (resolvedKind) {
        case JoinCodeKind.groupInvite:
          final invite = resolvedGroupInvite;
          if (invite == null) return false;
          final membership = await groupRepository.requestGroupJoin(
            traineeId: traineeId,
            traineeDisplayName: traineeDisplayName,
            code: invite.normalizedCode,
          );
          pendingGroupMemberships = [
            membership,
            ...pendingGroupMemberships.where(
              (item) => item.id != membership.id,
            ),
          ];
        case JoinCodeKind.teacherRosterInvite:
          final invite = resolvedTeacherInvite;
          if (invite == null) return false;
          final link = await relationshipRepository.requestTeacherJoin(
            traineeId: traineeId,
            traineeDisplayName: traineeDisplayName,
            code: invite.normalizedCode,
          );
          pending = [link, ...pending.where((item) => item.id != link.id)];
        case null:
          return false;
      }
      resetJoin();
      onJoinCompleted?.call();
      return true;
    } on GroupException catch (error) {
      joinError = switch (error.code) {
        GroupError.alreadyPending =>
          'A request is already waiting for this group.',
        GroupError.alreadyMember => 'You are already a member of this group.',
        GroupError.groupInactive =>
          'That group is no longer accepting members.',
        _ => error.message ?? 'Could not send that request.',
      };
      return false;
    } on TeacherRelationshipException catch (error) {
      joinError = switch (error.code) {
        TeacherRelationshipError.alreadyPending =>
          'A request is already waiting for this Teacher.',
        TeacherRelationshipError.alreadyLinked =>
          'This Teacher is already linked.',
        _ => error.message ?? 'Could not send that request.',
      };
      return false;
    } catch (_) {
      joinError = 'Could not send that request.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancelPending(TeacherStudentLink link) => _run(() async {
    await relationshipRepository.cancelJoin(
      linkId: link.id,
      traineeId: traineeId,
    );
    pending = pending.where((item) => item.id != link.id).toList();
  }, 'Could not cancel that request.');

  Future<void> cancelPendingGroup(GroupMembership membership) => _run(() async {
    await groupRepository.cancelMembership(
      membershipId: membership.id,
      traineeId: traineeId,
    );
    pendingGroupMemberships = pendingGroupMemberships
        .where((item) => item.id != membership.id)
        .toList();
  }, 'Could not cancel that group request.');

  Future<void> revokeTeacher(TeacherStudentLink link) => _run(
    () => relationshipRepository.revokeLink(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not revoke that Teacher.',
  );

  Future<void> shareProgress(TeacherStudentLink link) => _run(
    () => relationshipRepository.grantProgressAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not enable progress sharing. Check your connection and try again.',
  );

  Future<void> stopSharingProgress(TeacherStudentLink link) => _run(
    () => relationshipRepository.removeProgressAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not stop progress sharing. Check your connection and try again.',
  );

  Future<void> shareEvidence(TeacherStudentLink link) => _run(
    () async {
      if (!privateImageSavingEnabled) {
        throw StateError('Private image saving is disabled');
      }
      await reconcileEvidenceAvailability?.call(traineeId);
      await relationshipRepository.grantEvidenceAccess(
        linkId: link.id,
        traineeId: traineeId,
      );
    },
    'Could not enable saved-image sharing. Check your connection and try again.',
  );

  Future<void> stopSharingEvidence(TeacherStudentLink link) => _run(
    () => relationshipRepository.removeEvidenceAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not stop saved-image sharing.',
  );

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      errorMessage = failure;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshGroupNames(List<GroupMembership> memberships) async {
    for (final membership in memberships) {
      if (_disposed) return;
      final group = await groupRepository.getGroup(groupId: membership.groupId);
      if (group != null) {
        groupNamesById[membership.groupId] = group;
      }
    }
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_linksSub?.cancel());
    unawaited(_groupMembershipsSub?.cancel());
    super.dispose();
  }
}
