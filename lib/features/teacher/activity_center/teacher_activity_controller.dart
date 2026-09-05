import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

import '../../../core/router/app_route_paths.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_review_state.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import 'activity_read_store.dart';

enum TeacherActivityType {
  joinRequest,
  newSubmission,
  retryResubmission,
  message,
  upcomingDeadline,
  movementCompleted,
}

class TeacherActivity {
  const TeacherActivity({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.title,
    required this.description,
    required this.destination,
    required this.isRead,
    this.actorUserId,
    this.actorDisplayName,
    this.actorProfilePictureUrl,
  });

  final String id;
  final TeacherActivityType type;
  final DateTime occurredAt;
  final String title;
  final String description;
  final String destination;
  final bool isRead;

  /// The student who caused this activity. Class-wide reminders have no actor.
  final String? actorUserId;
  final String? actorDisplayName;
  final String? actorProfilePictureUrl;

  TeacherActivity copyWith({bool? isRead, String? actorProfilePictureUrl}) =>
      TeacherActivity(
        id: id,
        type: type,
        occurredAt: occurredAt,
        title: title,
        description: description,
        destination: destination,
        isRead: isRead ?? this.isRead,
        actorUserId: actorUserId,
        actorDisplayName: actorDisplayName,
        actorProfilePictureUrl:
            actorProfilePictureUrl ?? this.actorProfilePictureUrl,
      );
}

class TeacherPendingReview {
  const TeacherPendingReview({
    required this.attempt,
    required this.assignment,
    required this.traineeName,
    required this.submittedAt,
    required this.deadlineState,
    required this.destination,
    this.traineeProfilePictureUrl,
  });

  final AssignmentAttempt attempt;
  final GroupAssignment assignment;
  final String traineeName;
  final DateTime submittedAt;
  final AssignmentDeadlineState deadlineState;
  final String destination;
  final String? traineeProfilePictureUrl;
}

/// Combines the existing teacher-facing streams without changing their
/// Firestore contracts. Read state is local to the signed-in teacher.
class TeacherActivityController extends ChangeNotifier {
  TeacherActivityController({
    required this.groupRepository,
    required this.assignmentRepository,
    required this.chatRepository,
    required this.readStore,
    this.publicProfileRepository,
    DateTime Function()? now,
    Timer Function(Duration, void Function(Timer))? periodicTimer,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _periodicTimer = periodicTimer ?? Timer.periodic;

  static const recentHistory = Duration(days: 30);
  static const deadlineWindow = Duration(hours: 48);
  static const maxReadStateEntries = 500;

  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final ChatRepository chatRepository;
  final ActivityReadStore readStore;
  final PublicProfileRepository? publicProfileRepository;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function(Timer)) _periodicTimer;

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<GroupAssignment>>? _assignmentsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  StreamSubscription<List<ChatConversation>>? _inboxSub;
  final Map<String, StreamSubscription<dynamic>> _profileSubs = {};
  final Map<String, String> _profilePictureUrls = {};
  Completer<void>? _membershipsReady;
  Completer<void>? _assignmentsReady;
  Completer<void>? _attemptsReady;
  Completer<void>? _inboxReady;
  Timer? _deadlineTimer;
  String? _teacherId;
  int _generation = 0;
  bool _disposed = false;

  bool loading = false;
  Object? membershipsStreamError;
  Object? assignmentsStreamError;
  Object? attemptsStreamError;
  Object? inboxStreamError;
  String? persistenceMessage;
  List<GroupMembership> _memberships = const [];
  List<GroupAssignment> _assignments = const [];
  List<AssignmentAttempt> _attempts = const [];
  List<ChatConversation> _inbox = const [];
  Map<String, DateTime> _readAtById = <String, DateTime>{};
  List<TeacherActivity> _activities = const [];
  List<TeacherPendingReview> _pendingReviews = const [];

  List<TeacherActivity> get activities => _activities;
  List<TeacherPendingReview> get pendingReviews => _pendingReviews;
  int get pendingReviewCount => _pendingReviews.length;
  int get pendingJoinCount {
    final teacherId = _teacherId;
    if (teacherId == null) return 0;
    return _memberships
        .where(
          (membership) =>
              membership.teacherId == teacherId &&
              membership.status == GroupMembershipStatus.pending,
        )
        .length;
  }

  int get unreadCount =>
      _activities.where((activity) => !activity.isRead).length;
  bool get hasStreamError =>
      membershipsStreamError != null ||
      assignmentsStreamError != null ||
      attemptsStreamError != null ||
      inboxStreamError != null;
  bool get hasPendingReviewStreamError =>
      membershipsStreamError != null ||
      assignmentsStreamError != null ||
      attemptsStreamError != null;

  void setTeacher(String? teacherId) {
    final normalized = teacherId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_teacherId == next) return;
    _teacherId = next;
    unawaited(_restart());
  }

