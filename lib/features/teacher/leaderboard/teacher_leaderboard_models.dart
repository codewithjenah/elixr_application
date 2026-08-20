import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';

import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
import '../../../data/repositories/leaderboard_repository.dart';

enum TeacherLeaderboardScope { global, myStudents, group }

abstract final class TeacherLeaderboardModels {
  static List<ElixrGroup> activeGroups(Iterable<ElixrGroup> groups) {
    return [
      for (final group in groups)
        if (group.isActive) group,
    ];
  }

  static String? recoverSelectedGroupId({
    required String? selectedGroupId,
    required List<ElixrGroup> activeGroups,
  }) {
    if (activeGroups.isEmpty) return null;
    if (selectedGroupId != null &&
        activeGroups.any((group) => group.id == selectedGroupId)) {
      return selectedGroupId;
    }
    return activeGroups.first.id;
  }

  static List<GroupMembership> approvedMemberships(
    Iterable<GroupMembership> memberships, {
    String? groupId,
  }) {
    return [
      for (final membership in memberships)
        if (membership.isApproved &&
            (groupId == null || membership.groupId == groupId))
          membership,
    ];
  }

  /// Deduplicated approved trainees mapped to the newest membership display name.
  static Map<String, String> uniqueApprovedTrainees(
    Iterable<GroupMembership> approved,
  ) {
    final newest = <String, GroupMembership>{};
    for (final membership in approved) {
      final current = newest[membership.traineeId];
      if (current == null || _isNewer(membership, current)) {
        newest[membership.traineeId] = membership;
      }
    }
    return {
      for (final entry in newest.entries)
        entry.key: entry.value.traineeDisplayName,
    };
  }

  static LeaderboardEntry fallbackEntry({
    required String userId,
    required String displayName,
  }) {
    return LeaderboardEntry(
      userId: userId,
      displayName: displayName,
      totalXp: 0,
      sessionsCompleted: 0,
      scoreSum: 0,
      averageScore: 0,
      bestScore: 0,
    );
  }

  static List<LeaderboardEntry> rankScoped({
    required Map<String, String> trainees,
    required Map<String, LeaderboardEntry> fetched,
    required LeaderboardPeriod period,
  }) {
    final entries = [
      for (final trainee in trainees.entries)
        fetched[trainee.key] ??
            fallbackEntry(userId: trainee.key, displayName: trainee.value),
    ];
    LeaderboardRepository.sortLeaderboardEntries(entries, period: period);
    return List<LeaderboardEntry>.unmodifiable(entries);
  }

  static bool hasClassroomAuthorization({
    required String traineeId,
    required Iterable<GroupMembership> memberships,
  }) {
    return memberships.any(
      (membership) =>
          membership.isApproved && membership.traineeId == traineeId,
    );
  }

  static String? drillDownGroupId({
    required String traineeId,
    required Iterable<GroupMembership> memberships,
    String? preferredGroupId,
  }) {
    final approved = [
      for (final membership in memberships)
        if (membership.isApproved && membership.traineeId == traineeId)
          membership,
    ];
    if (approved.isEmpty) return null;
    if (preferredGroupId != null &&
        approved.any((membership) => membership.groupId == preferredGroupId)) {
      return preferredGroupId;
    }
    return approved.first.groupId;
  }

  static bool _isNewer(GroupMembership candidate, GroupMembership current) {
    final candidateAt =
        candidate.updatedAt ?? candidate.createdAt ?? DateTime(0);
    final currentAt = current.updatedAt ?? current.createdAt ?? DateTime(0);
    return candidateAt.isAfter(currentAt);
  }
}
