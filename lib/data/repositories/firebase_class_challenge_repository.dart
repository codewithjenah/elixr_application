import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/class_challenge.dart';
import 'class_challenge_repository.dart';

class FirebaseClassChallengeRepository implements ClassChallengeRepository {
  FirebaseClassChallengeRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_ASSIGNMENTS_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _firestore.collection('class_challenges');
  CollectionReference<Map<String, dynamic>> get _results =>
      _firestore.collection('class_challenge_results');
  CollectionReference<Map<String, dynamic>> get _participants =>
      _firestore.collection('class_challenge_participants');

  @override
  Stream<List<ClassChallenge>> watchChallengesForGroup({
    required String groupId,
  }) {
    return _challenges.where('group_id', isEqualTo: groupId).snapshots().map((
      snapshot,
    ) {
      final values = snapshot.docs
          .map((doc) => ClassChallenge.tryFromMap(doc.data(), id: doc.id))
          .whereType<ClassChallenge>()
          .toList();
      values.sort((a, b) => a.startAt.compareTo(b.startAt));
      return List.unmodifiable(values);
    });
  }

  @override
  Future<ClassChallenge?> getChallenge({required String challengeId}) async {
    final doc = await _challenges.doc(challengeId).get();
    final data = doc.data();
    return data == null
        ? null
        : ClassChallenge.tryFromMap(data, id: challengeId);
  }

  @override
  Future<ClassChallenge> createChallenge({
    required ClassChallenge challenge,
  }) async {
    final response = await _post('createClassChallenge', challenge.toFunctionPayload());
    return _challengeFromResponse(response);
  }

  @override
  Future<ClassChallenge> updateChallenge({
    required ClassChallenge challenge,
  }) async {
    final response = await _post('updateClassChallenge', {
      'challenge_id': challenge.id,
      ...challenge.toFunctionPayload(),
    });
    return _challengeFromResponse(response);
  }

  @override
  Future<void> archiveChallenge({required String challengeId}) async {
    await _post('archiveClassChallenge', {'challenge_id': challengeId});
  }

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchLeaderboard({
    required String challengeId,
  }) {
    return _results
        .where('challenge_id', isEqualTo: challengeId)
        .snapshots()
        .map((snapshot) {
          final values = snapshot.docs
              .map(
                (doc) => ClassChallengeLeaderboardEntry.tryFromMap(doc.data()),
              )
              .whereType<ClassChallengeLeaderboardEntry>();
          return rankClassChallengeEntries(values);
        });
  }

  @override
  Stream<List<ClassChallengeLeaderboardEntry>> watchResultsForGroup({
    required String groupId,
  }) => _results.where('group_id', isEqualTo: groupId).snapshots().map(
    (snapshot) => List.unmodifiable(
      snapshot.docs
          .map((doc) => ClassChallengeLeaderboardEntry.tryFromMap(doc.data()))
          .whereType<ClassChallengeLeaderboardEntry>(),
    ),
  );

  @override
  Stream<ClassChallengeParticipant?> watchParticipant({
    required String challengeId,
    required String traineeId,
  }) => _participants
      .doc('${challengeId}__${traineeId}')
      .snapshots()
      .map((doc) => doc.data() == null
          ? null
          : ClassChallengeParticipant.tryFromMap(doc.data()!));

  @override
  Future<ClassChallengeAttempt> reserveAttempt({
    required String challengeId,
    required String requestId,
  }) async {
    final response = await _post('reserveClassChallengeAttempt', {
      'challenge_id': challengeId,
      'request_id': requestId,
    });
    final raw = response['attempt'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final map = Map<String, dynamic>.from(raw);
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
    await _post('abandonClassChallengeAttempt', {
      'challenge_id': challengeId,
      'attempt_id': attemptId,
    });
  }

  @override
  Future<ClassChallengeLeaderboardEntry> completeAttempt({
    required String challengeId,
    required String attemptId,
    required String sessionId,
  }) async {
    final response = await _post('completeClassChallengeAttempt', {
      'challenge_id': challengeId,
      'attempt_id': attemptId,
      'session_id': sessionId,
    });
    final raw = response['best_result'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final parsed = ClassChallengeLeaderboardEntry.tryFromMap(
      Map<String, dynamic>.from(raw),
    );
    if (parsed == null) throw const ClassChallengeException('malformed');
    return parsed;
  }

  ClassChallenge _challengeFromResponse(Map<String, dynamic> response) {
    final raw = response['challenge'];
    if (raw is! Map) throw const ClassChallengeException('malformed');
    final map = Map<String, dynamic>.from(raw);
    final id = map.remove('id');
    final parsed = id is String
        ? ClassChallenge.tryFromMap(map, id: id)
        : null;
    if (parsed == null) throw const ClassChallengeException('malformed');
    return parsed;
  }

  Future<Map<String, dynamic>> _post(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ClassChallengeException('forbidden');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const ClassChallengeException('forbidden');
    }
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(apiBaseUri.resolve(functionName))
          .timeout(requestTimeout);
      request.headers.set('X-Firebase-Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(requestTimeout);
      final body = await utf8.decoder.bind(response).join().timeout(requestTimeout);
      final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      if (response.statusCode != HttpStatus.ok) {
        final code = decoded is Map ? decoded['error']?.toString() : null;
        throw ClassChallengeException(code ?? 'unavailable');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const ClassChallengeException('malformed');
      }
      return decoded;
    } on ClassChallengeException {
      rethrow;
    } on TimeoutException {
      throw const ClassChallengeException('unavailable');
    } on SocketException {
      throw const ClassChallengeException('offline');
    } on FormatException {
      throw const ClassChallengeException('malformed');
    } finally {
      client.close(force: true);
    }
  }
}