  Future<void> retry() => _restart();

  Future<void> _restart() async {
    final generation = ++_generation;
    _complete(_membershipsReady);
    _complete(_assignmentsReady);
    _complete(_attemptsReady);
    _complete(_inboxReady);
    _membershipsReady = null;
    _assignmentsReady = null;
    _attemptsReady = null;
    _inboxReady = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    final oldMembershipsSub = _membershipsSub;
    final oldAssignmentsSub = _assignmentsSub;
    final oldAttemptsSub = _attemptsSub;
    final oldInboxSub = _inboxSub;
    _membershipsSub = null;
    _assignmentsSub = null;
    _attemptsSub = null;
    _inboxSub = null;
    _memberships = const [];
    _assignments = const [];
    _attempts = const [];
    _inbox = const [];
    _readAtById = <String, DateTime>{};
    _activities = const [];
    _pendingReviews = const [];
    _cancelProfileWatches();
    membershipsStreamError = null;
    assignmentsStreamError = null;
    attemptsStreamError = null;
    inboxStreamError = null;
    persistenceMessage = null;
    loading = _teacherId != null;
    _publish();
    _cancelSubscription(oldMembershipsSub);
    _cancelSubscription(oldAssignmentsSub);
    _cancelSubscription(oldAttemptsSub);
    _cancelSubscription(oldInboxSub);
    if (_isStale(generation)) return;

    final teacherId = _teacherId;
    if (teacherId == null) return;

    try {
      final loaded = await readStore.load(teacherId);
      _readAtById = _pruneReadState(loaded);
      if (_readAtById.length != loaded.length) {
        await readStore.save(teacherId, _readAtById);
      }
    } catch (_) {
      persistenceMessage = 'Activity read state could not be restored.';
    }
    if (_isStale(generation)) return;

    final membershipsReady = Completer<void>();
    final assignmentsReady = Completer<void>();
    final attemptsReady = Completer<void>();
    final inboxReady = Completer<void>();
    _membershipsReady = membershipsReady;
    _assignmentsReady = assignmentsReady;
    _attemptsReady = attemptsReady;
    _inboxReady = inboxReady;
    final membershipsSub = _listenSafely<GroupMembership>(
      source: () =>
          groupRepository.watchTeacherMemberships(teacherId: teacherId),
      generation: generation,
      ready: membershipsReady,
      onData: (value) => _onMemberships(generation, membershipsReady, value),
      onError: (value) => membershipsStreamError = value,
    );
    final assignmentsSub = _listenSafely<GroupAssignment>(
      source: () =>
          assignmentRepository.watchTeacherAssignments(teacherId: teacherId),
      generation: generation,
      ready: assignmentsReady,
      onData: (value) => _onAssignments(generation, assignmentsReady, value),
      onError: (value) => assignmentsStreamError = value,
    );
    final attemptsSub = _listenSafely<AssignmentAttempt>(
      source: () =>
          assignmentRepository.watchAttemptsForTeacher(teacherId: teacherId),
      generation: generation,
      ready: attemptsReady,
      onData: (value) => _onAttempts(generation, attemptsReady, value),
      onError: (value) => attemptsStreamError = value,
    );
    final inboxSub = _listenSafely<ChatConversation>(
      source: () => chatRepository.watchInbox(teacherId),
      generation: generation,
      ready: inboxReady,
      onData: (value) => _onInbox(generation, inboxReady, value),
      onError: (value) => inboxStreamError = value,
    );
    if (_isStale(generation)) {
      _cancelSubscription(membershipsSub);
      _cancelSubscription(assignmentsSub);
      _cancelSubscription(attemptsSub);
      _cancelSubscription(inboxSub);
      return;
    }
    _membershipsSub = membershipsSub;
    _assignmentsSub = assignmentsSub;
    _attemptsSub = attemptsSub;
    _inboxSub = inboxSub;
    final deadlineTimer = _periodicTimer(const Duration(minutes: 1), (_) {
      if (!_isStale(generation)) _publish();
    });
    if (_isStale(generation)) {
      deadlineTimer.cancel();
      _cancelSubscription(membershipsSub);
      _cancelSubscription(assignmentsSub);
      _cancelSubscription(attemptsSub);
      _cancelSubscription(inboxSub);
      return;
    }
    _deadlineTimer = deadlineTimer;

    await Future.wait([
      membershipsReady.future,
      assignmentsReady.future,
      attemptsReady.future,
      inboxReady.future,
    ]);
    if (_isStale(generation)) return;
    loading = false;
    _publish();
  }

