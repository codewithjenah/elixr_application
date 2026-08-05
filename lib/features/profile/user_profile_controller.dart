import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/achievement.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/profile_visit.dart';
import '../../data/models/public_profile.dart';
import '../../data/models/public_profile_summary.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/profile_visit_repository.dart';
import '../../data/repositories/public_profile_repository.dart';

enum ProfileLoadState { loading, loaded, notFound, error }

enum ProfileVisitorsState { loading, loaded, empty, error }

class UserProfileController extends ChangeNotifier {
  UserProfileController({
    required String userId,
    required String? currentUserId,
    LeaderboardEntry? initialEntry,
    int? initialRank,
    LeaderboardRepository? leaderboardRepository,
    PublicProfileRepository? publicProfileRepository,
    ProfileVisitRepository? profileVisitRepository,
  }) : _userId = userId,
       _currentUserId = currentUserId,
       _leaderboardRepository =
           leaderboardRepository ?? LeaderboardRepository(),
       _publicProfileRepository =
           publicProfileRepository ?? PublicProfileRepository(),
       _profileVisitRepository =
           profileVisitRepository ?? ProfileVisitRepository() {
    _leaderboardEntry = initialEntry;
    _rank = initialRank;
  }

  final String _userId;
  final String? _currentUserId;
  final LeaderboardRepository _leaderboardRepository;
  final PublicProfileRepository _publicProfileRepository;
  final ProfileVisitRepository _profileVisitRepository;

  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;
  StreamSubscription<PublicProfile?>? _profileRootSub;
  bool _disposed = false;
  bool _visitRecorded = false;
  bool _backfillStarted = false;

  ProfileLoadState loadState = ProfileLoadState.loading;
  Object? loadError;
  PublicProfile? profileRoot;
  LeaderboardEntry? _leaderboardEntry;
  int? _rank;
  PublicProfileSummary? summary;
  List<AchievementDefinition> claimedAchievements = const [];
  ProfileVisitorsState visitorsState = ProfileVisitorsState.loading;
  List<ProfileVisitDisplay> visitors = const [];

  String get userId => _userId;
  bool get isSelf {
    final uid = _currentUserId;
    return uid != null && uid.isNotEmpty && _userId == uid;
  }

  bool get canViewDetails => isSelf || (profileRoot?.isPublic ?? false);
  LeaderboardEntry? get leaderboardEntry => _leaderboardEntry;
  int? get rank => _rank;

  Future<void> initialize({
    required String displayName,
    String? profilePictureUrl,
  }) async {
    _leaderboardSub = _leaderboardRepository.watchPlayer(_userId).listen((
      entry,
    ) {
      if (_disposed) return;
      _leaderboardEntry = entry;
      _safeNotify();
    });

    _profileRootSub = _publicProfileRepository
        .watchProfileRoot(_userId)
        .listen(
          (profile) async {
            if (_disposed) return;
            profileRoot = profile;
            if (profile == null && loadState == ProfileLoadState.loading) {
              // Wait for first emission before deciding not-found.
            }
            await _reloadProtectedContent();
            _safeNotify();
          },
          onError: (Object error) {
            if (_disposed) return;
            loadState = ProfileLoadState.error;
            loadError = error;
            _safeNotify();
          },
        );

    if (_rank == null) {
      try {
        _rank = await _leaderboardRepository.computeRankForUser(_userId);
      } catch (_) {
        // Rank is optional; profile can still render.
      }
    }

    if (!_visitRecorded && !isSelf) {
      final viewerId = _currentUserId;
      if (viewerId != null && viewerId.isNotEmpty) {
        _visitRecorded = true;
        unawaited(
          _profileVisitRepository
              .upsertVisit(profileOwnerId: _userId, viewerId: viewerId)
              .catchError((_) {}),
        );
      }
    }

    if (isSelf && !_backfillStarted) {
      _backfillStarted = true;
      unawaited(
        _publicProfileRepository
            .ensurePublicProfile(
              userId: _userId,
              displayName: displayName,
              profilePictureUrl: profilePictureUrl,
            )
            .catchError((_) {}),
      );
    }

    await _reloadProtectedContent();
    if (!_disposed) {
      loadState = profileRoot == null && _leaderboardEntry == null
          ? ProfileLoadState.notFound
          : ProfileLoadState.loaded;
      _safeNotify();
    }
  }

  Future<void> _reloadProtectedContent() async {
    if (canViewDetails) {
      try {
        summary = await _publicProfileRepository.getSummary(_userId);

        final claimedIds = await _publicProfileRepository
            .fetchClaimedAchievementIds(_userId);
        claimedAchievements = achievementCatalog
            .where((def) => claimedIds.contains(def.id))
            .toList(growable: false);
      } catch (error) {
        if (!_disposed) {
          loadState = ProfileLoadState.error;
          loadError = error;
        }
      }
    } else {
      summary = null;
      claimedAchievements = const [];
    }

    if (isSelf) {
      await _loadVisitors();
    }
  }

  Future<void> _loadVisitors() async {
    visitorsState = ProfileVisitorsState.loading;
    _safeNotify();
    try {
      final rows = await _profileVisitRepository.fetchVisitors(
        profileOwnerId: _userId,
      );
      if (_disposed) return;
      visitors = rows;
      visitorsState = rows.isEmpty
          ? ProfileVisitorsState.empty
          : ProfileVisitorsState.loaded;
    } catch (_) {
      if (_disposed) return;
      visitorsState = ProfileVisitorsState.error;
    }
  }

  Future<void> retry() async {
    loadState = ProfileLoadState.loading;
    loadError = null;
    _safeNotify();
    await _reloadProtectedContent();
    if (!_disposed) {
      loadState = ProfileLoadState.loaded;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _leaderboardSub?.cancel();
    _profileRootSub?.cancel();
    super.dispose();
  }
}
