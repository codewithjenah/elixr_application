import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';
import '../models/teacher_progress_exception.dart';
import 'teacher_progress_repository.dart';

/// Reads sanitized public-profile projections authorized by RLS (progress
/// grant, classroom authorization, public visibility or ownership).
class SupabaseTeacherProgressRepository implements TeacherProgressRepository {
  SupabaseTeacherProgressRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// RLS filters rows silently, so an explicit check preserves the
  /// "access withdrawn" state that previously surfaced as permission-denied.
  Future<void> _requireAccess(String traineeId) async {
    final allowed = await _client.rpc<dynamic>(
      'has_progress_access',
      params: {'p_trainee_id': traineeId},
    );
    if (allowed != true) {
      throw const TeacherProgressException(
        TeacherProgressError.accessWithdrawn,
      );
    }
  }

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) async* {
    try {
      await _requireAccess(traineeId);
    } on Object catch (error) {
      throw classifyError(error);
    }
    yield* _client
        .from('public_profile_summaries')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', traineeId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : PublicProfileSummary.tryFromMap(compactRow(rows.first)),
        )
        .handleError((Object error) => throw classifyError(error));
  }

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) async {
    TeacherProgressRepository.validatePageSize(pageSize);
    if (startAfter != null && startAfter is! _SupabaseTeacherProgressCursor) {
      throw ArgumentError('Cursor belongs to another repository');
    }
    try {
      await _requireAccess(traineeId);
      var query = _client
          .from('public_profile_sessions')
          .select()
          .eq('user_id', traineeId);
      if (startAfter is _SupabaseTeacherProgressCursor) {
        query = query.or(startAfter.keysetFilter);
      }
      final rows = await query
          .order('created_at', ascending: false)
          .order('session_id', ascending: false)
          .limit(pageSize + 1);
      final hasMore = rows.length > pageSize;
      final pageRows = rows.take(pageSize).toList(growable: false);
      return TeacherProgressPage(
        sessions: _sessions(pageRows),
        hasMore: hasMore,
        nextCursor: hasMore
            ? _SupabaseTeacherProgressCursor.fromRow(pageRows.last)
            : null,
      );
    } on Object catch (error) {
      throw classifyError(error);
    }
  }

  @override
  Future<List<PublicProfileSession>> fetchSessionsInRange({
    required String traineeId,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final start = startUtc.toUtc();
    final end = endUtc.toUtc();
    if (!end.isAfter(start)) return const [];
    try {
      await _requireAccess(traineeId);
      final sessions = <PublicProfileSession>[];
      _SupabaseTeacherProgressCursor? cursor;
      while (true) {
        var query = _client
            .from('public_profile_sessions')
            .select()
            .eq('user_id', traineeId)
            .gte('created_at', start.toIso8601String())
            .lt('created_at', end.toIso8601String());
        if (cursor != null) query = query.or(cursor.keysetFilter);
        final rows = await query
            .order('created_at', ascending: false)
            .order('session_id', ascending: false)
            .limit(TeacherProgressRepository.rangePageSize);
        if (rows.isEmpty) break;
        sessions.addAll(_sessions(rows));
        if (rows.length < TeacherProgressRepository.rangePageSize) break;
        cursor = _SupabaseTeacherProgressCursor.fromRow(rows.last);
      }
      return List<PublicProfileSession>.unmodifiable(sessions);
    } on Object catch (error) {
      throw classifyError(error);
    }
  }

  static List<PublicProfileSession> _sessions(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (row) => PublicProfileSession.tryFromMap(
            compactRow(row),
            id: row['session_id'] as String,
          ),
        )
        .whereType<PublicProfileSession>()
        .toList(growable: false);
  }

  @visibleForTesting
  static TeacherProgressException classifyError(Object error) {
    if (error is TeacherProgressException) return error;
    if (isPermissionDeniedError(error)) {
      return const TeacherProgressException(
        TeacherProgressError.accessWithdrawn,
      );
    }
    return TeacherProgressException(TeacherProgressError.unavailable, '$error');
  }
}

/// Keyset cursor over (created_at desc, session_id desc).
class _SupabaseTeacherProgressCursor extends TeacherProgressCursor {
  const _SupabaseTeacherProgressCursor(this.createdAtUtc, this.sessionId);

  factory _SupabaseTeacherProgressCursor.fromRow(Map<String, dynamic> row) {
    final createdAt = DateTime.parse(row['created_at'] as String).toUtc();
    return _SupabaseTeacherProgressCursor(
      createdAt.toIso8601String(),
      row['session_id'] as String,
    );
  }

  final String createdAtUtc;
  final String sessionId;

  String get keysetFilter =>
      'created_at.lt.$createdAtUtc,'
      'and(created_at.eq.$createdAtUtc,session_id.lt.$sessionId)';
}
