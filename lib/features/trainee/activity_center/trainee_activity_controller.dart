import 'dart:async';

import 'package:elixr_core/models/classroom_announcement.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../core/router/app_route_paths.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../teacher/activity_center/activity_read_store.dart';

enum TraineeActivityType {
  newAssignment,
  dueSoon,
  overdue,
  newAnnouncement,
  pinnedAnnouncement,
  submissionChecked,
  workReturned,
  joinApproved,
}

class TraineeActivity {
  const TraineeActivity({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.title,
    required this.description,
    required this.destination,
    required this.isRead,
  });

  final String id;
  final TraineeActivityType type;
  final DateTime occurredAt;
  final String title;
  final String description;
  final String destination;
  final bool isRead;
}

/// Builds trainee activity from existing classroom sources of truth. Only the
/// read/unread choice is local; assignments, announcements, membership, and
/// grading remain owned by their existing repositories.
class TraineeActivityController extends ChangeNotifier {
  TraineeActivityController({
    required this.groupRepository,
    required this.assignmentRepository,
    required this.announcementRepository,
    required this.readStore,
    DateTime Function()? now,
    Timer Function(Duration, void Function(Timer))? periodicTimer,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _periodicTimer = periodicTimer ?? Timer.periodic;

  static const recentHistory = Duration(days: 30);
  static const deadlineWindow = Duration(hours: 48);
  static const maxReadStateEntries = 500;

  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final ClassroomAnnouncementRepository announcementRepository;
  final ActivityReadStore readStore;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function(Timer)) _periodicTimer;

  String? _traineeId;
  int _generation = 0;
  int _refreshGeneration = 0;
  bool _disposed = false;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  final Map<String, StreamSubscription<ClassroomAnnouncementPage>>
  _announcementSubs = {};
  final Map<String, int> _announcementLoadTokens = {};
  Timer? _refreshTimer;

  bool loading = false;
  Object? membershipsStreamError;
  Object? attemptsStreamError;
  Object? assignmentsError;
  final Map<String, Object> announcementErrors = {};
  String? persistenceMessage;
  List<GroupMembership> _memberships = const [];
  Map<String, ElixrGroup> _activeGroups = const {};
  List<GroupAssignment> _assignments = const [];
  List<AssignmentAttempt> _attempts = const [];
  final Map<String, List<ClassroomAnnouncement>> _announcementsByGroup = {};
  Map<String, DateTime> _readAtById = {};
  List<TraineeActivity> _activities = const [];

  List<TraineeActivity> get activities => _activities;
  int get unreadCount =>
      _activities.where((activity) => !activity.isRead).length;
  bool get hasStreamError =>
      membershipsStreamError != null ||
      attemptsStreamError != null ||
      assignmentsError != null ||
      announcementErrors.isNotEmpty;

  void setTrainee(String? traineeId) {
    final normalized = traineeId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_traineeId == next) return;
    _traineeId = next;
    unawaited(_restart());
  }

  Future<void> retry() => _restart();

