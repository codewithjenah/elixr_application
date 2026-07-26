import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feedback.dart';
import '../models/session.dart';
import '../models/user.dart';

abstract final class FirestoreCollections {
  static const users = 'users';
  static const sessions = 'sessions';
  static const feedbacks = 'feedbacks';
}

class FirestoreHelper {
  FirestoreHelper._({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final FirestoreHelper instance = FirestoreHelper._();

  final FirebaseFirestore _firestore;

  static String? _readCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is String) return value;
    return null;
  }

  Map<String, dynamic> _userFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'full_name': data['full_name'],
      'email': data['email'],
      'role': data['role'],
      'created_at': _readCreatedAt(data['created_at']),
      'profile_picture_path': data['profile_picture_path'],
    };
  }

  Map<String, dynamic> _sessionFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'user_id': data['user_id'],
      'movement_name': data['movement_name'],
      'difficulty': data['difficulty'],
      'score': data['score'],
      'duration_seconds': data['duration_seconds'],
      'created_at': _readCreatedAt(data['created_at']),
    };
  }

  Map<String, dynamic> _feedbackFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'session_id': data['session_id'],
      'message': data['message'],
      'feedback_type': data['feedback_type'],
      'created_at': _readCreatedAt(data['created_at']),
    };
  }

  Future<void> upsertUserProfile(User user) async {
    if (user.id == null) {
      throw ArgumentError('User id is required');
    }
    await _firestore.collection(FirestoreCollections.users).doc(user.id).set({
      'full_name': user.fullName,
      'email': user.email,
      'role': user.role,
      'created_at': FieldValue.serverTimestamp(),
      if (user.profilePicturePath != null)
        'profile_picture_path': user.profilePicturePath,
    }, SetOptions(merge: true));
  }

  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .update(fields);
  }

  Future<User?> getUserById(String id) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    return User.fromMap(_userFromDoc(doc));
  }

  Future<String> insertSession(Session session) async {
    final doc = _firestore.collection(FirestoreCollections.sessions).doc();
    await doc.set({
      'user_id': session.userId,
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'score': session.score,
      'duration_seconds': session.durationSeconds,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<List<Session>> getSessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => Session.fromMap(_sessionFromDoc(doc)))
        .toList();
  }

  Future<String> insertFeedback(Feedback feedback) async {
    final doc = _firestore.collection(FirestoreCollections.feedbacks).doc();
    await doc.set({
      'session_id': feedback.sessionId,
      'message': feedback.message,
      'feedback_type': feedback.feedbackType,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> insertFeedbacks(List<Feedback> feedbacks) async {
    if (feedbacks.isEmpty) return;
    final batch = _firestore.batch();
    for (final feedback in feedbacks) {
      final doc = _firestore.collection(FirestoreCollections.feedbacks).doc();
      batch.set(doc, {
        'session_id': feedback.sessionId,
        'message': feedback.message,
        'feedback_type': feedback.feedbackType,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<List<Feedback>> getFeedbacksForSession(String sessionId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.feedbacks)
        .where('session_id', isEqualTo: sessionId)
        .orderBy('created_at')
        .get();
    return snapshot.docs
        .map((doc) => Feedback.fromMap(_feedbackFromDoc(doc)))
        .toList();
  }

  Future<int> countSessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  Future<double?> averageScoreForUser(String userId) async {
    final sessions = await _sessionsForUser(userId);
    if (sessions.isEmpty) return null;
    final total = sessions.fold<int>(
      0,
      (running, session) => running + session.score,
    );
    return total / sessions.length;
  }

  Future<int?> bestScoreForUser(String userId) async {
    final sessions = await _sessionsForUser(userId);
    if (sessions.isEmpty) return null;
    return sessions
        .map((session) => session.score)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<Map<String, int>> sessionCountByMovement(String userId) async {
    final sessions = await _sessionsForUser(userId);
    final counts = <String, int>{};
    for (final session in sessions) {
      counts.update(
        session.movementName,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  Future<List<Session>> _sessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .get();
    return snapshot.docs
        .map((doc) => Session.fromMap(_sessionFromDoc(doc)))
        .toList();
  }
}
