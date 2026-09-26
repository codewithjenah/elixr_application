import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/profile_visit.dart';
import '../models/public_profile.dart';
import 'public_profile_repository.dart';

/// Persistence for profile visitor records.
class ProfileVisitRepository {
  ProfileVisitRepository({
    SupabaseClient? client,
    PublicProfileRepository? publicProfileRepository,
  }) : _clientOverride = client,
       _publicProfileRepository =
           publicProfileRepository ?? PublicProfileRepository();

  final SupabaseClient? _clientOverride;
  final PublicProfileRepository _publicProfileRepository;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// Records or updates a visit. Self-visits are ignored. The server derives
  /// the viewer from the session and stamps both timestamps.
  Future<void> upsertVisit({
    required String profileOwnerId,
    required String viewerId,
  }) async {
    if (profileOwnerId.isEmpty || viewerId.isEmpty) return;
    if (profileOwnerId == viewerId) return;
    if (_client.auth.currentUser?.id != viewerId) return;

    await _client.rpc<dynamic>(
      'record_profile_visit',
      params: {'p_profile_owner_id': profileOwnerId},
    );
  }

  /// Fetches recent visitors for the profile owner, newest first.
  Future<List<ProfileVisitDisplay>> fetchVisitors({
    required String profileOwnerId,
    int limit = 20,
  }) async {
    final rows = await _client
        .from('profile_visits')
        .select()
        .eq('profile_owner_id', profileOwnerId)
        .order('last_viewed_at', ascending: false)
        .limit(limit);

    final displays = <ProfileVisitDisplay>[];
    for (final row in rows) {
      final visit = ProfileVisit.tryFromMap(compactRow(row));
      if (visit == null) continue;

      PublicProfile? viewerProfile;
      try {
        viewerProfile = await _publicProfileRepository.getProfileRoot(
          visit.viewerId,
        );
      } catch (error, stackTrace) {
        _logError('fetchVisitors.hydrate', error, stackTrace);
      }

      displays.add(
        ProfileVisitDisplay(
          visit: visit,
          displayName: viewerProfile?.displayName ?? 'Player',
          profilePictureUrl: viewerProfile?.profilePictureUrl,
        ),
      );
    }
    return displays;
  }

  static void _logError(String operation, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('ProfileVisit error: op=$operation error=$error');
    debugPrint('$stackTrace');
  }
}
