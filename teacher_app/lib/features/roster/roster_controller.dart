import 'dart:async';

import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

enum AddStudentStep { enterCode, confirm }

/// Teacher-side roster state.
class RosterController extends ChangeNotifier {
  RosterController({
    required this.repository,
    required this.teacherId,
    required this.teacherDisplayName,
  });

  final TeacherRelationshipRepository repository;
  final String teacherId;
  final String teacherDisplayName;

  List<TeacherStudentLink> pending = const [];
  List<TeacherStudentLink> approved = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;

  AddStudentStep addStudentStep = AddStudentStep.enterCode;
  String codeInput = '';
  TeacherInvite? resolvedInvite;
  String? addStudentError;

  StreamSubscription<List<TeacherStudentLink>>? _linksSub;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _linksSub?.cancel();
      final first = Completer<void>();
      _linksSub = repository
          .watchTeacherLinks(teacherId: teacherId)
          .listen(
            (links) {
              _onLinks(links);
              if (!first.isCompleted) first.complete();
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

  void resetAddStudent() {
    addStudentStep = AddStudentStep.enterCode;
    codeInput = '';
    resolvedInvite = null;
    addStudentError = null;
    notifyListeners();
  }

  void setCodeInput(String value) {
    codeInput = value;
    addStudentError = null;
    notifyListeners();
  }

  Future<void> resolveEnteredCode() async {
    if (busy) return;
    busy = true;
    addStudentError = null;
    notifyListeners();
    try {
      resolvedInvite = await repository.resolveCoachCode(codeInput);
      addStudentStep = AddStudentStep.confirm;
    } on TeacherRelationshipException catch (error) {
      addStudentError = switch (error.code) {
        TeacherRelationshipError.malformedCode =>
          'That coach code is not valid.',
        TeacherRelationshipError.inviteNotFound =>
          'No trainee is using that coach code.',
        TeacherRelationshipError.inviteExpired =>
          'That coach code has expired.',
        _ => error.message ?? 'Could not look up that code.',
      };
    } catch (_) {
      addStudentError = 'Could not look up that code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> confirmRequest() async {
    final invite = resolvedInvite;
    if (invite == null || busy) return false;
    busy = true;
    addStudentError = null;
    notifyListeners();
    try {
      await repository.requestLink(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        code: invite.normalizedCode,
      );
      resetAddStudent();
      return true;
    } on TeacherRelationshipException catch (error) {
      addStudentError = switch (error.code) {
        TeacherRelationshipError.alreadyPending =>
          'A request is already waiting for this trainee.',
        TeacherRelationshipError.alreadyLinked =>
          'This trainee is already on your roster.',
        TeacherRelationshipError.inviteExpired =>
          'That coach code has expired.',
        TeacherRelationshipError.malformedCode =>
          'That coach code is not valid.',
        TeacherRelationshipError.inviteNotFound =>
          'No trainee is using that coach code.',
        _ => error.message ?? 'Could not send that request.',
      };
      return false;
    } catch (_) {
      addStudentError = 'Could not send that request.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancelPending(TeacherStudentLink link) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.cancelLink(linkId: link.id, teacherId: teacherId);
    } catch (_) {
      errorMessage = 'Could not cancel that request.';
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
