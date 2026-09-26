import 'dart:async';
import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import '../../core/utils/manila_day.dart';
import '../models/daily_quest.dart';
import '../models/daily_quest_board.dart';
import '../models/quest_claim.dart';
import '../models/session.dart';

/// The reason a trusted quest-claim request could not be completed.
enum QuestClaimServiceError {
  unauthorized,
  unavailable,
  malformedResponse,
  timedOut,
  network,
}

/// A controlled failure from the trusted daily-quest claim service.
///
/// This deliberately contains only a safe status diagnostic. It never
/// includes an access token or a raw response body.
class QuestClaimServiceException implements Exception {
  const QuestClaimServiceException(this.error, {this.statusCode});

  final QuestClaimServiceError error;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    return switch (error) {
      QuestClaimServiceError.unauthorized =>
        'Quest claim authorization failed$status.',
      QuestClaimServiceError.unavailable =>
        'Quest claim service is unavailable$status.',
      QuestClaimServiceError.malformedResponse =>
        'Quest claim service returned an invalid response$status.',
      QuestClaimServiceError.timedOut => 'Quest claim service timed out.',
      QuestClaimServiceError.network => 'Quest claim service is unavailable.',
    };
  }
}

/// Persistence for the daily quest board and quest claims.
///
/// Local quest evaluation is only a progress prediction for the UI. Claiming
/// always calls the trusted database function, which derives identity, day,
/// session evidence, completion, and XP independently.
class GamificationRepository {
  GamificationRepository({
    SupabaseClient? client,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  final Duration requestTimeout;

  /// Lazily resolved so unit tests can subclass this repository without
  /// initializing Supabase. Claim calls still require a real auth user.
  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// Returns today's (Manila calendar day) board for [userId], creating it
  /// deterministically on first access. Never mutates `quest_ids`/`day_key`/
  /// `day_start` once created — a repeated call on the same real day always
  /// returns the same board, even if [currentLevel] has increased since.
  ///
  /// [currentLevel] is the already-resolved personal progression level used
  /// only when creating a new board. Callers must not invent a default
  /// Level 1 while personal progression is still loading. The server owns the
  /// Manila day and validates the proposed quest set.
  Future<DailyQuestBoard> getOrCreateDailyBoard({
    required String userId,
    required int currentLevel,
    DateTime? nowUtc,
  }) async {
    _requireUser(userId);
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final questIds = generateDailyQuestIds(
      userId: userId,
      dayKey: ManilaDay.dayKeyFor(now),
      currentLevel: currentLevel,
    );
    final row = await rpcMap(_client, 'get_or_create_daily_quest_board', {
      'p_quest_ids': questIds,
    });
    return DailyQuestBoard.tryFromMap(compactRow(row)) ??
        (throw const FormatException('Malformed daily quest board.'));
  }

  /// Live set of claimed quest ids for [userId]'s board [boardId]. RLS limits
  /// the stream to the caller's own claims.
  Stream<Set<String>> watchClaimedQuestIds({
    required String userId,
    required String boardId,
  }) {
    return _client
        .from('daily_quest_claims')
        .stream(primaryKey: ['id'])
        .eq('board_id', boardId)
        .map(
          (rows) => rows
              .where((row) => row['user_id'] == userId)
              .map((row) => row['quest_id'])
              .whereType<String>()
              .toSet(),
        );
  }

  /// Claims [questId] through the trusted database function. [userId],
  /// [sessionsToday], and [nowUtc] remain for source compatibility and local
  /// UX only; none are sent as award authority.
  Future<QuestClaimResult> claimQuest({
    required String userId,
    required String questId,
    required List<Session> sessionsToday,
    DateTime? nowUtc,
  }) async {
    final quest = questById(questId);
    if (quest == null) {
      return const QuestClaimResult.invalidQuest();
    }
    // Local progress is advisory only. A user-initiated claim must reach the
    // server because cached or filtered client sessions can be stale.
    quest.evaluate(sessionsToday);
    _requireUser(userId);
    try {
      final response = await _client
          .rpc<dynamic>('claim_daily_quest', params: {'p_quest_id': questId})
          .timeout(requestTimeout);
      return parseQuestClaimResponse(response);
    } on QuestClaimServiceException {
      rethrow;
    } on TimeoutException {
      throw const QuestClaimServiceException(QuestClaimServiceError.timedOut);
    } on SocketException {
      throw const QuestClaimServiceException(QuestClaimServiceError.network);
    } on PostgrestException catch (error) {
      throw QuestClaimServiceException(
        isPermissionDeniedError(error)
            ? QuestClaimServiceError.unauthorized
            : QuestClaimServiceError.unavailable,
      );
    } catch (error) {
      if (isBackendUnavailableError(error)) {
        throw const QuestClaimServiceException(QuestClaimServiceError.network);
      }
      rethrow;
    }
  }

  void _requireUser(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('A matching authenticated user is required.');
    }
  }
}

/// Converts the claim function's JSON result into the typed outcomes.
///
/// The server is authoritative for eligibility and awards. This parser
/// accepts only its known results; malformed payloads become controlled
/// service errors instead of leaking a type error to the UI.
QuestClaimResult parseQuestClaimResponse(Object? decoded) {
  if (decoded is! Map) {
    throw const QuestClaimServiceException(
      QuestClaimServiceError.malformedResponse,
    );
  }
  return switch (decoded['status']) {
    'claimed' => QuestClaimResult.claimed(
      (decoded['xp_awarded'] as num?)?.toInt() ?? 0,
    ),
    'already_claimed' => const QuestClaimResult.alreadyClaimed(),
    'quest_not_completed' ||
    'invalid_evidence' => const QuestClaimResult.questNotCompleted(),
    'board_missing' => const QuestClaimResult.boardMissing(),
    'leaderboard_missing' => const QuestClaimResult.leaderboardMissing(),
    'invalid_quest' => const QuestClaimResult.invalidQuest(),
    _ => throw const QuestClaimServiceException(
      QuestClaimServiceError.malformedResponse,
    ),
  };
}
