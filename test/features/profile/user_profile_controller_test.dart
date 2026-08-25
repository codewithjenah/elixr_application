import 'dart:async';

import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/data/models/profile_visit.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/public_profile_summary.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/data/repositories/profile_visit_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/profile/user_profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<PublicProfile?> profileRoot;
  late StreamController<LeaderboardEntry?> leaderboard;
  late UserProfileController controller;

  setUp(() {
    profileRoot = StreamController<PublicProfile?>.broadcast();
    leaderboard = StreamController<LeaderboardEntry?>.broadcast();
  });

  tearDown(() async {
    controller.dispose();
    await profileRoot.close();
    await leaderboard.close();
  });

  UserProfileController buildController({
    String userId = 'teacher-b',
    String currentUserId = 'teacher-a',
    LeaderboardEntry? initialEntry,
    String? initialDisplayName,
    String? initialProfilePictureUrl,
  }) {
    return UserProfileController(
      userId: userId,
      currentUserId: currentUserId,
      initialEntry: initialEntry,
      initialDisplayName: initialDisplayName,
      initialProfilePictureUrl: initialProfilePictureUrl,
      leaderboardRepository: _DelayedLeaderboardRepository(leaderboard.stream),
      publicProfileRepository: _DelayedPublicProfileRepository(
        profileRoot.stream,
      ),
      profileVisitRepository: _NoopProfileVisitRepository(),
    );
  }

  Future<void> waitFor(
    UserProfileController target,
    bool Function() predicate,
  ) async {
    if (predicate()) return;
    final done = Completer<void>();
    void listener() {
      if (predicate() && !done.isCompleted) done.complete();
    }

    target.addListener(listener);
    addTearDown(() => target.removeListener(listener));
    await done.future.timeout(const Duration(seconds: 2));
  }

  test(
    'teacher without leaderboard stays loading until the public profile snapshot',
    () async {
      controller = buildController();
      unawaited(controller.initialize(displayName: 'Teacher A'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.loadState, ProfileLoadState.loading);

      leaderboard.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(controller.loadState, ProfileLoadState.loading);

      profileRoot.add(
        const PublicProfile(
          userId: 'teacher-b',
          displayName: 'Zoe Faculty',
          visibility: ProfileVisibility.public,
        ),
      );
      await waitFor(
        controller,
        () => controller.loadState == ProfileLoadState.loaded,
      );

      expect(controller.profileRoot?.displayName, 'Zoe Faculty');
      expect(controller.profileRoot?.isPublic, isTrue);
    },
  );

  test(
    'recovers to loaded when the public profile arrives after initialize',
    () async {
      controller = buildController();
      await controller.initialize(displayName: 'Teacher A');

      expect(controller.loadState, isNot(ProfileLoadState.notFound));

      leaderboard.add(null);
      profileRoot.add(
        const PublicProfile(
          userId: 'teacher-b',
          displayName: 'Ada Teacher',
          visibility: ProfileVisibility.private,
        ),
      );
      await waitFor(
        controller,
        () => controller.loadState == ProfileLoadState.loaded,
      );

      expect(controller.profileRoot?.displayName, 'Ada Teacher');
      expect(controller.canViewDetails, isFalse);
    },
  );

  test(
    'marks notFound only after both snapshots are empty and no fallback name',
    () async {
      controller = buildController();
      unawaited(controller.initialize(displayName: 'Teacher A'));
      leaderboard.add(null);
      profileRoot.add(null);
      await waitFor(
        controller,
        () => controller.loadState == ProfileLoadState.notFound,
      );
    },
  );

  test(
    'uses faculty directory identity when teacher has no public profile or leaderboard',
    () async {
      controller = buildController(
        initialDisplayName: 'Zoe Faculty',
        initialProfilePictureUrl: 'https://example.com/zoe.png',
      );
      unawaited(controller.initialize(displayName: 'Teacher A'));
      leaderboard.add(null);
      profileRoot.add(null);
      await waitFor(
        controller,
        () => controller.loadState == ProfileLoadState.loaded,
      );

      expect(controller.profileRoot?.displayName, 'Zoe Faculty');
      expect(
        controller.profileRoot?.profilePictureUrl,
        'https://example.com/zoe.png',
      );
      expect(controller.profileRoot?.visibility, ProfileVisibility.private);
      expect(controller.canViewDetails, isFalse);
    },
  );

  test(
    'firestore public profile wins over faculty directory fallback identity',
    () async {
      controller = buildController(initialDisplayName: 'From Faculties List');
      unawaited(controller.initialize(displayName: 'Teacher A'));
      leaderboard.add(null);
      profileRoot.add(
        const PublicProfile(
          userId: 'teacher-b',
          displayName: 'From Public Profile',
          visibility: ProfileVisibility.public,
        ),
      );
      await waitFor(
        controller,
        () =>
            controller.loadState == ProfileLoadState.loaded &&
            controller.profileRoot?.displayName == 'From Public Profile',
      );

      expect(controller.profileRoot?.isPublic, isTrue);
    },
  );
}

class _DelayedLeaderboardRepository extends LeaderboardRepository {
  _DelayedLeaderboardRepository(this._watch);

  final Stream<LeaderboardEntry?> _watch;

  @override
  Stream<LeaderboardEntry?> watchPlayer(String userId) => _watch;

  @override
  Future<int?> computeRankForUser(
    String userId, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    DateTime? nowUtc,
  }) async => null;
}

class _DelayedPublicProfileRepository extends PublicProfileRepository {
  _DelayedPublicProfileRepository(this._watch);

  final Stream<PublicProfile?> _watch;

  @override
  Stream<PublicProfile?> watchProfileRoot(String userId) => _watch;

  @override
  Future<void> ensurePublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {}

  @override
  Future<PublicProfileSummary?> getSummary(String userId) async => null;

  @override
  Future<List<String>> fetchClaimedAchievementIds(String userId) async =>
      const [];
}

class _NoopProfileVisitRepository extends ProfileVisitRepository {
  @override
  Future<void> upsertVisit({
    required String profileOwnerId,
    required String viewerId,
  }) async {}

  @override
  Future<List<ProfileVisitDisplay>> fetchVisitors({
    required String profileOwnerId,
    int limit = 20,
  }) async => const [];
}
