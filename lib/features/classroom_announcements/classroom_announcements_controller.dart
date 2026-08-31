import 'dart:async';

import 'package:elixr_core/models/classroom_announcement.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:flutter/foundation.dart';

class ClassroomAnnouncementsController extends ChangeNotifier {
  ClassroomAnnouncementsController({
    required this.repository,
    required this.groupId,
    required this.currentUserId,
    required this.canManage,
    required this.isGroupActive,
    this.ensureTeacherAuthorization,
  });

  final ClassroomAnnouncementRepository repository;
  final String groupId;
  final String currentUserId;
  final bool canManage;
  final bool Function() isGroupActive;
  final Future<bool> Function()? ensureTeacherAuthorization;

  List<ClassroomAnnouncement> items = const [];
  bool loading = false;
  bool loadingMore = false;
  bool busy = false;
  bool hasMore = false;
  String? errorMessage;
  String? actionMessage;

  ClassroomAnnouncementCursor? _nextCursor;
  final Set<String> _olderItemIds = {};
  StreamSubscription<ClassroomAnnouncementPage>? _subscription;
  bool _disposed = false;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    _safeNotify();
    await _subscription?.cancel();
    final first = Completer<void>();
    _subscription = repository
        .watchAnnouncements(groupId: groupId)
        .listen(
          (page) {
            if (_disposed) return;
            _applyLivePage(page);
            if (!first.isCompleted) first.complete();
            _safeNotify();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed) return;
            if (kDebugMode) {
              debugPrint('[Announcements] stream failed: $error\n$stackTrace');
            }
            errorMessage = 'Could not load announcements.';
            if (!first.isCompleted) first.completeError(error, stackTrace);
            _safeNotify();
          },
        );
    try {
      await first.future;
    } catch (_) {
      // The visible error state is assigned by the stream listener.
    } finally {
      if (!_disposed) {
        loading = false;
        _safeNotify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (loadingMore || !hasMore || cursor == null || _disposed) return;
    loadingMore = true;
    errorMessage = null;
    _safeNotify();
    try {
      final page = await repository.fetchOlderAnnouncements(
        groupId: groupId,
        startAfter: cursor,
      );
      if (_disposed) return;
      _appendOlderPage(page);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Announcements] load older failed: $error\n$stackTrace');
      }
      errorMessage = 'Could not load older announcements.';
    } finally {
      if (!_disposed) {
        loadingMore = false;
        _safeNotify();
      }
    }
  }

  Future<bool> create({required String title, required String body}) =>
      _runTeacherAction(
        operation: 'create',
        requiresActiveGroup: true,
        successMessage: 'Announcement published.',
        action: () => repository.createAnnouncement(
          groupId: groupId,
          teacherId: currentUserId,
          title: title,
          body: body,
        ),
      );

  Future<bool> update(
    ClassroomAnnouncement announcement, {
    required String title,
    required String body,
  }) => _runTeacherAction(
    operation: 'update',
    requiresActiveGroup: true,
    successMessage: 'Announcement updated.',
    action: () => repository.updateAnnouncement(
      groupId: groupId,
      announcementId: announcement.id,
      teacherId: currentUserId,
      title: title,
      body: body,
    ),
  );

  Future<bool> delete(ClassroomAnnouncement announcement) => _runTeacherAction(
    operation: 'delete',
    requiresActiveGroup: false,
    successMessage: 'Announcement deleted.',
    action: () => repository.deleteAnnouncement(
      groupId: groupId,
      announcementId: announcement.id,
      teacherId: currentUserId,
    ),
  );

  Future<bool> _runTeacherAction({
    required String operation,
    required bool requiresActiveGroup,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (_disposed || busy) return false;
    if (!canManage) {
      errorMessage = 'Only the teacher can manage announcements.';
      _safeNotify();
      return false;
    }
    if (requiresActiveGroup && !isGroupActive()) {
      errorMessage = 'Archived classes cannot be changed.';
      _safeNotify();
      return false;
    }
    busy = true;
    errorMessage = null;
    actionMessage = null;
    _safeNotify();
    try {
      final refresh = ensureTeacherAuthorization;
      if (refresh != null && !await refresh()) {
        errorMessage = 'Refresh your Teacher authorization and try again.';
        return false;
      }
      await action();
      actionMessage = successMessage;
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Announcements] $operation failed: $error\n$stackTrace');
      }
      errorMessage = _messageFor(error);
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        _safeNotify();
      }
    }
  }

  void _applyLivePage(ClassroomAnnouncementPage page) {
    final older = items.where((item) => _olderItemIds.contains(item.id));
    final merged = <String, ClassroomAnnouncement>{
      for (final item in page.items) item.id: item,
      for (final item in older) item.id: item,
    };
    items = merged.values.toList()..sort(_compare);
    hasMore = page.hasMore;
    _nextCursor = page.nextCursor;
  }

  void _appendOlderPage(ClassroomAnnouncementPage page) {
    _olderItemIds.addAll(page.items.map((item) => item.id));
    final merged = <String, ClassroomAnnouncement>{
      for (final item in items) item.id: item,
      for (final item in page.items) item.id: item,
    };
    items = merged.values.toList()..sort(_compare);
    hasMore = page.hasMore;
    _nextCursor = page.nextCursor;
  }

  static int _compare(ClassroomAnnouncement a, ClassroomAnnouncement b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static String _messageFor(Object error) {
    if (error is ArgumentError && error.message is String) {
      return error.message! as String;
    }
    return 'Could not save the announcement. Try again.';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
