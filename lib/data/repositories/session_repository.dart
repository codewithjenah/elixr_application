import '../database/firestore_helper.dart';
import '../models/feedback.dart';
import '../models/session.dart';

class SessionRepository {
  SessionRepository({FirestoreHelper? db})
    : _db = db ?? FirestoreHelper.instance;

  final FirestoreHelper _db;

  String allocateSessionId() => _db.allocateSessionId();

  Future<void> saveSessionWithFeedbacks({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
  }) {
    return _db.saveSessionWithFeedbacks(
      sessionId: sessionId,
      session: session,
      feedbacks: feedbacks,
    );
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
