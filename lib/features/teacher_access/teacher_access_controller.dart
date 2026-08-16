import 'dart:async';

import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

enum JoinTeacherStep { enterCode, confirm }

class TeacherAccessController extends ChangeNotifier {
  TeacherAccessController({
    required this.repository,
    required this.traineeId,
    required this.traineeDisplayName,
    this.privateImageSavingEnabled = false,
    this.reconcileEvidenceAvailability,
    this.onJoinCompleted,
  });

  final TeacherRelationshipRepository repository;
  final String traineeId;
  final String traineeDisplayName;
  final bool privateImageSavingEnabled;
  final Future<void> Function(String traineeId)? reconcileEvidenceAvailability;
  final VoidCallback? onJoinCompleted;

  List<TeacherStudentLink> pending = const [];
  List<TeacherStudentLink> approved = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  String codeInput = '';
  JoinTeacherStep joinStep = JoinTeacherStep.enterCode;
  TeacherRosterInvite? resolvedInvite;
  String? joinError;
  StreamSubscription<List<TeacherStudentLink>>? _linksSub;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _linksSub?.cancel();
      final first = Completer<void>();
      _linksSub = repository
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
              if (!first.isCompleted) first.complete();
              notifyListeners();
            },
            onError: (Object error) {
              errorMessage = 'Could not load Teacher Access.';
              if (!first.isCompleted) first.completeError(error);
              notifyListeners();
            },
          );
      await first.future;
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
    resolvedInvite = null;
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
    resolvedInvite = null;
    joinError = null;
    notifyListeners();
  }

  Future<void> resolveCode() async {
    if (busy) return;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      resolvedInvite = await repository.resolveRosterCode(codeInput);
      joinStep = JoinTeacherStep.confirm;
    } on TeacherRelationshipException catch (error) {
      joinError = switch (error.code) {
        TeacherRelationshipError.malformedCode =>
          'That roster code is not valid.',
        TeacherRelationshipError.inviteNotFound =>
          'No Teacher is using that roster code.',
        _ => error.message ?? 'Could not look up that roster code.',
      };
    } catch (_) {
      joinError = 'Could not look up that roster code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> confirmJoin() async {
    final invite = resolvedInvite;
    if (busy || invite == null) return false;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      final link = await repository.requestTeacherJoin(
        traineeId: traineeId,
        traineeDisplayName: traineeDisplayName,
        code: invite.normalizedCode,
      );
      pending = [link, ...pending.where((item) => item.id != link.id)];
      resetJoin();
      onJoinCompleted?.call();
      return true;
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
    await repository.cancelJoin(linkId: link.id, traineeId: traineeId);
    pending = pending.where((item) => item.id != link.id).toList();
  }, 'Could not cancel that request.');

  Future<void> revokeTeacher(TeacherStudentLink link) => _run(
    () => repository.revokeLink(linkId: link.id, traineeId: traineeId),
    'Could not revoke that Teacher.',
  );

  Future<void> shareProgress(TeacherStudentLink link) => _run(
    () => repository.grantProgressAccess(linkId: link.id, traineeId: traineeId),
    'Could not enable progress sharing. Check your connection and try again.',
  );

  Future<void> stopSharingProgress(TeacherStudentLink link) => _run(
    () =>
        repository.removeProgressAccess(linkId: link.id, traineeId: traineeId),
    'Could not stop progress sharing. Check your connection and try again.',
  );

  Future<void> shareEvidence(TeacherStudentLink link) => _run(
    () async {
      if (!privateImageSavingEnabled) {
        throw StateError('Private image saving is disabled');
      }
      await reconcileEvidenceAvailability?.call(traineeId);
      await repository.grantEvidenceAccess(
        linkId: link.id,
        traineeId: traineeId,
      );
    },
    'Could not enable saved-image sharing. Check your connection and try again.',
  );

  Future<void> stopSharingEvidence(TeacherStudentLink link) => _run(
    () =>
        repository.removeEvidenceAccess(linkId: link.id, traineeId: traineeId),
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

  @override
  void dispose() {
    unawaited(_linksSub?.cancel());
    super.dispose();
  }
}
