import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import '../database/session_database.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/classroom_exceptions.dart';
import '../models/feedback.dart';
import '../models/session.dart';
import 'supabase_classroom_assignment_repository.dart';

class SessionRepository {
  SessionRepository({SessionDatabase? db, SupabaseClient? client})
    : _dbOverride = db,
      _clientOverride = client;

  final SessionDatabase? _dbOverride;
  final SupabaseClient? _clientOverride;
  SessionDatabase get _db => _dbOverride ?? SessionDatabase.instance;
  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

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
    );
  }

  /// The session, its feedback, the official assignment pointer and the
  /// attempt-limit ledger commit in one server transaction.
  Future<void> _completeOfficialAssignmentSession({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
  }) async {
    final sessionPayload = SessionDatabase.sessionPayload(session)
      ..remove('challenge_context');
    try {
      await _client
          .rpc<dynamic>(
            'complete_official_assignment_session',
            params: {
              'p_session_id': sessionId,
              'p_session': sessionPayload,
              'p_feedbacks': [
                for (final feedback in feedbacks)
                  {
                    'message': feedback.message,
                    'feedback_type': feedback.feedbackType,
                  },
              ],
            },
          )
          .timeout(const Duration(seconds: 30));
    } on PostgrestException catch (error) {
      throw classroomRpcFailure(error);
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } catch (error) {
      if (isBackendUnavailableError(error)) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      rethrow;
    }
  }

  Future<List<Session>> getSessionsForUser(String userId) {
    return _db.getSessionsForUser(userId);
  }

  Future<List<Feedback>> getFeedbacksForSession(String sessionId) {
    return _db.getFeedbacksForSession(sessionId);
  }
}
