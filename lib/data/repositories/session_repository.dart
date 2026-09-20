import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../database/firestore_helper.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/classroom_exceptions.dart';
import '../models/feedback.dart';
import '../models/session.dart';
import 'firebase_classroom_assignment_repository.dart';

class SessionRepository {
  SessionRepository({
    FirestoreHelper? db,
    FirebaseAuth? auth,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
  }) : _dbOverride = db,
       _authOverride = auth,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_ASSIGNMENTS_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirestoreHelper? _dbOverride;
  final FirebaseAuth? _authOverride;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  FirestoreHelper get _db => _dbOverride ?? FirestoreHelper.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String allocateSessionId() => _db.allocateSessionId();

  Future<void> saveSessionWithFeedbacks({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
    AssignmentAttempt? officialAssignmentPointer,
  }) async {
    if (officialAssignmentPointer != null) {
      final expectedId = assignmentAttemptIdForOfficialSession(sessionId);
      if (officialAssignmentPointer.id != expectedId ||
          officialAssignmentPointer.sourceSessionId != sessionId ||
          session.assignmentContext == null) {
        throw ArgumentError('Invalid official assignment session identity.');
      }
      await _completeOfficialAssignmentSession(
        sessionId: sessionId,
        session: session,
        feedbacks: feedbacks,
      );
      return;
    }
    await _db.saveSessionWithFeedbacks(
      sessionId: sessionId,
      session: session,
      feedbacks: feedbacks,
      officialAssignmentPointer: officialAssignmentPointer,
    );
  }

  Future<void> _completeOfficialAssignmentSession({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ClassroomException(ClassroomError.forbidden);
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final sessionPayload = session.toMap()
      ..remove('id')
      ..remove('created_at')
      ..remove('user_id')
      ..remove('challenge_context');
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(apiBaseUri.resolve('completeOfficialAssignmentSession'))
          .timeout(const Duration(seconds: 30));
      request.headers.set('X-Firebase-Authorization', 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'session_id': sessionId,
          'session': sessionPayload,
          'feedbacks': [
            for (final feedback in feedbacks)
              {
                'message': feedback.message,
                'feedback_type': feedback.feedbackType,
              },
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 30));
      Object? decoded;
      try {
        decoded = responseBody.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(responseBody);
      } on FormatException {
        if (response.statusCode == HttpStatus.ok) rethrow;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw classroomFunctionFailure(
          statusCode: response.statusCode,
          responseBody: decoded,
        );
      }
    } on ClassroomException {
      rethrow;
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FormatException {
      throw const ClassroomException(ClassroomError.malformed);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> saveSession(Session session) {
    return _db.insertSession(session);
  }

  Future<void> saveFeedbacks(List<Feedback> feedbacks) {
    return _db.insertFeedbacks(feedbacks);
  }

  Future<List<Session>> getSessionsForUser(String userId) {
    return _db.getSessionsForUser(userId);
  }

  Future<List<Feedback>> getFeedbacksForSession(String sessionId) {
    return _db.getFeedbacksForSession(sessionId);
  }
}