  Future<void> markRead(TeacherActivity activity) async {
    if (_teacherId == null || activity.isRead) return;
    _readAtById[activity.id] = _now().toUtc();
    _readAtById = _pruneReadState(_readAtById);
    _publish();
    await _saveReadState();
  }

  Future<bool> markAllRead() async {
    if (_teacherId == null || unreadCount == 0) return false;
    final readAt = _now().toUtc();
    for (final activity in _activities) {
      _readAtById[activity.id] = readAt;
    }
    _readAtById = _pruneReadState(_readAtById);
    _publish();
    return _saveReadState();
  }

  void _onMemberships(
    int generation,
    Completer<void> ready,
    List<GroupMembership> value,
  ) {
    if (_isStale(generation)) return;
    _memberships = value;
    membershipsStreamError = null;
    _complete(ready);
    _publish();
  }

  void _onAssignments(
    int generation,
    Completer<void> ready,
    List<GroupAssignment> value,
  ) {
    if (_isStale(generation)) return;
    _assignments = value;
    assignmentsStreamError = null;
    _complete(ready);
    _publish();
  }

  void _onAttempts(
    int generation,
    Completer<void> ready,
    List<AssignmentAttempt> value,
  ) {
    if (_isStale(generation)) return;
    _attempts = value;
    attemptsStreamError = null;
    _complete(ready);
    _publish();
  }

  void _onInbox(
    int generation,
    Completer<void> ready,
    List<ChatConversation> value,
  ) {
    if (_isStale(generation)) return;
    _inbox = value;
    inboxStreamError = null;
    _complete(ready);
    _publish();
  }

  void _onStreamError(
    int generation,
    Completer<void> ready,
    Object error,
    void Function(Object) assign,
  ) {
    if (_isStale(generation)) return;
    assign(error);
    _complete(ready);
    _publish();
  }

  Future<bool> _saveReadState() async {
    final teacherId = _teacherId;
    if (teacherId == null) return false;
    try {
      await readStore.save(teacherId, Map<String, DateTime>.from(_readAtById));
      if (_teacherId == teacherId) {
        persistenceMessage = null;
        _publish();
      }
      return true;
    } catch (_) {
      if (_teacherId == teacherId) {
        persistenceMessage = 'Activity read state could not be saved.';
        _publish();
      }
      return false;
    }
  }

  Map<String, DateTime> _pruneReadState(Map<String, DateTime> source) {
    final cutoff = _now().toUtc().subtract(recentHistory);
    final entries =
        source.entries
            .where((entry) => entry.value.toUtc().isAfter(cutoff))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, DateTime>.fromEntries(entries.take(maxReadStateEntries));
  }

  void _publish() {
    final teacherId = _teacherId;
    if (teacherId != null) {
      _activities = _buildActivities(teacherId);
      _pendingReviews = _buildPendingReviews(teacherId);
      _syncProfileWatches();
    }
    if (!_disposed) notifyListeners();
  }

