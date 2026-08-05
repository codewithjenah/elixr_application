import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../database/firestore_helper.dart';
import '../models/profile_visit.dart';
import '../models/public_profile.dart';
import 'public_profile_repository.dart';

/// Persistence for profile visitor records.
class ProfileVisitRepository {
  ProfileVisitRepository({
    FirebaseFirestore? firestore,
    PublicProfileRepository? publicProfileRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _publicProfileRepository =
           publicProfileRepository ?? PublicProfileRepository();

  final FirebaseFirestore _firestore;
  final PublicProfileRepository _publicProfileRepository;

  DocumentReference<Map<String, dynamic>> _visitRef(
    String profileOwnerId,
    String viewerId,
  ) => _firestore
      .collection(FirestoreCollections.profileVisits)
      .doc(profileOwnerId)
      .collection('visitors')
      .doc(viewerId);

  /// Records or updates a visit. Self-visits are ignored.
  Future<void> upsertVisit({
    required String profileOwnerId,
    required String viewerId,
  }) async {
    if (profileOwnerId.isEmpty || viewerId.isEmpty) return;
    if (profileOwnerId == viewerId) return;

    final ref = _visitRef(profileOwnerId, viewerId);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'profile_owner_id': profileOwnerId,
        'viewer_id': viewerId,
        'first_viewed_at': FieldValue.serverTimestamp(),
        'last_viewed_at': FieldValue.serverTimestamp(),
      });
      return;
    }

    await ref.update({
      'profile_owner_id': profileOwnerId,
      'viewer_id': viewerId,
      'last_viewed_at': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches recent visitors for the profile owner, newest first.
  Future<List<ProfileVisitDisplay>> fetchVisitors({
    required String profileOwnerId,
    int limit = 20,
  }) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.profileVisits)
        .doc(profileOwnerId)
        .collection('visitors')
        .orderBy('last_viewed_at', descending: true)
        .limit(limit)
        .get();

    final displays = <ProfileVisitDisplay>[];
    for (final doc in snapshot.docs) {
      final visit = ProfileVisit.tryFromMap(doc.data(), id: doc.id);
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
