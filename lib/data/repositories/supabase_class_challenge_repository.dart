import 'dart:async';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import '../models/class_challenge.dart';
import 'class_challenge_repository.dart';

/// Class Challenges: classroom-scoped reads under RLS; every mutation and the
/// attempt/best-result projections are server transactions.
class SupabaseClassChallengeRepository implements ClassChallengeRepository {
  SupabaseClassChallengeRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  final Duration requestTimeout;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  @override
  Stream<List<ClassChallenge>> watchChallengesForGroup({
    required String groupId,
    required String teacherId,
  }) {
    return _client
        .from('class_challenges')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map((rows) {
          final values = [
            for (final row in rows)
              if (row['teacher_id'] == teacherId)
                ?ClassChallenge.tryFromMap(
                  compactRow(row),
                  id: row['id'] as String,
                ),
          ];
          values.sort((a, b) => a.startAt.compareTo(b.startAt));
          return List<ClassChallenge>.unmodifiable(values);
        });
  }

  @override
  Future<ClassChallenge?> getChallenge({required String challengeId}) async {
    final row = await _client
        .from('class_challenges')
        .select()
        .eq('id', challengeId)
        .maybeSingle();
    return row == null
        ? null
        : ClassChallenge.tryFromMap(compactRow(row), id: challengeId);
  }

  @override
  Future<ClassChallenge> createChallenge({
    required ClassChallenge challenge,
  }) async {
    final response = await _call('create_class_challenge', {
      'p': challenge.toFunctionPayload(),
    });
    return _challengeFromResponse(response);
  }

  @override
  Future<ClassChallenge> updateChallenge({
    required ClassChallenge challenge,
  }) async {
    final response = await _call('update_class_challenge', {
      'p_challenge_id': challenge.id,
      'p': challenge.toFunctionPayload(),
    });
    return _challengeFromResponse(response);
  }

  @override
  Future<void> archiveChallenge({required String challengeId}) async {
    await _call('archive_class_challenge', {'p_challenge_id': challengeId});
  }

  @override
  Future<void> permanentlyDeleteChallenge({
    required String challengeId,
    required String confirmation,
  }) async {
    await _call('delete_class_challenge', {
      'p_challenge_id': challengeId,
      'p_confirmation': confirmation,
    });
  }

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchLeaderboard({
    required String challengeId,
    required String groupId,
    required String teacherId,
  }) {
    return _client
        .from('class_challenge_results')
        .stream(primaryKey: ['id'])
        .eq('challenge_id', challengeId)
        .map(
          (rows) => rankClassChallengeEntries(
            rows
                .where(
                  (row) =>
                      row['group_id'] == groupId &&
                      row['teacher_id'] == teacherId,
                )
                .map(
                  (row) => ClassChallengeLeaderboardEntry.tryFromMap(
                    compactRow(row),
                  ),
                )
                .whereType<ClassChallengeLeaderboardEntry>(),
          ),
        );
  }

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchResultsForGroup({
    required String groupId,
    required String teacherId,
  }) => _client
      .from('class_challenge_results')
      .stream(primaryKey: ['id'])
      .eq('group_id', groupId)
      .map(
        (rows) => List.unmodifiable(
          rows
              .where((row) => row['teacher_id'] == teacherId)
              .map(
                (row) =>
                    ClassChallengeLeaderboardEntry.tryFromMap(compactRow(row)),
              )
              .whereType<ClassChallengeLeaderboardEntry>(),
        ),
      );

  @override
  Stream<ClassChallengeParticipant?> watchParticipant({
    required String challengeId,
    required String traineeId,
  }) => _client
      .from('class_challenge_participants')
      .stream(primaryKey: ['id'])
      .eq('id', '${challengeId}__$traineeId')
      .map(
        (rows) => rows.isEmpty
            ? null
            : ClassChallengeParticipant.tryFromMap(compactRow(rows.first)),
      );

  @override
  Future<ClassChallengeAttempt> reserveAttempt({
    required String challengeId,
    required String requestId,
  }) async {
    final response = await _call('reserve_class_challenge_attempt', {
      'p_challenge_id': challengeId,
      'p_request_id': requestId,
    });
    final raw = response['attempt'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final map = compactRow(raw);
    final id = map.remove('id');
    final parsed = id is String
        ? ClassChallengeAttempt.tryFromMap(map, id: id)
        : null;
    if (parsed == null) throw const ClassChallengeException('malformed');
    return parsed;
  }

  @override
  Future<void> abandonAttempt({
    required String challengeId,
    required String attemptId,
  }) async {
    await _call('abandon_class_challenge_attempt', {
      'p_challenge_id': challengeId,
      'p_attempt_id': attemptId,
    });
  }

  @override
  Future<ClassChallengeLeaderboardEntry> completeAttempt({
    required String challengeId,
    required String attemptId,
    required String sessionId,
  }) async {
    final response = await _call('complete_class_challenge_attempt', {
      'p_challenge_id': challengeId,
      'p_attempt_id': attemptId,
      'p_session_id': sessionId,
    });
    final raw = response['best_result'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final parsed = ClassChallengeLeaderboardEntry.tryFromMap(compactRow(raw));
    if (parsed == null) throw const ClassChallengeException('malformed');
    return parsed;
  }

  ClassChallenge _challengeFromResponse(Map<String, dynamic> response) {
    final raw = response['challenge'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final map = compactRow(raw);
    final id = map.remove('id');
    final parsed = id is String ? ClassChallenge.tryFromMap(map, id: id) : null;
    if (parsed == null) throw const ClassChallengeException('malformed');
    return parsed;
  }

  Future<Map<String, dynamic>> _call(
    String function,
    Map<String, dynamic> params,
  ) async {
    if (_client.auth.currentUser == null) {
      throw const ClassChallengeException('forbidden');
    }
    try {
      final result = await _client
          .rpc<dynamic>(function, params: params)
          .timeout(requestTimeout);
      return result == null ? <String, dynamic>{} : asRowMap(result);
    } on PostgrestException catch (error) {
      throw ClassChallengeException(error.message);
    } on TimeoutException {
      throw const ClassChallengeException('unavailable');
    } on FormatException {
      throw const ClassChallengeException('malformed');
    } catch (error) {
      if (isBackendUnavailableError(error)) {
        throw const ClassChallengeException('offline');
      }
      rethrow;
    }
  }
}
