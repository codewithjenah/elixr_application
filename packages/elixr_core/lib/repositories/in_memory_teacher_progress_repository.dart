import 'dart:async';

import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';
import 'teacher_progress_repository.dart';

class InMemoryTeacherProgressRepository implements TeacherProgressRepository {
  final Map<String, PublicProfileSummary?> summaries = {};
  final Map<String, List<PublicProfileSession>> sessions = {};
  final _controllers = <String, StreamController<PublicProfileSummary?>>{};

  void setSummary(String traineeId, PublicProfileSummary? summary) {
    summaries[traineeId] = summary;
    _controllers[traineeId]?.add(summary);
  }

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) {
    return (_controllers[traineeId] ??= StreamController.broadcast())
        .stream.startWith(summaries[traineeId]);
  }

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId, int pageSize = 20, TeacherProgressCursor? startAfter,
  }) async {
    if (pageSize < 1 || pageSize > 50) throw ArgumentError.value(pageSize);
    final all = List<PublicProfileSession>.from(sessions[traineeId] ?? const [])
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final offset = startAfter is _MemoryCursor ? startAfter.offset : 0;
    final page = all.skip(offset).take(pageSize).toList(growable: false);
    final next = offset + page.length;
    return TeacherProgressPage(
      sessions: page, hasMore: next < all.length,
      nextCursor: next < all.length ? _MemoryCursor(next) : null,
    );
  }
}

class _MemoryCursor extends TeacherProgressCursor {
  const _MemoryCursor(this.offset);
  final int offset;
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* { yield value; yield* this; }
}
