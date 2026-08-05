import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PublicProfileRepository.clearAchievementSyncInFlightForTest);

  group('ClaimedAchievementProjectionPlanner', () {
    test('legacy claim without projection creates a draft', () {
      final claimedAt = Timestamp.fromDate(DateTime.utc(2024, 1, 2));
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {
            'user_id': 'u1',
            'achievement_id': 'first_steps',
            'claimed_at': claimedAt,
          },
        ],
        existingProjectedIds: const {},
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.achievementId, 'first_steps');
      expect(drafts.single.claimedAt, claimedAt);
    });

    test('running sync planning twice is idempotent when projected', () {
      final claims = [
        {'user_id': 'u1', 'achievement_id': 'first_steps'},
      ];
      final first = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: claims,
        existingProjectedIds: const {},
      );
      expect(first, hasLength(1));

      final second = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: claims,
        existingProjectedIds: {'first_steps'},
      );
      expect(second, isEmpty);
    });

    test('existing projections are not needlessly rewritten', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {'user_id': 'u1', 'achievement_id': 'first_steps'},
          {'user_id': 'u1', 'achievement_id': 'sharp_pour'},
        ],
        existingProjectedIds: {'first_steps'},
      );

      expect(drafts.map((d) => d.achievementId), ['sharp_pour']);
    });

    test('multiple valid claims are projected', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {'user_id': 'u1', 'achievement_id': 'first_steps'},
          {'user_id': 'u1', 'achievement_id': 'sharp_pour'},
        ],
        existingProjectedIds: const {},
      );

      expect(drafts.map((d) => d.achievementId).toSet(), {
        'first_steps',
        'sharp_pour',
      });
    });

    test('unknown achievement IDs are skipped', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {'user_id': 'u1', 'achievement_id': 'not_a_real_achievement'},
          {'user_id': 'u1', 'achievement_id': 'first_steps'},
        ],
        existingProjectedIds: const {},
      );

      expect(drafts.map((d) => d.achievementId), ['first_steps']);
    });

    test('malformed claims are skipped safely', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {'user_id': 'u1', 'achievement_id': 42},
          {'user_id': 'u1', 'achievement_id': ''},
          {'user_id': 'u1', 'achievement_id': '   '},
          {'user_id': 'u1'},
          {'user_id': 'u1', 'achievement_id': 'first_steps'},
        ],
        existingProjectedIds: const {},
      );

      expect(drafts.map((d) => d.achievementId), ['first_steps']);
    });

    test('a user with no claims produces no projections', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: const [],
        existingProjectedIds: const {},
      );
      expect(drafts, isEmpty);
    });

    test('invalid claimed_at falls back to null for server timestamp', () {
      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: [
          {
            'user_id': 'u1',
            'achievement_id': 'first_steps',
            'claimed_at': 'not-a-timestamp',
          },
        ],
        existingProjectedIds: const {},
      );

      expect(drafts.single.claimedAt, isNull);
    });
  });

  group('achievement sync in-flight guard', () {
    test(
      'concurrent synchronization for the same user reuses one future',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        var runs = 0;

        Future<void> action() async {
          runs++;
          started.complete();
          await release.future;
        }

        final first = PublicProfileRepository.runWithAchievementSyncGuard(
          'u1',
          action,
        );
        final second = PublicProfileRepository.runWithAchievementSyncGuard(
          'u1',
          action,
        );

        await started.future;
        expect(identical(first, second), isTrue);
        expect(runs, 1);

        release.complete();
        await Future.wait([first, second]);
        expect(runs, 1);
      },
    );

    test('different users are not blocked by each other', () async {
      final release = Completer<void>();
      var runs = 0;

      Future<void> action() async {
        runs++;
        await release.future;
      }

      final first = PublicProfileRepository.runWithAchievementSyncGuard(
        'u1',
        action,
      );
      final second = PublicProfileRepository.runWithAchievementSyncGuard(
        'u2',
        action,
      );

      expect(identical(first, second), isFalse);
      expect(runs, 2);

      release.complete();
      await Future.wait([first, second]);
    });
  });

  group('ensurePublicProfile achievement sync reuse', () {
    test('ensure implementation delegates to focused sync helper', () {
      final source = File(
        'lib/data/repositories/public_profile_repository.dart',
      ).readAsStringSync();
      expect(source.contains('_syncClaimedAchievementProjectionsImpl'), isTrue);
      expect(
        source.contains(
          'await projectAchievement(userId: userId, achievementId: achievementId)',
        ),
        isFalse,
      );
    });
  });

  group('new claim immediate projection contract', () {
    test('achievement repository still projects immediately after claim', () {
      final source = File(
        'lib/data/repositories/achievement_repository.dart',
      ).readAsStringSync();
      expect(source.contains('projectAchievement('), isTrue);
      expect(source.contains('syncClaimedAchievementProjections('), isFalse);
    });
  });
}
