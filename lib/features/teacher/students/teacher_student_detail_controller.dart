import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/public_profile.dart';
import '../../../data/repositories/public_profile_repository.dart';

enum TeacherStudentDetailState {
  loadingClassroom,
  unauthorized,
  pending,
  relationshipRemoved,
  waitingForAccess,
  loadingProgress,
  ready,
  empty,
  accessWithdrawn,
  connectionRequired,
  error,
}

class TeacherStudentDetailController extends ChangeNotifier {
  TeacherStudentDetailController({
    required this.groupRepository,
    required this.relationshipRepository,
    required this.progressRepository,
    required this.publicProfileRepository,
    required this.teacherId,
    required this.traineeId,
    this.preferredGroupId,
  });

  final GroupRepository groupRepository;
  final TeacherRelationshipRepository relationshipRepository;
  final TeacherProgressRepository progressRepository;
  final PublicProfileRepository publicProfileRepository;
  final String teacherId;
  final String traineeId;
  final String? preferredGroupId;

  TeacherStudentDetailState state = TeacherStudentDetailState.loadingClassroom;
  List<GroupMembership> classroomMemberships = const [];
  List<GroupMembership> approvedMemberships = const [];
  List<ElixrGroup> teacherGroups = const [];
  String? selectedGroupId;
  TeacherStudentLink? link;
  PublicProfile? profileRoot;
  PublicProfileSummary? summary;
  List<PublicProfileSession> sessions = const [];
  TeacherProgressCursor? _cursor;
  bool hasMore = false;
  bool loadingMore = false;
  Object? paginationError;
  String? errorMessage;

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<TeacherStudentLink>>? _linksSub;
  StreamSubscription<PublicProfile?>? _profileSub;
  StreamSubscription<PublicProfileSummary?>? _summarySub;

  int _classroomEpoch = 0;
  int _accessEpoch = 0;
  int _dataEpoch = 0;
  int _pageEpoch = 0;
  bool _hadEffectiveAccess = false;
  bool _firstSummarySettled = false;
  bool _firstPageSettled = false;
  bool _teacherGroupsLoaded = false;
  bool _disposed = false;

  bool get hasClassroomAuthorization => approvedMemberships.isNotEmpty;

