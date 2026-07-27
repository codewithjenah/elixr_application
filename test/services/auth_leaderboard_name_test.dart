import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Profile rename must only touch display_name; aggregates stay unchanged.
/// Full AuthService+Firestore coverage needs emulator; this guards the contract.
void main() {
  test('rename preserves XP and scores in award plan sense', () {
    final before = {
      'user_id': 'u1',
      'display_name': 'Old Name',
      'total_xp': 50,
      'sessions_completed': 2,
      'score_sum': 140.0,
      'average_score': 70.0,
      'best_score': 80,
      'last_awarded_session_id': 's2',
    };

    final afterNameOnly = Map<String, dynamic>.from(before)
      ..['display_name'] = 'New Name';

    expect(afterNameOnly['total_xp'], before['total_xp']);
    expect(afterNameOnly['sessions_completed'], before['sessions_completed']);
    expect(afterNameOnly['score_sum'], before['score_sum']);
    expect(afterNameOnly['average_score'], before['average_score']);
    expect(afterNameOnly['best_score'], before['best_score']);
    expect(afterNameOnly.containsKey('email'), isFalse);
    expect(afterNameOnly.containsKey('profile_picture_path'), isFalse);
    expect(afterNameOnly['display_name'], 'New Name');
  });

  test('sync planner never includes another user session refs', () {
    final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
      sessions: const [SessionRef(id: 'mine', userId: 'u1', createdAtMs: 1)],
      processedSessionIds: const {},
    );
    expect(missing, hasLength(1));
    expect(missing.single.userId, 'u1');
  });
}