  Future<void> _restart() async {
    final generation = ++_generation;
    _refreshGeneration++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final oldMemberships = _membershipsSub;
    final oldAttempts = _attemptsSub;
    _membershipsSub = null;
    _attemptsSub = null;
    _cancelAnnouncementWatches();
    _memberships = const [];
    _activeGroups = const {};
    _assignments = const [];
    _attempts = const [];
    _announcementsByGroup.clear();
    _readAtById = {};
    _activities = const [];
    membershipsStreamError = null;
    attemptsStreamError = null;
    assignmentsError = null;
    announcementErrors.clear();
    persistenceMessage = null;
    loading = _traineeId != null;
    _publish();
    _cancelSubscription(oldMemberships);
    _cancelSubscription(oldAttempts);
    if (_isStale(generation)) return;

    final traineeId = _traineeId;
    if (traineeId == null) return;
    try {
      final loaded = await readStore.load(_readAccountKey(traineeId));
      _readAtById = _pruneReadState(loaded);
      if (_readAtById.length != loaded.length) {
        await readStore.save(_readAccountKey(traineeId), _readAtById);
      }
    } catch (_) {
      persistenceMessage = 'Activity read state could not be restored.';
    }
    if (_isStale(generation)) return;

    final membershipsReady = Completer<void>();
    final attemptsReady = Completer<void>();
    _membershipsSub = groupRepository
        .watchTraineeMemberships(traineeId: traineeId)
        .listen(
          (value) => unawaited(
            _onMemberships(generation, traineeId, value, membershipsReady),
          ),
          onError: (Object error, StackTrace stackTrace) {
            if (_isStale(generation)) return;
            membershipsStreamError = error;
            _complete(membershipsReady);
            _publish();
          },
        );
    _attemptsSub = assignmentRepository
        .watchAttemptsForTrainee(traineeId: traineeId)
        .listen(
          (value) {
            if (_isStale(generation)) return;
            _attempts = [
              for (final attempt in value)
                if (attempt.traineeId == traineeId) attempt,
            ];
            attemptsStreamError = null;
            _complete(attemptsReady);
            _publish();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isStale(generation)) return;
            attemptsStreamError = error;
            _complete(attemptsReady);
            _publish();
          },
        );

