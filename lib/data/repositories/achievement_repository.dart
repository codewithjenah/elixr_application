import 'package:elixr_core/database/supabase_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/achievement.dart';
import '../models/achievement_claim.dart';
import '../models/leaderboard_entry.dart';
import '../models/profile_border.dart';
import '../models/session.dart';
import '../models/user_cosmetics.dart';

/// Persistence for claimable achievements and equippable profile borders.
///
/// CAPSTONE SECURITY NOTE: [claimAchievement]'s pre-claim completion check is
/// defense-in-depth / UX only. A modified client can call the claim function
/// directly. The database enforces fixed reward mappings, ownership, atomic
/// claim↔cosmetics linkage, idempotency, and equip-only-if-unlocked — it does
/// **not** independently verify that an achievement was completed. Because
/// Phase 2 rewards are cosmetic-only (no XP), modified-client impact is
/// limited to the attacker's own cosmetics.
class AchievementRepository {
  AchievementRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// Live set of claimed achievement ids for [userId].
  Stream<Set<String>> watchClaimedAchievementIds(String userId) {
    return _client
        .from('achievement_claims')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows
              .map((row) => row['achievement_id'])
              .whereType<String>()
              .toSet(),
        );
  }

  /// Watches the caller's `user_cosmetics` row.
  Stream<UserCosmetics?> watchUserCosmetics(String userId) {
    return _client
        .from('user_cosmetics')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : UserCosmetics.tryFromMap(compactRow(rows.first), id: userId),
        );
  }

  /// Claims [achievementId] once and unlocks its reward border.
  ///
  /// Never writes XP or leaderboard aggregates. The claim, cosmetics update
  /// and public achievement projection commit in one server transaction.
  Future<AchievementClaimResult> claimAchievement({
    required String userId,
    required String achievementId,
    required List<Session> sessions,
    required LeaderboardEntry? leaderboardEntry,
  }) async {
    final definition = achievementById(achievementId);
    if (definition == null) {
      return const AchievementClaimResult.invalidAchievement();
    }

    // Defense-in-depth / UX only — see class doc comment.
    final progress = definition.evaluator(sessions, leaderboardEntry);
    if (!progress.completed) {
      return const AchievementClaimResult.notCompleted();
    }
    _requireUser(userId);

    final response = await rpcMap(_client, 'claim_achievement', {
      'p_achievement_id': achievementId,
    });
    return switch (response['status']) {
      'claimed' => AchievementClaimResult.claimed(
        response['reward_border_id'] as String,
      ),
      'already_claimed' => const AchievementClaimResult.alreadyClaimed(),
      'invalid_achievement' =>
        const AchievementClaimResult.invalidAchievement(),
      _ => throw const FormatException('Malformed achievement claim result.'),
    };
  }

  /// Equips [borderId] on the caller's leaderboard `equipped_border_id`.
  ///
  /// Pass an empty [borderId] to unequip. Persists unequip as `''`.
  /// Does not modify XP, session aggregates, quest fields, or profile
  /// metadata.
  Future<EquipBorderResult> equipBorder({
    required String userId,
    required String borderId,
  }) async {
    final trimmed = borderId.trim();
    if (trimmed.isNotEmpty && !isKnownProfileBorderId(trimmed)) {
      return const EquipBorderResult.invalidBorder();
    }
    _requireUser(userId);

    final response = await rpcMap(_client, 'equip_border', {
      'p_border_id': trimmed,
    });
    return switch (response['status']) {
      'equipped' => const EquipBorderResult.equipped(),
      'already_equipped' => const EquipBorderResult.alreadyEquipped(),
      'invalid_border' => const EquipBorderResult.invalidBorder(),
      'border_locked' => const EquipBorderResult.borderLocked(),
      'cosmetics_missing' => const EquipBorderResult.cosmeticsMissing(),
      'leaderboard_missing' => const EquipBorderResult.leaderboardMissing(),
      _ => throw const FormatException('Malformed equip result.'),
    };
  }

  void _requireUser(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('A matching authenticated user is required.');
    }
  }
}
