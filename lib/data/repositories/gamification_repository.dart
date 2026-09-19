import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/utils/manila_day.dart';
import '../database/firestore_helper.dart';
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
/// This deliberately contains only a safe HTTP status diagnostic. It never
/// includes an ID token, response headers, or a raw response body.
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

/// Supplies an authenticated Firebase token in repository tests.
///
/// Production construction leaves this unset and verifies the current
/// Firebase user's UID before requesting its token. The Function still
/// verifies every supplied token server-side.
typedef QuestClaimTokenProvider = Future<String?> Function(String userId);

/// Persistence for the daily quest board and quest claims.
///
/// Local quest evaluation is only a progress prediction for the UI. Claiming
/// always calls the trusted Function, which derives identity, day, session
/// evidence, completion, and XP independently.
class GamificationRepository {
  GamificationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
    QuestClaimTokenProvider? tokenProvider,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _injectedFirestore = firestore,
       _injectedAuth = auth,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _tokenProvider = tokenProvider;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_ASSIGNMENTS_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  final QuestClaimTokenProvider? _tokenProvider;
  final Duration requestTimeout;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  /// Lazily resolved so unit tests can subclass this repository without
  /// constructing a Firebase app. Claim calls still require a real auth user.
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _boardRef(String boardId) =>
      _firestore.collection(FirestoreCollections.dailyQuestBoards).doc(boardId);

  /// Returns today's (Manila calendar day) board for [userId], creating it
  /// deterministically on first access. Never mutates `quest_ids`/`day_key`/
  /// `day_start` once created — a repeated call on the same real day always
  /// returns the same board, even if [currentLevel] has increased since.
  ///
  /// [currentLevel] is the already-resolved personal progression level used
  /// only when creating a new board. Callers must not invent a default
  /// Level 1 while personal progression is still loading.
  Future<DailyQuestBoard> getOrCreateDailyBoard({
    required String userId,
    required int currentLevel,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final dayKey = ManilaDay.dayKeyFor(now);
    final dayStart = ManilaDay.dayStartUtcFor(now);
    final boardRef = _boardRef(DailyQuestBoard.documentId(userId, dayKey));

    return _firestore.runTransaction<DailyQuestBoard>((tx) async {
      final snap = await tx.get(boardRef);
      if (snap.exists && snap.data() != null) {
        final existing = DailyQuestBoard.tryFromMap(snap.data()!);
        if (existing != null) return existing;
      }

      final questIds = generateDailyQuestIds(
        userId: userId,
        dayKey: dayKey,
        currentLevel: currentLevel,
      );
      final board = DailyQuestBoard(
        userId: userId,
        dayKey: dayKey,
        dayStart: dayStart,
        questIds: questIds,
      );
      tx.set(boardRef, {
        ...board.toMap(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return board;
    });
  }

  /// Live set of claimed quest ids for [userId]'s board [boardId]. Filters
  /// on both fields (matches the `user_id`+`board_id` composite index in
  /// `firestore.indexes.json` and the ownership-scoped `list` rule).
  Stream<Set<String>> watchClaimedQuestIds({
    required String userId,
    required String boardId,
  }) {
    return _firestore
        .collection(FirestoreCollections.dailyQuestClaims)
        .where('user_id', isEqualTo: userId)
        .where('board_id', isEqualTo: boardId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => doc.data()['quest_id'])
              .whereType<String>()
              .toSet();
        });
  }

  /// Claims [questId] through the trusted Firebase Function. [userId],
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
    final token = await _resolveToken(userId);
    if (token == null || token.isEmpty) {
      throw StateError('Unable to authenticate quest claim.');
    }
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(apiBaseUri.resolve('claimDailyQuest'))
          .timeout(requestTimeout);
      request.headers.set('X-Firebase-Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'quest_id': questId}));
      final response = await request.close().timeout(requestTimeout);
      final raw = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      return parseQuestClaimResponse(
        statusCode: response.statusCode,
        contentType: response.headers.contentType?.mimeType,
        rawBody: raw,
      );
    } on QuestClaimServiceException {
      rethrow;
    } on TimeoutException {
      throw const QuestClaimServiceException(QuestClaimServiceError.timedOut);
    } on SocketException {
      throw const QuestClaimServiceException(QuestClaimServiceError.network);
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _resolveToken(String userId) async {
    final tokenProvider = _tokenProvider;
    if (tokenProvider != null) return tokenProvider(userId);

    final user = _auth.currentUser;
    if (user == null || user.uid != userId) {
      throw StateError('A matching authenticated user is required.');
    }
    return user.getIdToken(true);
  }
}

/// Converts the Function's JSON contract into the existing typed outcomes.
///
/// The Function is authoritative for eligibility and awards. This parser
/// accepts only its known JSON responses; gateway HTML, empty bodies, and
/// malformed payloads become controlled service errors instead of leaking a
/// [FormatException] to the UI.
QuestClaimResult parseQuestClaimResponse({
  required int statusCode,
  required String? contentType,
  required String rawBody,
}) {
  if (statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.forbidden) {
    throw QuestClaimServiceException(
      QuestClaimServiceError.unauthorized,
      statusCode: statusCode,
    );
  }
  if (statusCode != HttpStatus.ok && statusCode != HttpStatus.badRequest) {
    throw QuestClaimServiceException(
      QuestClaimServiceError.unavailable,
      statusCode: statusCode,
    );
  }
  if (rawBody.trim().isEmpty ||
      (contentType != null &&
          contentType.toLowerCase() != 'application/json')) {
    throw QuestClaimServiceException(
      QuestClaimServiceError.malformedResponse,
      statusCode: statusCode,
    );
  }

  final Object decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException {
    throw QuestClaimServiceException(
      QuestClaimServiceError.malformedResponse,
      statusCode: statusCode,
    );
  }
  if (decoded is! Map) {
    throw QuestClaimServiceException(
      QuestClaimServiceError.malformedResponse,
      statusCode: statusCode,
    );
  }

  final response = Map<String, dynamic>.from(decoded);
  final status = response['status'] ?? response['error'];
  if (statusCode == HttpStatus.badRequest && status != 'invalid_quest') {
    throw QuestClaimServiceException(
      QuestClaimServiceError.unavailable,
      statusCode: statusCode,
    );
  }
  return switch (status) {
    'claimed' when statusCode == HttpStatus.ok => QuestClaimResult.claimed(
      (response['xp_awarded'] as num?)?.toInt() ?? 0,
    ),
    'already_claimed' when statusCode == HttpStatus.ok =>
      const QuestClaimResult.alreadyClaimed(),
    'quest_not_completed' || 'invalid_evidence'
        when statusCode == HttpStatus.ok =>
      const QuestClaimResult.questNotCompleted(),
    'board_missing' when statusCode == HttpStatus.ok =>
      const QuestClaimResult.boardMissing(),
    'leaderboard_missing' when statusCode == HttpStatus.ok =>
      const QuestClaimResult.leaderboardMissing(),
    'invalid_quest'
        when statusCode == HttpStatus.badRequest ||
            statusCode == HttpStatus.ok =>
      const QuestClaimResult.invalidQuest(),
    _ => throw QuestClaimServiceException(
      QuestClaimServiceError.unavailable,
      statusCode: statusCode,
    ),
  };
}
