import '../models/class_challenge.dart';

class ClassChallengeException implements Exception {
  const ClassChallengeException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message ?? code;
}

abstract class ClassChallengeRepository {
  Stream<List<ClassChallenge>> watchChallengesForGroup({
    required String groupId,
  });

  Future<ClassChallenge?> getChallenge({required String challengeId});

  Future<ClassChallenge> createChallenge({
    required ClassChallenge challenge,
  });

  Future<ClassChallenge> updateChallenge({
    required ClassChallenge challenge,
  });

  Future<void> archiveChallenge({required String challengeId});

  Stream<List<ClassChallengeLeaderboardEntry>> watchLeaderboard({
    required String challengeId,
  });

  Stream<List<ClassChallengeLeaderboardEntry>> watchResultsForGroup({
    required String groupId,
  });

  Stream<ClassChallengeParticipant?> watchParticipant({
    required String challengeId,
    required String traineeId,
  });

  Future<ClassChallengeAttempt> reserveAttempt({
    required String challengeId,
    required String requestId,
  });

  Future<void> abandonAttempt({
    required String challengeId,
    required String attemptId,
  });

  Future<ClassChallengeLeaderboardEntry> completeAttempt({
    required String challengeId,
    required String attemptId,
    required String sessionId,
  });
}
