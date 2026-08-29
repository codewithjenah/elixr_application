import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classroomKeys = {
    'assignment_context',
    'teacher_id',
    'group_id',
    'assignment_id',
    'revision_id',
  };

  test('canonical summary payload contains only supported keys', () {
    final payload = PublicProfileSummaryWrite.canonicalMap(
      totalDurationSeconds: 90,
      completedMovementNames: const ['Hand Stall'],
      updatedAt: 'now',
      lastBackfillSessionId: 'sessA',
    );

    expect(payload.keys.toSet(), {
      'total_duration_seconds',
      'completed_movement_names',
      'updated_at',
      'last_backfill_session_id',
    });
    expect(payload['total_duration_seconds'], 90);
    expect(payload['completed_movement_names'], ['Hand Stall']);
    expect(payload['last_backfill_session_id'], 'sessA');
    for (final key in classroomKeys) {
      expect(payload.containsKey(key), isFalse);
    }
  });

  test('unknown legacy fields are not copied forward on rebuild', () {
    final payload = PublicProfileSummaryWrite.rebuildMap(
      totalDurationSeconds: 40,
      completedMovementNames: const ['Hand Stall'],
      updatedAt: 'now',
      existingSummary: {
        'total_duration_seconds': 10,
        'completed_movement_names': ['legacy'],
        'updated_at': 'old',
        'last_backfill_session_id': 'sessKeep',
        'legacy_score_average': 99,
        'assignment_context': {'assignment_id': 'asg1'},
        'teacher_id': 'teacher-1',
        'group_id': 'group-1',
        'assignment_id': 'asg1',
        'revision_id': 'rev1',
      },
    );

    expect(payload.keys.toSet(), {
      'total_duration_seconds',
      'completed_movement_names',
      'updated_at',
      'last_backfill_session_id',
    });
    expect(payload['total_duration_seconds'], 40);
    expect(payload['completed_movement_names'], ['Hand Stall']);
    expect(payload['last_backfill_session_id'], 'sessKeep');
    expect(payload.containsKey('legacy_score_average'), isFalse);
    for (final key in classroomKeys) {
      expect(payload.containsKey(key), isFalse);
    }
  });

  test('invalid last_backfill_session_id is dropped on rebuild', () {
    final payload = PublicProfileSummaryWrite.rebuildMap(
      totalDurationSeconds: 0,
      completedMovementNames: const [],
      updatedAt: 'now',
      existingSummary: {'last_backfill_session_id': '   '},
    );

    expect(payload.containsKey('last_backfill_session_id'), isFalse);
    expect(payload.keys.toSet(), {
      'total_duration_seconds',
      'completed_movement_names',
      'updated_at',
    });
  });

  test('incremental session summary writes canonical current schema', () {
    final payload = PublicProfileSummaryWrite.afterSessionMap(
      existingSummary: {
        'total_duration_seconds': 10,
        'completed_movement_names': ['Normal Grip'],
        'legacy_unknown': true,
        'teacher_id': 'teacher-1',
        'assignment_id': 'asg1',
      },
      sessionDurationSeconds: 30,
      sessionMovementName: 'Hand Stall',
      sessionId: 'sessB',
      updatedAt: 'now',
    );

    expect(payload.keys.toSet(), {
      'total_duration_seconds',
      'completed_movement_names',
      'updated_at',
      'last_backfill_session_id',
    });
    expect(payload['total_duration_seconds'], 40);
    expect(payload['completed_movement_names'], ['Hand Stall', 'Normal Grip']);
    expect(payload['last_backfill_session_id'], 'sessB');
    expect(payload.containsKey('legacy_unknown'), isFalse);
    for (final key in classroomKeys) {
      expect(payload.containsKey(key), isFalse);
    }
  });

  test('normal current-schema summary behavior remains unchanged', () {
    final payload = PublicProfileSummaryWrite.afterSessionMap(
      existingSummary: {
        'total_duration_seconds': 120,
        'completed_movement_names': ['Hand Stall'],
        'updated_at': 'old',
        'last_backfill_session_id': 'sessOld',
      },
      sessionDurationSeconds: 40,
      sessionMovementName: 'Hand Stall',
      sessionId: 'sessNew',
      updatedAt: 'now',
    );

    expect(payload['total_duration_seconds'], 160);
    expect(payload['completed_movement_names'], ['Hand Stall']);
    expect(payload['last_backfill_session_id'], 'sessNew');
  });

  test('legacy movement names are excluded from the completed summary', () {
    final payload = PublicProfileSummaryWrite.afterSessionMap(
      existingSummary: {
        'total_duration_seconds': 10,
        'completed_movement_names': ['Tap', 'Clip', 'Arm Stall', 'Hand Stall'],
      },
      sessionDurationSeconds: 30,
      sessionMovementName: 'Clip',
      sessionId: 'sessLegacy',
      updatedAt: 'now',
    );

    expect(payload['total_duration_seconds'], 40);
    expect(payload['completed_movement_names'], ['Hand Stall']);
  });
}
