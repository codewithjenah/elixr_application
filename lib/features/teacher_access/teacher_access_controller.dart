import 'dart:async';

import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

/// Trainee-side Teacher Access state.
class TeacherAccessController extends ChangeNotifier {
  TeacherAccessController({
    required this.repository,
    required this.traineeId,
    required this.traineeDisplayName,
  });

  final TeacherRelationshipRepository repository;
  final String traineeId;
  final String traineeDisplayName;

  TeacherInvite? invite;
  List<TeacherStudentLink> pending = const [];
  List<TeacherStudentLink> approved = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  StreamSubscription<List<TeacherStudentLink>>? _linksSub;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      invite = await repository.getActiveInvite(traineeId: traineeId);
      await _linksSub?.cancel();
      final first = Completer<void>();
      _linksSub = repository
          .watchTraineeLinks(traineeId: traineeId)
          .listen(
            (links) {
              _onLinks(links);
              if (!first.isCompleted) first.complete();
            },
            onError: (Object error) {
              errorMessage = 'Could not load Teacher requests.';
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

  Future<void> generateOrRotate() async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      invite = await repository.createOrRotateInvite(
        traineeId: traineeId,
        traineeDisplayName: traineeDisplayName,
      );
    } catch (_) {
      errorMessage = 'Could not generate a coach code. Please try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> revokeInvite() async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.revokeInvite(traineeId: traineeId);
      invite = null;
    } catch (_) {
      errorMessage = 'Could not revoke the coach code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> approve(TeacherStudentLink link) {
    return _runLinkAction(
      () => repository.approveLink(linkId: link.id, traineeId: traineeId),
      failure: 'Could not approve that request.',
    );
  }

  Future<void> reject(TeacherStudentLink link) {
    return _runLinkAction(
      () => repository.rejectLink(linkId: link.id, traineeId: traineeId),
      failure: 'Could not reject that request.',
    );
  }

  Future<void> revokeTeacher(TeacherStudentLink link) {
    return _runLinkAction(
      () => repository.revokeLink(linkId: link.id, traineeId: traineeId),
      failure: 'Could not revoke that Teacher.',
    );
  }

  Future<void> shareProgress(TeacherStudentLink link) {
    return _runLinkAction(
      () => repository.grantProgressAccess(linkId: link.id, traineeId: traineeId),
      failure: 'Could not enable progress sharing. Check your connection and try again.',
    );
  }

  Future<void> stopSharingProgress(TeacherStudentLink link) {
    return _runLinkAction(
      () => repository.removeProgressAccess(linkId: link.id, traineeId: traineeId),
      failure: 'Could not stop progress sharing. Check your connection and try again.',
    );
  }

  Future<void> _runLinkAction(
    Future<void> Function() action, {
    required String failure,
  }) async {
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

  void _onLinks(List<TeacherStudentLink> links) {
    pending = [
      for (final link in links)
        if (link.isPending) link,
    ];
    approved = [
      for (final link in links)
        if (link.isApproved) link,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_linksSub?.cancel());
    super.dispose();
  }
}