  /// Human-readable group name from Teacher group metadata, never the document ID.
  String? groupNameForId(String groupId) {
    for (final group in teacherGroups) {
      if (group.id != groupId) continue;
      final name = group.name.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  String? get selectedGroupName {
    final groupId = selectedGroupId;
    if (groupId == null) return null;
    return groupNameForId(groupId);
  }

  /// ComboBox label that never falls back to a Firestore document ID.
  String displayNameForGroupId(String groupId) {
    return groupNameForId(groupId) ?? 'Group name unavailable';
  }

  /// Classroom caption that omits the raw group ID when metadata is missing.
  String? get classroomGroupCaption {
    if (selectedGroupId == null) return null;
    final name = selectedGroupName;
    if (name != null) return 'Classroom group: $name';
    if (!_teacherGroupsLoaded) return 'Classroom group';
    return 'Group name unavailable';
  }

  bool get isPrivateProfile =>
      profileRoot?.visibility == ProfileVisibility.private;

  String get displayName {
    if (profileRoot != null && profileRoot!.displayName.isNotEmpty) {
      return profileRoot!.displayName;
    }
    if (approvedMemberships.isNotEmpty) {
      return approvedMemberships.first.traineeDisplayName;
    }
    if (classroomMemberships.isNotEmpty) {
      return classroomMemberships.first.traineeDisplayName;
    }
    return 'Student';
  }

  Future<void> start() async {
    final epoch = ++_classroomEpoch;
    ++_accessEpoch;
    _dataEpoch++;
    _pageEpoch++;
    await _cancelAll();
    _resetProtected(TeacherStudentDetailState.loadingClassroom);
    classroomMemberships = const [];
    approvedMemberships = const [];
    teacherGroups = const [];
    _teacherGroupsLoaded = false;
    link = null;
    profileRoot = null;
    selectedGroupId = preferredGroupId;
    if (_disposed || epoch != _classroomEpoch) return;

    _groupsSub = groupRepository
        .watchTeacherGroups(teacherId: teacherId)
        .listen(
          (groups) => _onTeacherGroups(groups, epoch),
          onError: (_) {
            if (!_isCurrentClassroom(epoch)) return;
            _teacherGroupsLoaded = true;
            if (!_disposed) notifyListeners();
          },
        );
    _membershipsSub = groupRepository
        .watchTeacherMemberships(teacherId: teacherId)
        .listen(
          (all) => _onMemberships(all, epoch),
          onError: (_) {
            if (!_isCurrentClassroom(epoch)) return;
            _resetProtected(TeacherStudentDetailState.connectionRequired);
          },
        );
  }

  void _onTeacherGroups(List<ElixrGroup> groups, int epoch) {
    if (!_isCurrentClassroom(epoch)) return;
    teacherGroups = groups;
    _teacherGroupsLoaded = true;
    notifyListeners();
  }

  void _onMemberships(List<GroupMembership> all, int epoch) {
    if (!_isCurrentClassroom(epoch)) return;
    final mine = all.where((m) => m.traineeId == traineeId).toList();
    classroomMemberships = mine;
    approvedMemberships = mine.where((m) => m.isApproved).toList();

    if (mine.isEmpty) {
      return _resetProtected(TeacherStudentDetailState.unauthorized);
    }
    if (approvedMemberships.isEmpty) {
      if (mine.any((m) => m.isPending)) {
        return _resetProtected(TeacherStudentDetailState.pending);
      }
      return _resetProtected(TeacherStudentDetailState.relationshipRemoved);
    }

    _ensureSelectedGroup();
    _watchProfile(epoch);
    _watchLinks(epoch);
  }

  void _ensureSelectedGroup() {
    final approvedIds = approvedMemberships.map((m) => m.groupId).toSet();
    if (selectedGroupId != null && approvedIds.contains(selectedGroupId)) {
      return;
    }
    selectedGroupId = approvedMemberships.first.groupId;
  }

  void setSelectedGroupId(String groupId) {
    if (!approvedMemberships.any((m) => m.groupId == groupId)) return;
    selectedGroupId = groupId;
    notifyListeners();
  }

  void _watchProfile(int classroomEpoch) {
    _profileSub?.cancel();
    _profileSub = publicProfileRepository.watchProfileRoot(traineeId).listen((
      value,
    ) {
      if (!_isCurrentClassroom(classroomEpoch)) return;
      profileRoot = value;
      notifyListeners();
    }, onError: (_) {});
  }

  void _watchLinks(int classroomEpoch) {
    final accessEpoch = ++_accessEpoch;
    _linksSub?.cancel();
    _summarySub?.cancel();
    _summarySub = null;
    link = null;
    _hadEffectiveAccess = false;
    _linksSub = relationshipRepository
        .watchTeacherLinks(teacherId: teacherId)
        .listen(
          (links) => _onLinks(links, classroomEpoch, accessEpoch),
          onError: (_) {
            if (!_isCurrentClassroom(classroomEpoch)) return;
            _resetProtected(TeacherStudentDetailState.connectionRequired);
          },
        );
  }

  void _onLinks(
    List<TeacherStudentLink> links,
    int classroomEpoch,
    int accessEpoch,
  ) {
    if (!_isCurrentClassroom(classroomEpoch) || accessEpoch != _accessEpoch) {
      return;
    }
    TeacherStudentLink? current;
    for (final item in links) {
      if (item.traineeId == traineeId) {
        current = item;
        break;
      }
    }
    link = current;
    if (!hasClassroomAuthorization) {
      return _resetProtected(TeacherStudentDetailState.unauthorized);
    }
    if (current == null ||
        !current.isApproved ||
        !current.hasEffectiveProgressAccess) {
      return _clearProgress(
        current != null &&
                current.isApproved &&
                _hadEffectiveAccess &&
                !current.hasEffectiveProgressAccess
            ? TeacherStudentDetailState.accessWithdrawn
            : TeacherStudentDetailState.waitingForAccess,
      );
    }
    _hadEffectiveAccess = true;
    if (_summarySub == null) {
      _beginProgress(classroomEpoch, accessEpoch);
    }
  }

  void _beginProgress(int classroomEpoch, int accessEpoch) {
    if (!_isCurrentClassroom(classroomEpoch) || accessEpoch != _accessEpoch) {
      return;
    }
    final dataEpoch = ++_dataEpoch;
    final pageEpoch = ++_pageEpoch;
    state = TeacherStudentDetailState.loadingProgress;
    _firstSummarySettled = false;
    _firstPageSettled = false;
    sessions = const [];
    summary = null;
    _cursor = null;
    hasMore = false;
    paginationError = null;
    notifyListeners();

    _summarySub = progressRepository
        .watchSummary(traineeId)
        .listen(
          (value) {
            if (!_isCurrentData(classroomEpoch, accessEpoch, dataEpoch)) return;
            summary = value;
            _firstSummarySettled = true;
            _setStateFromData();
          },
          onError: (Object error) {
            if (!_isCurrentData(classroomEpoch, accessEpoch, dataEpoch)) return;
            final next =
                error is TeacherProgressException &&
                    error.code == TeacherProgressError.accessWithdrawn
                ? TeacherStudentDetailState.accessWithdrawn
                : TeacherStudentDetailState.error;
            _clearProgress(next);
          },
        );
    _loadPage(
      classroomEpoch,
      accessEpoch,
      dataEpoch,
      pageEpoch,
      firstPage: true,
    );
  }

  Future<void> loadMore() async {
    if (loadingMore ||
        !hasMore ||
        state == TeacherStudentDetailState.loadingProgress ||
        link?.hasEffectiveProgressAccess != true ||
        !hasClassroomAuthorization) {
      return;
    }
    await _loadPage(_classroomEpoch, _accessEpoch, _dataEpoch, ++_pageEpoch);
  }

  Future<void> retryLoadMore() => loadMore();

  Future<void> refresh() => start();

  Future<void> _loadPage(
    int classroomEpoch,
    int accessEpoch,
    int dataEpoch,
    int pageEpoch, {
    bool firstPage = false,
  }) async {
    loadingMore = true;
    if (!firstPage) paginationError = null;
    notifyListeners();
    try {
      final page = await progressRepository.fetchSessionsPage(
        traineeId: traineeId,
        startAfter: _cursor,
      );
      if (!_isCurrent(classroomEpoch, accessEpoch, dataEpoch, pageEpoch))
        return;
      final known = sessions.map((item) => item.sessionId).toSet();
      sessions = [
        ...sessions,
        ...page.sessions.where((item) => known.add(item.sessionId)),
      ];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      _firstPageSettled = true;
      _setStateFromData();
    } on TeacherProgressException catch (error) {
      if (!_isCurrent(classroomEpoch, accessEpoch, dataEpoch, pageEpoch))
        return;
      if (error.code == TeacherProgressError.accessWithdrawn) {
        _clearProgress(TeacherStudentDetailState.accessWithdrawn);
      } else if (firstPage) {
        _clearProgress(TeacherStudentDetailState.error);
      } else {
        paginationError = error;
      }
    } catch (error) {
      if (!_isCurrent(classroomEpoch, accessEpoch, dataEpoch, pageEpoch))
        return;
      if (firstPage) {
        _clearProgress(TeacherStudentDetailState.error);
      } else {
        paginationError = error;
      }
    } finally {
      if (_isCurrent(classroomEpoch, accessEpoch, dataEpoch, pageEpoch)) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentClassroom(int epoch) => !_disposed && epoch == _classroomEpoch;
  bool _isCurrentData(int classroomEpoch, int accessEpoch, int dataEpoch) =>
      _isCurrentClassroom(classroomEpoch) &&
      accessEpoch == _accessEpoch &&
      dataEpoch == _dataEpoch;
  bool _isCurrent(
    int classroomEpoch,
    int accessEpoch,
    int dataEpoch,
    int pageEpoch,
  ) =>
      _isCurrentData(classroomEpoch, accessEpoch, dataEpoch) &&
      pageEpoch == _pageEpoch;

  void _setStateFromData() {
    if (!_firstSummarySettled || !_firstPageSettled) return;
    final noSummary =
        summary == null ||
        (summary!.totalDurationSeconds == 0 &&
            summary!.completedMovementNames.isEmpty);
    state = sessions.isEmpty && noSummary
        ? TeacherStudentDetailState.empty
        : TeacherStudentDetailState.ready;
    notifyListeners();
  }

  void _clearProgress(TeacherStudentDetailState next) {
    _dataEpoch++;
    _pageEpoch++;
    _summarySub?.cancel();
    _summarySub = null;
    summary = null;
    sessions = const [];
    _cursor = null;
    hasMore = false;
    loadingMore = false;
    paginationError = null;
    _firstSummarySettled = false;
    _firstPageSettled = false;
    state = next;
    if (!_disposed) notifyListeners();
  }

  void _resetProtected(TeacherStudentDetailState next) {
    _accessEpoch++;
    _dataEpoch++;
    _pageEpoch++;
    _summarySub?.cancel();
    _summarySub = null;
    _linksSub?.cancel();
    _linksSub = null;
    link = null;
    summary = null;
    sessions = const [];
    _cursor = null;
    hasMore = false;
    loadingMore = false;
    paginationError = null;
    _firstSummarySettled = false;
    _firstPageSettled = false;
    state = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> _cancelAll() async {
    await _membershipsSub?.cancel();
    await _groupsSub?.cancel();
    await _linksSub?.cancel();
    await _profileSub?.cancel();
    await _summarySub?.cancel();
    _membershipsSub = null;
    _groupsSub = null;
    _linksSub = null;
    _profileSub = null;
    _summarySub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _classroomEpoch++;
    _accessEpoch++;
    unawaited(_cancelAll());
    super.dispose();
  }
}
