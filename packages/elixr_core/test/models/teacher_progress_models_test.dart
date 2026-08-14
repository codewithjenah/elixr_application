import 'package:elixr_core/models/public_profile_session.dart';
import 'package:elixr_core/models/public_profile_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base({int version = 1}) => {
    'session_id': 's1',
    'user_id': 'trainee',
    'movement_name': 'Hand Stall',
    'difficulty': 'Easy',
    'duration_seconds': 60,
    'prop_type': 'bottle',
    'created_at': '2026-08-14T00:00:00Z',
    'assessment_version': version,
    if (version == 1) 'score': 80,
  };

  test('legacy sessions accept bounded integer scores only', () {
    expect(PublicProfileSession.tryFromMap(base()..['score'] = 0), isNotNull);
    expect(PublicProfileSession.tryFromMap(base()..['score'] = 100), isNotNull);
    for (final value in [-1, 101, 80.5, '80']) {
      expect(
        PublicProfileSession.tryFromMap(base()..['score'] = value),
        isNull,
      );
    }
    expect(
      PublicProfileSession.tryFromMap(base()..['duration_seconds'] = -1),
      isNull,
    );
    expect(
      PublicProfileSession.tryFromMap(base()..['duration_seconds'] = 1.5),
      isNull,
    );
    expect(PublicProfileSession.tryFromMap(base()..['rubric'] = {}), isNull);
  });

  test('explicit V2 requires a valid internally consistent rubric', () {
    final v2 = base(version: 2)
      ..addAll({
        'rubric': {
          'technique': 3,
          'stability': 2,
          'completion': 1,
          'prop_positioning': 0,
        },
        'rubric_total': 6,
        'performance_level': 'developing',
      });
    final parsed = PublicProfileSession.tryFromMap(v2);
    expect(parsed?.rubric?.total, 6);
    expect(parsed?.legacyScore, isNull);
    expect(PublicProfileSession.tryFromMap(v2..['rubric_total'] = 7), isNull);
    expect(
      PublicProfileSession.tryFromMap(base(version: 2)..['score'] = 80),
      isNull,
    );
  });

  test('summary safely normalizes malformed values and movement names', () {
    final parsed = PublicProfileSummary.tryFromMap({
      'total_duration_seconds': -2,
      'completed_movement_names': [
        ' Hand Stall ',
        '',
        2,
        'Hand Stall',
        'Claw Grip',
      ],
      'updated_at': null,
    })!;
    expect(parsed.totalDurationSeconds, 0);
    expect(parsed.completedMovementNames, ['Hand Stall', 'Claw Grip']);
    expect(
      () => parsed.completedMovementNames.add('x'),
      throwsUnsupportedError,
    );
    expect(
      PublicProfileSummary.tryFromMap({
        'total_duration_seconds': 2.5,
      })!.totalDurationSeconds,
      0,
    );
  });
}
