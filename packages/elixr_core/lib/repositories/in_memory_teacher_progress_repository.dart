import 'dart:async';

import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';
import 'teacher_progress_repository.dart';

class InMemoryTeacherProgressRepository implements TeacherProgressRepository {
  final Map<String, PublicProfileSummary?> summaries = {};
  final Map<String, List<PublicProfileSession>> sessions = {};
  final _controllers = <String, StreamController<PublicProfileSummary?>>{};

  Future<void> dispose() async {
    await Future.wait(
      _controllers.values.map((controller) => controller.close()),
    );
    _controllers.clear();
  }

  void setSummary(String traineeId, PublicProfileSummary? summary) {
    summaries[traineeId] = summary;
    _controllers[traineeId]?.add(summary);
  }

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) {
    return (_controllers[traineeId] ??= StreamController.broadcast()).stream
        .startWith(summaries[traineeId]);
  }

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) async {
    TeacherProgressRepository.validatePageSize(pageSize);
    final all = List<PublicProfileSession>.from(sessions[traineeId] ?? const [])
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    if (startAfter != null && startAfter is! _MemoryCursor) {
      throw ArgumentError('Cursor belongs to another repository');
    }
    if (startAfter is _MemoryCursor && startAfter.traineeId != traineeId) {
      throw ArgumentError('Cursor belongs to another trainee');
    }
    final offset = startAfter is _MemoryCursor ? startAfter.offset : 0;
    final page = all.skip(offset).take(pageSize).toList(growable: false);
    final next = offset + page.length;
    return TeacherProgressPage(
      sessions: page,
      hasMore: next < all.length,
      nextCursor: next < all.length ? _MemoryCursor(traineeId, next) : null,
    );
  }
}

class _MemoryCursor extends TeacherProgressCursor {
  const _MemoryCursor(this.traineeId, this.offset);
  final String traineeId;
  final int offset;
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