  void _syncProfileWatches() {
    final repository = publicProfileRepository;
    if (repository == null) return;

    final actorIds = {
      for (final activity in _activities)
        if (activity.actorUserId != null) activity.actorUserId!,
      for (final review in _pendingReviews) review.attempt.traineeId,
    };
    final staleIds = _profileSubs.keys
        .where((id) => !actorIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_profileSubs.remove(id)?.cancel());
      _profilePictureUrls.remove(id);
    }

    for (final actorId in actorIds) {
      if (_profileSubs.containsKey(actorId)) continue;
      _profileSubs[actorId] = repository
          .watchProfileRoot(actorId)
          .listen(
            (profile) {
              if (_disposed) return;
              final url = profile?.profilePictureUrl?.trim();
              final next = url == null || url.isEmpty ? null : url;
              if (_profilePictureUrls[actorId] == next) return;
              if (next == null) {
                _profilePictureUrls.remove(actorId);
              } else {
                _profilePictureUrls[actorId] = next;
              }
              _publish();
            },
            onError: (_, _) {
              // The activity remains usable when an optional avatar is unavailable.
            },
          );
    }
  }

  List<TeacherPendingReview> _buildPendingReviews(String teacherId) {
    final now = _now().toUtc();
    final assignmentsById = <String, GroupAssignment>{
      for (final assignment in _assignments)
        if (assignment.teacherId == teacherId) assignment.id: assignment,
    };
    final authorizedMemberships = <String, GroupMembership>{
      for (final membership in _memberships)
        if (membership.teacherId == teacherId &&
            membership.hasClassroomAuthorization)
          '${membership.groupId}:${membership.traineeId}': membership,
    };
    final attemptsByRecipient = <String, List<AssignmentAttempt>>{};
    for (final attempt in _attempts) {
      if (attempt.teacherId != teacherId) continue;
      final assignment = assignmentsById[attempt.assignmentId];
      if (assignment == null ||
          assignment.groupId != attempt.groupId ||
          assignment.movementId != attempt.movementId ||
          assignment.revisionId != attempt.revisionId ||
          !assignment.isTeacherCreated ||
          !assignment.isAvailableToTrainee(attempt.traineeId) ||
          !authorizedMemberships.containsKey(
            '${attempt.groupId}:${attempt.traineeId}',
          )) {
        continue;
      }
      attemptsByRecipient
          .putIfAbsent(
            '${attempt.assignmentId}:${attempt.traineeId}',
            () => <AssignmentAttempt>[],
          )
          .add(attempt);
    }

    final pending = <TeacherPendingReview>[];
    for (final attempts in attemptsByRecipient.values) {
      final first = attempts.first;
      final current = AssignmentAttemptSemantics.latestVisible(
        attempts: attempts,
        assignmentId: first.assignmentId,
        traineeId: first.traineeId,
      );
      if (!AssignmentReviewSemantics.isActionablePending(current, now: now)) {
        continue;
      }
      final assignment = assignmentsById[current!.assignmentId]!;
      final membership =
          authorizedMemberships['${current.groupId}:${current.traineeId}']!;
      pending.add(
        TeacherPendingReview(
          attempt: current,
          assignment: assignment,
          traineeName: membership.traineeDisplayName,
          submittedAt: current.submittedAt!,
          deadlineState: AssignmentReviewSemantics.deadlineStateFor(
            assignment: assignment,
            attempt: current,
            now: now,
          ),
          destination: AppRoutePaths.teacherGroupClasswork(
            current.groupId,
            current.assignmentId,
            traineeId: current.traineeId,
          ),
          traineeProfilePictureUrl: _profilePictureUrls[current.traineeId],
        ),
      );
    }
    pending.sort((a, b) {
      final byTime = a.submittedAt.compareTo(b.submittedAt);
      if (byTime != 0) return byTime;
      final byAssignment = a.assignment.id.compareTo(b.assignment.id);
      if (byAssignment != 0) return byAssignment;
      final byTrainee = a.attempt.traineeId.compareTo(b.attempt.traineeId);
      return byTrainee != 0 ? byTrainee : a.attempt.id.compareTo(b.attempt.id);
    });
    return pending;
  }

  void _cancelProfileWatches() {
    for (final subscription in _profileSubs.values) {
      unawaited(subscription.cancel());
    }
    _profileSubs.clear();
    _profilePictureUrls.clear();
  }

  List<TeacherActivity> _buildActivities(String teacherId) {
    final now = _now().toUtc();
    final cutoff = now.subtract(recentHistory);
    final membershipsByTraineeAndGroup = <String, GroupMembership>{
      for (final membership in _memberships)
        if (membership.teacherId == teacherId)
          '${membership.groupId}:${membership.traineeId}': membership,
    };
    final assignmentsById = <String, GroupAssignment>{
      for (final assignment in _assignments)
        if (assignment.teacherId == teacherId) assignment.id: assignment,
    };
    final activities = <TeacherActivity>[];

    for (final membership in _memberships) {
      if (membership.teacherId != teacherId) continue;
      final at = (membership.updatedAt ?? membership.createdAt)?.toUtc();
      if (!membership.isPending || at == null || at.isBefore(cutoff)) continue;
      activities.add(
        _activity(
          id: 'join_request:${membership.id}',
          type: TeacherActivityType.joinRequest,
          occurredAt: at,
          title: '${membership.traineeDisplayName} requested to join',
          description: 'Review the request for this class in Groups.',
          destination: AppRoutePaths.teacherGroup(membership.groupId),
          actorUserId: membership.traineeId,
          actorDisplayName: membership.traineeDisplayName,
        ),
      );
    }

    for (final attempt in _attempts) {
      if (attempt.teacherId != teacherId) continue;
      final assignment = assignmentsById[attempt.assignmentId];
      final traineeName =
          membershipsByTraineeAndGroup['${attempt.groupId}:${attempt.traineeId}']
              ?.traineeDisplayName ??
          _membershipForTrainee(
            attempt.traineeId,
            teacherId,
          )?.traineeDisplayName ??
          'A student';
      final title = assignment?.displayTitle ?? 'an assigned movement';
      final group = assignment?.groupName ?? 'your class';
      final submittedAt = attempt.submittedAt?.toUtc();
      // Activity Center records that a valid submission happened. Its current
      // review state may later become checked without erasing that history.
      if (attempt.isReviewFacingSubmission &&
          submittedAt != null &&
          !submittedAt.isBefore(cutoff)) {
        final isRetry = attempt.supersedesAttemptId != null;
        activities.add(
          _activity(
            id: '${isRetry ? 'retry_resubmission' : 'new_submission'}:${attempt.id}',
            type: isRetry
                ? TeacherActivityType.retryResubmission
                : TeacherActivityType.newSubmission,
            occurredAt: submittedAt,
            title: isRetry
                ? '$traineeName resubmitted $title'
                : '$traineeName submitted $title',
            description: isRetry
                ? 'A revised clip is ready for review in $group.'
                : 'A new clip is ready for review in $group.',
            destination: AppRoutePaths.teacherGroupClasswork(
              attempt.groupId,
              attempt.assignmentId,
              traineeId: attempt.traineeId,
            ),
            actorUserId: attempt.traineeId,
            actorDisplayName: traineeName,
          ),
        );
      }

      final completedAt = attempt.completedAt?.toUtc();
      if (!attempt.isTeacherReviewSubmission &&
          completedAt != null &&
          !completedAt.isBefore(cutoff)) {
        activities.add(
          _activity(
            id: 'movement_completed:${attempt.id}',
            type: TeacherActivityType.movementCompleted,
            occurredAt: completedAt,
            title: '$traineeName completed $title',
            description: 'Completed assigned practice in $group.',
            destination: AppRoutePaths.teacherGroupClasswork(
              attempt.groupId,
              attempt.assignmentId,
              traineeId: attempt.traineeId,
            ),
            actorUserId: attempt.traineeId,
            actorDisplayName: traineeName,
          ),
        );
      }
    }

    for (final conversation in _inbox) {
      if (!conversation.participants.containsKey(teacherId)) continue;
      final at = (conversation.lastMessageAt ?? conversation.updatedAt).toUtc();
      final senderId = conversation.lastMessageSenderId;
      if (conversation.unreadFor(teacherId) <= 0 ||
          senderId == null ||
          senderId == teacherId ||
          at.isBefore(cutoff)) {
        continue;
      }
      final sender = conversation.participants[senderId];
      final senderName = sender?.displayName.trim().isNotEmpty == true
          ? sender!.displayName
          : 'A student';
      final senderRole = sender?.isTeacher == true
          ? User.roleTeacher
          : User.roleTrainee;
      activities.add(
        _activity(
          id: 'message:${conversation.id}:${conversation.lastMessageId ?? at.millisecondsSinceEpoch}',
          type: TeacherActivityType.message,
          occurredAt: at,
          title: 'New message from $senderName',
          description: conversation.lastMessageBody?.trim().isNotEmpty == true
              ? conversation.lastMessageBody!.trim()
              : 'Open Messages to reply.',
          destination:
              '${AppRoutePaths.teacherMessages}?userId=${Uri.encodeComponent(senderId)}&name=${Uri.encodeComponent(senderName)}&role=${Uri.encodeComponent(senderRole)}',
          actorUserId: senderRole == User.roleTrainee ? senderId : null,
          actorDisplayName: senderRole == User.roleTrainee ? senderName : null,
        ),
      );
    }

    for (final assignment in _assignments) {
      if (assignment.teacherId != teacherId) continue;
      final dueAt = assignment.dueAt?.toUtc();
      if (!assignment.isActive || dueAt == null) continue;
      final windowEntry = dueAt.subtract(deadlineWindow);
      if (now.isBefore(windowEntry) || !now.isBefore(dueAt)) continue;
      activities.add(
        _activity(
          id: 'upcoming_deadline:${assignment.id}:${dueAt.millisecondsSinceEpoch}',
          type: TeacherActivityType.upcomingDeadline,
          occurredAt: windowEntry,
          title: '${assignment.displayTitle} is due soon',
          description:
              'Due in ${assignment.groupName} within the next 48 hours.',
          destination: AppRoutePaths.teacherGroupClasswork(
            assignment.groupId,
            assignment.id,
          ),
        ),
      );
    }

    activities.sort((a, b) {
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return activities;
  }

  GroupMembership? _membershipForTrainee(String traineeId, String teacherId) {
    for (final membership in _memberships) {
      if (membership.teacherId == teacherId &&
          membership.traineeId == traineeId) {
        return membership;
      }
    }
    return null;
  }

  TeacherActivity _activity({
    required String id,
    required TeacherActivityType type,
    required DateTime occurredAt,
    required String title,
    required String description,
    required String destination,
    String? actorUserId,
    String? actorDisplayName,
  }) => TeacherActivity(
    id: id,
    type: type,
    occurredAt: occurredAt,
    title: title,
    description: description,
    destination: destination,
    isRead: _readAtById.containsKey(id),
    actorUserId: actorUserId,
    actorDisplayName: actorDisplayName,
    actorProfilePictureUrl: actorUserId == null
        ? null
        : _profilePictureUrls[actorUserId],
  );

  StreamSubscription<List<T>>? _listenSafely<T>({
    required Stream<List<T>> Function() source,
    required int generation,
    required Completer<void> ready,
    required void Function(List<T> value) onData,
    required void Function(Object error) onError,
  }) {
    try {
      return source().listen(
        onData,
        onError: (Object error, StackTrace stackTrace) {
          _onStreamError(generation, ready, error, onError);
        },
      );
    } catch (error) {
      _onStreamError(generation, ready, error, onError);
      return null;
    }
  }

  void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _cancelSubscription(StreamSubscription<dynamic>? subscription) {
    if (subscription == null) return;
    unawaited(_cancelSubscriptionSafely(subscription));
  }

  Future<void> _cancelSubscriptionSafely(
    StreamSubscription<dynamic> subscription,
  ) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // A stale stream must not prevent the next teacher stream from starting.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _complete(_membershipsReady);
    _complete(_assignmentsReady);
    _complete(_attemptsReady);
    _complete(_inboxReady);
    _deadlineTimer?.cancel();
    _cancelSubscription(_membershipsSub);
    _cancelSubscription(_assignmentsSub);
    _cancelSubscription(_attemptsSub);
    _cancelSubscription(_inboxSub);
    _cancelProfileWatches();
    super.dispose();
  }
}
