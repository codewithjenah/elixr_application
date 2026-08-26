import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';

/// Filter for the Students roster.
enum TeacherStudentStatusFilter { all, approved, pending, inactive }

/// Aggregated student directory entry across one or more group memberships.
class TeacherStudentEntry {
  const TeacherStudentEntry({
    required this.traineeId,
    required this.displayName,
    required this.memberships,
    required this.effectiveStatus,
  });

  final String traineeId;
  final String displayName;
  final List<GroupMembership> memberships;
  final GroupMembershipStatus effectiveStatus;

  bool get hasApprovedMembership => memberships.any((m) => m.isApproved);

  List<String> groupIdsFor(Set<String> ownedGroupIds) {
    return memberships
        .where((m) => ownedGroupIds.contains(m.groupId))
        .map((m) => m.groupId)
        .toSet()
        .toList();
  }
}

/// Dashboard group summary derived from memberships.
class TeacherGroupSummary {
  const TeacherGroupSummary({
    required this.group,
    required this.approvedCount,
    required this.pendingCount,
  });

  final ElixrGroup group;
  final int approvedCount;
  final int pendingCount;
}

String teacherStudentStatusLabel(GroupMembershipStatus status) {
  return switch (status) {
    GroupMembershipStatus.approved => 'Approved',
    GroupMembershipStatus.pending => 'Pending',
    GroupMembershipStatus.rejected => 'Rejected',
    GroupMembershipStatus.cancelled => 'Cancelled',
    GroupMembershipStatus.removed => 'Removed',
  };
}

bool membershipMatchesStatusFilter(
  GroupMembershipStatus status,
  TeacherStudentStatusFilter filter,
) {
  return switch (filter) {
    TeacherStudentStatusFilter.all => true,
    TeacherStudentStatusFilter.approved =>
      status == GroupMembershipStatus.approved,
    TeacherStudentStatusFilter.pending =>
      status == GroupMembershipStatus.pending,
    TeacherStudentStatusFilter.inactive =>
      status == GroupMembershipStatus.rejected ||
          status == GroupMembershipStatus.cancelled ||
          status == GroupMembershipStatus.removed,
  };
}

GroupMembershipStatus effectiveMembershipStatus(
  Iterable<GroupMembership> memberships,
) {
  final list = memberships.toList();
  if (list.any((m) => m.isApproved)) {
    return GroupMembershipStatus.approved;
  }
  if (list.any((m) => m.isPending)) {
    return GroupMembershipStatus.pending;
  }
  list.sort(
    (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
      a.updatedAt ?? a.createdAt ?? DateTime(0),
    ),
  );
  return list.first.status;
}

List<TeacherStudentEntry> aggregateTeacherStudents(
  List<GroupMembership> memberships,
) {
  final byTrainee = <String, List<GroupMembership>>{};
  for (final membership in memberships) {
    byTrainee.putIfAbsent(membership.traineeId, () => []).add(membership);
  }
  final entries = <TeacherStudentEntry>[];
  for (final entry in byTrainee.entries) {
    final items = entry.value;
    final displayName = _newestDisplayName(items);
    entries.add(
      TeacherStudentEntry(
        traineeId: entry.key,
        displayName: displayName,
        memberships: List.unmodifiable(items),
        effectiveStatus: effectiveMembershipStatus(items),
      ),
    );
  }
  entries.sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );
  return entries;
}

String _newestDisplayName(List<GroupMembership> memberships) {
  final sorted = [...memberships]
    ..sort(
      (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(0)).compareTo(
        a.updatedAt ?? a.createdAt ?? DateTime(0),
      ),
    );
  return sorted.first.traineeDisplayName;
}

List<TeacherStudentEntry> filterTeacherStudents({
  required List<TeacherStudentEntry> entries,
  required String searchQuery,
  required String? groupId,
  required TeacherStudentStatusFilter statusFilter,
}) {
  final trimmed = searchQuery.trim().toLowerCase();
  return entries.where((entry) {
    if (groupId != null &&
        !entry.memberships.any((m) => m.groupId == groupId)) {
      return false;
    }
    if (!membershipMatchesStatusFilter(entry.effectiveStatus, statusFilter)) {
      return false;
    }
    if (trimmed.isEmpty) return true;
    return entry.displayName.toLowerCase().contains(trimmed);
  }).toList();
}

List<TeacherGroupSummary> buildGroupSummaries({
  required List<ElixrGroup> groups,
  required List<GroupMembership> memberships,
}) {
  return [
    for (final group in groups.where((g) => g.isActive))
      TeacherGroupSummary(
        group: group,
        approvedCount: memberships
            .where((m) => m.groupId == group.id && m.isApproved)
            .length,
        pendingCount: memberships
            .where(
              (m) =>
                  m.groupId == group.id &&
                  m.status == GroupMembershipStatus.pending,
            )
            .length,
      ),
  ];
}

/// One class with the students that belong only to that class.
class TeacherGroupRoster {
  const TeacherGroupRoster({required this.group, required this.memberships});

  final ElixrGroup group;
  final List<GroupMembership> memberships;
}

List<TeacherGroupRoster> buildTeacherGroupRosters({
  required List<ElixrGroup> groups,
  required List<GroupMembership> memberships,
  required String searchQuery,
  required String? groupId,
  required TeacherStudentStatusFilter statusFilter,
}) {
  final trimmed = searchQuery.trim().toLowerCase();
  final orderedGroups = [
    ...groups.where((group) => group.isActive),
    ...groups.where((group) => !group.isActive),
  ];
  final rosters = <TeacherGroupRoster>[];
  for (final group in orderedGroups) {
    if (groupId != null && group.id != groupId) continue;
    final members =
        memberships.where((membership) {
          if (membership.groupId != group.id) return false;
          if (!membershipMatchesStatusFilter(membership.status, statusFilter)) {
            return false;
          }
          if (trimmed.isNotEmpty &&
              !membership.traineeDisplayName.toLowerCase().contains(trimmed)) {
            return false;
          }
          return true;
        }).toList()..sort(
          (a, b) => a.traineeDisplayName.toLowerCase().compareTo(
            b.traineeDisplayName.toLowerCase(),
          ),
        );
    if (trimmed.isNotEmpty && members.isEmpty) continue;
    if (!group.isActive && members.isEmpty) continue;
    rosters.add(TeacherGroupRoster(group: group, memberships: members));
  }
  return rosters;
}