    await Future.wait([membershipsReady.future, attemptsReady.future]);
    if (_isStale(generation)) return;
    loading = false;
    _publish();
    _refreshTimer = _periodicTimer(const Duration(minutes: 1), (_) {
      if (!_isStale(generation)) {
        unawaited(_refreshClassroomData(generation, traineeId));
      }
    });
  }

  Future<void> _onMemberships(
    int generation,
    String traineeId,
    List<GroupMembership> value,
    Completer<void> ready,
  ) async {
    if (_isStale(generation)) return;
    _memberships = [
      for (final membership in value)
        if (membership.traineeId == traineeId && membership.isApproved)
          membership,
    ];
    membershipsStreamError = null;
    await _refreshClassroomData(generation, traineeId);
    _complete(ready);
    _publish();
  }

  Future<void> _refreshClassroomData(int generation, String traineeId) async {
    final refreshGeneration = ++_refreshGeneration;
    final activeGroups = <String, ElixrGroup>{};
    await Future.wait([
      for (final membership in _memberships)
        () async {
          try {
            final group = await groupRepository.getGroup(
              groupId: membership.groupId,
            );
            if (group?.isActive == true &&
                group!.teacherId == membership.teacherId) {
              activeGroups[group.id] = group;
            }
          } catch (_) {
            // Archived or no-longer-readable classrooms are excluded.
          }
        }(),
    ]);
    if (_isStale(generation) || refreshGeneration != _refreshGeneration) {
      return;
    }
    _activeGroups = activeGroups;
    _syncAnnouncementWatches(generation, activeGroups.keys.toSet());
    try {
      final assignments = await assignmentRepository.fetchAssignmentsForTrainee(
        traineeId: traineeId,
      );
      if (_isStale(generation) || refreshGeneration != _refreshGeneration) {
        return;
      }
      _assignments = [
        for (final assignment in assignments)
          if (assignment.isActive &&
              activeGroups.containsKey(assignment.groupId) &&
              assignment.isAvailableToTrainee(traineeId))
            assignment,
      ];
      assignmentsError = null;
    } catch (error) {
      if (_isStale(generation) || refreshGeneration != _refreshGeneration) {
        return;
      }
      assignmentsError = error;
    }
    _publish();
  }

  void _syncAnnouncementWatches(int generation, Set<String> groupIds) {
    final stale = _announcementSubs.keys
        .where((groupId) => !groupIds.contains(groupId))
        .toList(growable: false);
    for (final groupId in stale) {
      _cancelSubscription(_announcementSubs.remove(groupId));
      _announcementLoadTokens[groupId] =
          (_announcementLoadTokens[groupId] ?? 0) + 1;
      _announcementsByGroup.remove(groupId);
      announcementErrors.remove(groupId);
    }
    for (final groupId in groupIds) {
      if (_announcementSubs.containsKey(groupId)) continue;
      _announcementSubs[groupId] = announcementRepository
          .watchAnnouncements(groupId: groupId)
          .listen(
            (page) =>
                unawaited(_loadRecentAnnouncements(generation, groupId, page)),
            onError: (Object error, StackTrace stackTrace) {
              if (_isStale(generation)) return;
              announcementErrors[groupId] = error;
              _publish();
            },
          );
    }
  }

  Future<void> _loadRecentAnnouncements(
    int generation,
    String groupId,
    ClassroomAnnouncementPage firstPage,
  ) async {
    if (_isStale(generation) || !_activeGroups.containsKey(groupId)) return;
    final token = (_announcementLoadTokens[groupId] ?? 0) + 1;
    _announcementLoadTokens[groupId] = token;
    final cutoff = _now().toUtc().subtract(recentHistory);
    final byId = <String, ClassroomAnnouncement>{
      for (final item in firstPage.items) item.id: item,
    };
    _announcementsByGroup[groupId] = byId.values.toList(growable: false);
    announcementErrors.remove(groupId);
    _publish();
    var hasMore = firstPage.hasMore;
    var cursor = firstPage.nextCursor;
    try {
      while (hasMore && cursor != null) {
        final page = await announcementRepository.fetchOlderAnnouncements(
          groupId: groupId,
          startAfter: cursor,
        );
        if (_isStale(generation) ||
            _announcementLoadTokens[groupId] != token ||
            !_activeGroups.containsKey(groupId)) {
          return;
        }
        for (final item in page.items) {
          byId[item.id] = item;
        }
        hasMore = page.hasMore;
        cursor = page.nextCursor;
        if (page.items.isNotEmpty &&
            page.items.every((item) => !_hasRecentActivity(item, cutoff))) {
          break;
        }
      }
      if (_isStale(generation) ||
          _announcementLoadTokens[groupId] != token ||
          !_activeGroups.containsKey(groupId)) {
        return;
      }
      _announcementsByGroup[groupId] = byId.values.toList(growable: false);
      announcementErrors.remove(groupId);
      _publish();
    } catch (error) {
      if (_isStale(generation) || _announcementLoadTokens[groupId] != token) {
        return;
      }
      announcementErrors[groupId] = error;
      _publish();
    }
  }

  Future<void> markRead(TraineeActivity activity) async {
    final traineeId = _traineeId;
    if (traineeId == null || activity.isRead) return;
    _readAtById[activity.id] = _now().toUtc();
    _readAtById = _pruneReadState(_readAtById);
    _publish();
    await _saveReadState(traineeId);
  }

  Future<bool> markAllRead() async {
    final traineeId = _traineeId;
    if (traineeId == null || unreadCount == 0) return false;
    final readAt = _now().toUtc();
    for (final activity in _activities) {
      _readAtById[activity.id] = readAt;
    }
    _readAtById = _pruneReadState(_readAtById);
    _publish();
    return _saveReadState(traineeId);
  }

  Future<bool> _saveReadState(String traineeId) async {
    try {
      await readStore.save(
        _readAccountKey(traineeId),
        Map<String, DateTime>.from(_readAtById),
      );
      if (_traineeId == traineeId) {
        persistenceMessage = null;
        _publish();
      }
      return true;
    } catch (_) {
      if (_traineeId == traineeId) {
        persistenceMessage = 'Activity read state could not be saved.';
        _publish();
      }
      return false;
    }
  }

  void _publish() {
    final traineeId = _traineeId;
    if (traineeId != null) _activities = _buildActivities(traineeId);
    if (!_disposed) notifyListeners();
  }

  List<TraineeActivity> _buildActivities(String traineeId) {
    final now = _now().toUtc();
    final cutoff = now.subtract(recentHistory);
    final assignmentsById = <String, GroupAssignment>{
      for (final assignment in _assignments) assignment.id: assignment,
    };
    final attemptsByAssignment = <String, List<AssignmentAttempt>>{};
    for (final attempt in _attempts) {
      if (attempt.traineeId != traineeId ||
          !_activeGroups.containsKey(attempt.groupId) ||
          !assignmentsById.containsKey(attempt.assignmentId)) {
        continue;
      }
      attemptsByAssignment
          .putIfAbsent(attempt.assignmentId, () => [])
          .add(attempt);
    }
    final latestByAssignment = <String, AssignmentAttempt?>{
      for (final entry in attemptsByAssignment.entries)
        entry.key: AssignmentAttemptSemantics.latestVisible(
          attempts: entry.value,
          assignmentId: entry.key,
          traineeId: traineeId,
        ),
    };
    final activities = <TraineeActivity>[];

    for (final membership in _memberships) {
      if (!_activeGroups.containsKey(membership.groupId)) continue;
      final at = (membership.updatedAt ?? membership.createdAt)?.toUtc();
      if (at == null || at.isBefore(cutoff)) continue;
      final groupName = _activeGroups[membership.groupId]!.name;
      activities.add(
        _activity(
          id: 'join_approved:${membership.id}',
          type: TraineeActivityType.joinApproved,
          occurredAt: at,
          title: 'You joined $groupName',
          description: 'Your teacher approved your class request.',
          destination: AppRoutePaths.teacherAccessClass(membership.groupId),
        ),
      );
    }

    for (final assignment in _assignments) {
      final createdAt = assignment.createdAt?.toUtc();
      if (createdAt != null && !createdAt.isBefore(cutoff)) {
        activities.add(
          _activity(
            id: 'new_assignment:${assignment.id}',
            type: TraineeActivityType.newAssignment,
            occurredAt: createdAt,
            title: 'New assignment: ${assignment.displayTitle}',
            description: 'Assigned in ${assignment.groupName}.',
            destination: AppRoutePaths.assignmentDetail(assignment.id),
          ),
        );
      }
      final dueAt = assignment.dueAt?.toUtc();
      if (dueAt == null || !_isIncomplete(latestByAssignment[assignment.id])) {
        continue;
      }
      final windowEntry = dueAt.subtract(deadlineWindow);
      if (!now.isBefore(dueAt) && !dueAt.isBefore(cutoff)) {
        activities.add(
          _activity(
            id: 'overdue:${assignment.id}:${dueAt.millisecondsSinceEpoch}',
            type: TraineeActivityType.overdue,
            occurredAt: dueAt,
            title: '${assignment.displayTitle} is overdue',
            description: 'Open the assignment to finish your work.',
            destination: AppRoutePaths.assignmentDetail(assignment.id),
          ),
        );
      } else if (!now.isBefore(windowEntry) && now.isBefore(dueAt)) {
        activities.add(
          _activity(
            id: 'due_soon:${assignment.id}:${dueAt.millisecondsSinceEpoch}',
            type: TraineeActivityType.dueSoon,
            occurredAt: windowEntry,
            title: '${assignment.displayTitle} is due soon',
            description: 'Due within the next 48 hours.',
            destination: AppRoutePaths.assignmentDetail(assignment.id),
          ),
        );
      }
    }

    for (final entry in _announcementsByGroup.entries) {
      final group = _activeGroups[entry.key];
      if (group == null) continue;
      for (final announcement in entry.value) {
        final createdAt = announcement.createdAt?.toUtc();
        if (createdAt != null && !createdAt.isBefore(cutoff)) {
          activities.add(
            _activity(
              id: 'announcement:${group.id}:${announcement.id}',
              type: TraineeActivityType.newAnnouncement,
              occurredAt: createdAt,
              title: announcement.title,
              description: 'New announcement in ${group.name}.',
              destination:
                  '${AppRoutePaths.teacherAccessClass(group.id)}?tab=stream',
            ),
          );
        }
        final pinnedAt = announcement.pinnedAt?.toUtc();
        if (announcement.isPinned &&
            pinnedAt != null &&
            !pinnedAt.isBefore(cutoff)) {
          activities.add(
            _activity(
              id: 'pinned_announcement:${group.id}:${announcement.id}:${pinnedAt.millisecondsSinceEpoch}',
              type: TraineeActivityType.pinnedAnnouncement,
              occurredAt: pinnedAt,
              title: 'Pinned: ${announcement.title}',
              description: 'Pinned in ${group.name}.',
              destination:
                  '${AppRoutePaths.teacherAccessClass(group.id)}?tab=stream',
            ),
          );
        }
      }
    }

    for (final attempt in _attempts) {
      final assignment = assignmentsById[attempt.assignmentId];
      if (assignment == null ||
          attempt.traineeId != traineeId ||
          attempt.groupId != assignment.groupId ||
          !_activeGroups.containsKey(attempt.groupId)) {
        continue;
      }
      if (attempt.status == AssignmentAttemptStatus.checked) {
        final at = (attempt.checkedAt ?? attempt.reviewUpdatedAt)?.toUtc();
        if (at != null && !at.isBefore(cutoff)) {
          activities.add(
            _activity(
              id: 'submission_checked:${attempt.id}:${attempt.reviewRevision ?? 0}',
              type: TraineeActivityType.submissionChecked,
              occurredAt: at,
              title: 'Your ${assignment.displayTitle} work was checked',
              description: 'Open it to see your score and feedback.',
              destination: AppRoutePaths.assignmentDetail(assignment.id),
            ),
          );
        }
      } else if (attempt.status == AssignmentAttemptStatus.needsRetry) {
        final at = (attempt.reviewedAt ?? attempt.reviewUpdatedAt)?.toUtc();
        if (at != null && !at.isBefore(cutoff)) {
          activities.add(
            _activity(
              id: 'work_returned:${attempt.id}:${attempt.reviewRevision ?? 0}',
              type: TraineeActivityType.workReturned,
              occurredAt: at,
              title: 'Your ${assignment.displayTitle} work was returned',
              description: 'Open it to review feedback and submit again.',
              destination: AppRoutePaths.assignmentDetail(assignment.id),
            ),
          );
        }
      }
    }

    activities.sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return activities;
  }

  TraineeActivity _activity({
    required String id,
    required TraineeActivityType type,
    required DateTime occurredAt,
    required String title,
    required String description,
    required String destination,
  }) => TraineeActivity(
    id: id,
    type: type,
    occurredAt: occurredAt,
    title: title,
    description: description,
    destination: destination,
    isRead: _readAtById.containsKey(id),
  );

  static bool _isIncomplete(AssignmentAttempt? attempt) {
    if (attempt == null) return true;
    return switch (attempt.status) {
      AssignmentAttemptStatus.submitted ||
      AssignmentAttemptStatus.unsubmitting ||
      AssignmentAttemptStatus.checked ||
      AssignmentAttemptStatus.approved => false,
      AssignmentAttemptStatus.draft ||
      AssignmentAttemptStatus.inProgress ||
      AssignmentAttemptStatus.needsRetry => true,
    };
  }

  static bool _hasRecentActivity(
    ClassroomAnnouncement announcement,
    DateTime cutoff,
  ) {
    final createdAt = announcement.createdAt?.toUtc();
    final pinnedAt = announcement.pinnedAt?.toUtc();
    return (createdAt != null && !createdAt.isBefore(cutoff)) ||
        (announcement.isPinned &&
            pinnedAt != null &&
            !pinnedAt.isBefore(cutoff));
  }

  Map<String, DateTime> _pruneReadState(Map<String, DateTime> source) {
    final cutoff = _now().toUtc().subtract(recentHistory);
    final entries =
        source.entries
            .where((entry) => entry.value.toUtc().isAfter(cutoff))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(maxReadStateEntries));
  }

  static String _readAccountKey(String traineeId) => 'trainee:$traineeId';

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void _cancelSubscription(StreamSubscription<dynamic>? subscription) {
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _cancelAnnouncementWatches() {
    for (final subscription in _announcementSubs.values) {
      unawaited(subscription.cancel());
    }
    _announcementSubs.clear();
    _announcementLoadTokens.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _refreshGeneration++;
    _refreshTimer?.cancel();
    _cancelSubscription(_membershipsSub);
    _cancelSubscription(_attemptsSub);
    _cancelAnnouncementWatches();
    super.dispose();
  }
}
