import 'dart:async';

import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

class RosterController extends ChangeNotifier {
  RosterController({
    required this.repository,
    required this.teacherId,
    required this.teacherDisplayName,
  });

  final TeacherRelationshipRepository repository;
  final String teacherId;
  final String teacherDisplayName;

  TeacherRosterInvite? invite;
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
      invite = await repository.getActiveRosterInvite(teacherId: teacherId);
      await _linksSub?.cancel();
      final first = Completer<void>();
      _linksSub = repository
          .watchTeacherLinks(teacherId: teacherId)
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
              errorMessage = 'Could not load your roster.';
              if (!first.isCompleted) first.completeError(error);
              notifyListeners();
            },
          );
      await first.future;
    } catch (_) {
      errorMessage = 'Could not load your roster.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => start();

  Future<void> generateOrRotateInvite() => _run(() async {
    invite = await repository.createOrRotateRosterInvite(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
    );
  }, 'Could not generate a roster code.');

  Future<void> revokeInvite() => _run(() async {
    await repository.revokeRosterInvite(teacherId: teacherId);
    invite = null;
  }, 'Could not revoke the roster code.');

  Future<void> approve(TeacherStudentLink link) => _run(
    () => repository.approveJoin(linkId: link.id, teacherId: teacherId),
    'Could not approve that request.',
  );

  Future<void> reject(TeacherStudentLink link) => _run(
    () => repository.rejectJoin(linkId: link.id, teacherId: teacherId),
    'Could not reject that request.',
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
