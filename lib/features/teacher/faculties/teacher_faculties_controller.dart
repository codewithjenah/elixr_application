import 'dart:async';

import 'package:elixr_core/models/chat_user.dart';
import 'package:elixr_core/models/teacher_access_code.dart';
import 'package:elixr_core/models/teacher_access_code_exception.dart';
import 'package:elixr_core/repositories/faculty_directory_repository.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:flutter/foundation.dart';

class TeacherFacultiesController extends ChangeNotifier {
  TeacherFacultiesController({
    required this.directory,
    required this.accessCodes,
    required this.teacherId,
  });

  final FacultyDirectoryRepository directory;
  final TeacherAccessCodeRepository accessCodes;
  final String teacherId;

  List<ChatUser> teachers = const [];
  List<TeacherAccessCode> pendingCodes = const [];
  bool loading = false;
  bool busy = false;
  String? errorMessage;

  StreamSubscription<List<ChatUser>>? _teachersSub;
  StreamSubscription<List<TeacherAccessCode>>? _codesSub;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    await _teachersSub?.cancel();
    await _codesSub?.cancel();
    try {
      final teachersReady = Completer<void>();
      final codesReady = Completer<void>();
      _teachersSub = directory.watchTeachers().listen(
        (value) {
          teachers = _visibleTeachers(value);
          if (!teachersReady.isCompleted) teachersReady.complete();
          notifyListeners();
        },
        onError: (_) {
          errorMessage = 'Could not load faculties.';
          if (!teachersReady.isCompleted) teachersReady.complete();
          notifyListeners();
        },
      );
      _codesSub = accessCodes
          .watchCreatedBy(teacherId)
          .listen(
            (value) {
              pendingCodes = _unusedCodes(value);
              if (!codesReady.isCompleted) codesReady.complete();
              notifyListeners();
            },
            onError: (_) {
              if (!codesReady.isCompleted) codesReady.complete();
              notifyListeners();
            },
          );
      await Future.wait([teachersReady.future, codesReady.future]);
    } catch (_) {
      errorMessage = 'Could not load faculties.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<TeacherAccessCode?> inviteFaculty() async {
    if (busy) return null;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await accessCodes.mint(createdBy: teacherId);
    } on TeacherAccessCodeException catch (error) {
      errorMessage = error.message ?? 'Could not create an access code.';
      return null;
    } catch (_) {
      errorMessage = 'Could not create an access code.';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> revokePendingCode(TeacherAccessCode code) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await accessCodes.deleteUnused(
        createdBy: teacherId,
        normalizedCode: code.normalizedCode,
      );
    } on TeacherAccessCodeException catch (error) {
      errorMessage = error.message ?? 'Could not revoke that access code.';
    } catch (_) {
      errorMessage = 'Could not revoke that access code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<ChatUser> _visibleTeachers(List<ChatUser> value) {
    final others = [
      for (final user in value)
        if (user.id != teacherId) user,
    ];
    others.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return others;
  }

  List<TeacherAccessCode> _unusedCodes(List<TeacherAccessCode> value) {
    final unused = [
      for (final code in value)
        if (!code.consumed) code,
    ];
    unused.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return unused;
  }

  @override
  void dispose() {
    unawaited(_teachersSub?.cancel());
    unawaited(_codesSub?.cancel());
    super.dispose();
  }
}
