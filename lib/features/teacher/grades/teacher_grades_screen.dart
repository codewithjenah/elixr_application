import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/chat_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../classwork/teacher_classwork_controller.dart';
import '../classwork/teacher_gradebook_pane.dart';
import '../groups/teacher_groups_controller.dart';

class TeacherGradesScreen extends StatefulWidget {
  const TeacherGradesScreen({super.key, this.initialGroupId});

  final String? initialGroupId;

  @override
  State<TeacherGradesScreen> createState() => _TeacherGradesScreenState();
}

class _TeacherGradesScreenState extends State<TeacherGradesScreen> {
  TeacherGroupsController? _groups;
  TeacherClassworkController? _classwork;
  int _bindGeneration = 0;
  String? _boundGroupId;
  String? _bindingGroupId;
  String? _failedGroupId;
  String? _seenRequest;
  String? _userSelectedGroupId;
  String? _dependencyError;
  bool _bindingInProgress = false;
  Future<void>? _bindFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final alreadyReady = _groups != null;
    _ensureGroupsController();
    final requested = _requestedGroupId();
    if (alreadyReady && requested == _seenRequest) return;
    _seenRequest = requested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_reconcileSelection());
    });
  }

  @override
  void dispose() {
    _groups?.removeListener(_onGroupsChanged);
    _classwork?.dispose();
    _groups?.dispose();
    super.dispose();
  }

  void _ensureGroupsController() {
    if (_groups != null || _dependencyError != null) return;
    AuthService? auth;
    try {
      auth = context.read<AuthService>();
    } on ProviderNotFoundException {
      _dependencyError = 'Sign in to view grades.';
      return;
    }
    final user = auth.currentUser;
    final teacherId = user?.id;
    final groups = _tryRead<GroupRepository>(context);
    if (user == null || teacherId == null || groups == null) {
      _dependencyError = user == null
          ? 'Sign in to view grades.'
          : 'Grades is not available right now.';
      return;
    }
    _groups = TeacherGroupsController(
      repository: groups,
      teacherId: teacherId,
      teacherDisplayName: user.fullName,
      ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
      publicProfileRepository: _tryRead<PublicProfileRepository>(context),
      watchAssignmentSummaries: false,
    )..addListener(_onGroupsChanged);
    unawaited(_groups!.start());
  }

  void _onGroupsChanged() {
    if (!mounted || _bindingInProgress) return;
    unawaited(_reconcileSelection());
  }

  @override
  void didUpdateWidget(TeacherGradesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroupId != widget.initialGroupId) {
      _seenRequest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_reconcileSelection());
      });
    }
  }

  String? _requestedGroupId() {
    final selected = _userSelectedGroupId?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    try {
      final value = GoRouterState.of(
        context,
      ).uri.queryParameters[AppRoutePaths.teacherGradesGroupQuery]?.trim();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    final fromWidget = widget.initialGroupId?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return null;
  }

  List<ElixrGroup> _accessibleClassrooms(TeacherGroupsController groups) {
    final items = [
      for (final group in groups.groups)
        if (group.teacherId == groups.teacherId) group,
    ];
    items.sort((a, b) {
      final created = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (created != 0) return created;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return items;
  }

  Future<void> _reconcileSelection() async {
    final groups = _groups;
    if (!mounted || groups == null) {
      if (mounted) setState(() {});
      return;
    }
    if (groups.loading && groups.groups.isEmpty) {
      setState(() {});
      return;
    }

    final accessible = _accessibleClassrooms(groups);
    if (_userSelectedGroupId != null &&
        !accessible.any((group) => group.id == _userSelectedGroupId)) {
      _userSelectedGroupId = null;
    }
    if (groups.errorMessage != null && accessible.isEmpty) {
      _disposeClasswork();
      setState(() {});
      return;
    }
    if (accessible.isEmpty) {
      _disposeClasswork();
      setState(() {});
      return;
    }

    final requested = _requestedGroupId();
    final String nextId;
    var shouldWriteRoute = false;
    if (requested != null) {
      nextId = requested;
    } else {
      nextId = accessible.first.id;
      shouldWriteRoute = true;
    }

    await _bindClassroom(nextId);
    if (!mounted) return;
    if (shouldWriteRoute &&
        _requestedGroupId() == null &&
        _boundGroupId == nextId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_requestedGroupId() != null) return;
        context.go(AppRoutePaths.teacherGradesForGroup(nextId));
      });
    }
  }

  Future<void> _bindClassroom(String groupId) {
    final groups = _groups;
    if (groups == null) return Future.value();
    if (_classwork != null &&
        _classwork!.groupId == groupId &&
        _boundGroupId == groupId) {
      return Future.value();
    }
    if (_bindingInProgress &&
        _bindingGroupId == groupId &&
        _bindFuture != null) {
      return _bindFuture!;
    }
    if (_failedGroupId == groupId &&
        _classwork == null &&
        groups.unauthorized) {
      return Future.value();
    }

    final generation = ++_bindGeneration;
    _bindingInProgress = true;
    _bindingGroupId = groupId;
    final future = _performBind(groupId, generation);
    _bindFuture = future;
    return future;
  }

  Future<void> _performBind(String groupId, int generation) async {
    final groups = _groups;
    if (groups == null) return;
    _disposeClasswork();
    if (mounted) setState(() {});

    try {
      // Let the previous classwork cancel its assignment stream so the next
      // controller can receive the in-memory repository's onListen snapshot.
      await Future<void>.value();
      await Future<void>.value();
      if (!mounted || generation != _bindGeneration) return;
      if (groups.selectedGroup?.id != groupId ||
          !groups.approvedMembershipsReady) {
        await groups.openGroupById(groupId);
      }
      if (!mounted || generation != _bindGeneration) return;
      if (groups.unauthorized || groups.selectedGroup?.id != groupId) {
        _failedGroupId = groupId;
        setState(() {});
        return;
      }
      _failedGroupId = null;

      final auth = _tryRead<AuthService>(context);
      final assignments = _tryRead<ClassroomAssignmentRepository>(context);
      final teacherId = auth?.currentUser?.id;
      if (auth == null ||
          teacherId == null ||
          assignments == null ||
          teacherId != groups.teacherId) {
        setState(() {});
        return;
      }

      final classwork = TeacherClassworkController(
        teacherId: teacherId,
        teacherDisplayName:
            auth.currentUser?.fullName ?? groups.teacherDisplayName,
        groupId: groupId,
        groupRepository: groups.repository,
        assignmentRepository: assignments,
        submissionRepository: _tryRead<AssignmentSubmissionRepository>(context),
        chatRepository: _tryRead<ChatRepository>(context),
        approvedMembershipsProvider: () => groups.approvedMemberships,
        approvedMembershipsListenable: groups,
        approvedMembershipsReady: () => groups.approvedMembershipsReady,
      );
      await classwork.start();
      if (!mounted || generation != _bindGeneration) {
        classwork.dispose();
        return;
      }
      _classwork = classwork;
      _boundGroupId = groupId;
      setState(() {});
    } finally {
      if (generation == _bindGeneration) {
        _bindingInProgress = false;
        _bindingGroupId = null;
        _bindFuture = null;
      }
    }
  }

  void _disposeClasswork() {
    _classwork?.dispose();
    _classwork = null;
    _boundGroupId = null;
  }

  T? _tryRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _selectClassroom(String groupId) {
    _userSelectedGroupId = groupId;
    final location = AppRoutePaths.teacherGradesForGroup(groupId);
    try {
      final current = GoRouterState.of(context).uri;
      if (current.path == AppRoutePaths.teacherGrades &&
          current.queryParameters[AppRoutePaths.teacherGradesGroupQuery] ==
              groupId) {
        unawaited(_bindClassroom(groupId));
        return;
      }
      // Route first so classroom switches reuse the same query-driven bind
      // path as a fresh Grades deep link.
      GoRouter.of(context).go(location);
    } catch (_) {
      unawaited(_bindClassroom(groupId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) {
      return TeacherScaffoldPage(
        header: const ElixEditorialPageHeader(
          heading: 'Grades',
          eyebrow: 'TEACHER WORKSPACE',
          subtitle: 'Review assignment grades for one classroom at a time.',
        ),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ElixStatusPanel(
              isError: _dependencyError != null,
              message: _dependencyError ?? 'Loading grades…',
              icon: _dependencyError == null ? null : FluentIcons.error,
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([groups, ?_classwork]),
      builder: (context, _) {
        final accessible = _accessibleClassrooms(groups);
        final selected = groups.selectedGroup;
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: 'Grades',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: selected == null
                ? 'Choose a classroom to review assignment grades.'
                : 'Review assignment grades for ${selected.name}.',
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accessible.isNotEmpty) ...[
                _ClassroomSelector(
                  classrooms: accessible,
                  selectedGroupId: selected?.id,
                  onChanged: _selectClassroom,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _GradesBody(
                groups: groups,
                classwork: _classwork,
                accessible: accessible,
                onRetryGroups: () => unawaited(groups.start()),
                onRetryClasswork: () => unawaited(_classwork?.start()),
                onOpenClassrooms: () => context.go(AppRoutePaths.teacherGroups),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassroomSelector extends StatelessWidget {
  const _ClassroomSelector({
    required this.classrooms,
    required this.selectedGroupId,
    required this.onChanged,
  });

  final List<ElixrGroup> classrooms;
  final String? selectedGroupId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = [
      for (final group in classrooms)
        if (group.id == selectedGroupId) group,
    ];
    final value = selected.isEmpty ? null : selected.first.id;
    final selectedGroup = selected.isEmpty ? null : selected.first;
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Classroom',
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: 320,
            child: ComboBox<String>(
              key: const Key('teacher_grades_classroom_selector'),
              value: value,
              isExpanded: true,
              placeholder: const Text('Choose a classroom'),
              items: [
                for (final group in classrooms)
                  ComboBoxItem<String>(
                    value: group.id,
                    child: Text(
                      group.isActive ? group.name : '${group.name} (Archived)',
                    ),
                  ),
              ],
              onChanged: (next) {
                if (next == null || next.isEmpty) return;
                onChanged(next);
              },
            ),
          ),
          if (selectedGroup != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              selectedGroup.isActive
                  ? 'Showing grades for this classroom only.'
                  : 'This classroom is archived. Existing grades remain available.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GradesBody extends StatelessWidget {
  const _GradesBody({
    required this.groups,
    required this.classwork,
    required this.accessible,
    required this.onRetryGroups,
    required this.onRetryClasswork,
    required this.onOpenClassrooms,
  });

  final TeacherGroupsController groups;
  final TeacherClassworkController? classwork;
  final List<ElixrGroup> accessible;
  final VoidCallback onRetryGroups;
  final VoidCallback onRetryClasswork;
  final VoidCallback onOpenClassrooms;

  @override
  Widget build(BuildContext context) {
    if (groups.loading && accessible.isEmpty && classwork == null) {
      return const SizedBox(height: 280, child: Center(child: ProgressRing()));
    }
    if (groups.errorMessage != null && accessible.isEmpty) {
      return ElixStatusPanel(
        key: const Key('teacher_grades_load_error'),
        isError: true,
        message: groups.errorMessage!,
        actionLabel: 'Retry',
        onAction: onRetryGroups,
      );
    }
    if (accessible.isEmpty) {
      return ElixStatusPanel(
        key: const Key('teacher_grades_no_classrooms'),
        title: 'No classrooms yet',
        message:
            'Open Classrooms to create a class, then come back here to review grades. Each classroom has its own gradebook.',
        actionLabel: 'Open Classrooms',
        onAction: onOpenClassrooms,
      );
    }
    if (groups.unauthorized) {
      return ElixStatusPanel(
        key: const Key('teacher_grades_unauthorized'),
        isError: true,
        message:
            groups.errorMessage ??
            'This class is not available. You can only open classes you teach.',
      );
    }
    final current = classwork;
    if (current == null) {
      return const SizedBox(height: 280, child: Center(child: ProgressRing()));
    }
    if (!current.loading &&
        current.errorMessage != null &&
        !current.unauthorized &&
        current.group == null) {
      return ElixStatusPanel(
        key: const Key('teacher_grades_classwork_error'),
        isError: true,
        message: current.errorMessage!,
        actionLabel: 'Retry',
        onAction: onRetryClasswork,
      );
    }
    return TeacherGradebookPane(
      key: Key('teacher_grades_gradebook_${current.groupId}'),
      controller: current,
      showHeading: false,
      profilePictureUrlFor: groups.profilePictureUrlFor,
      onOpenStudent: (membership) => context.push(
        AppRoutePaths.teacherStudentDetail(
          membership.traineeId,
          groupId: current.groupId,
        ),
      ),
      onOpenAssignment: (assignment) => context.push(
        AppRoutePaths.teacherGroupClasswork(current.groupId, assignment.id),
      ),
      onOpenCell: (assignment, traineeId) => context.push(
        AppRoutePaths.teacherGroupClasswork(
          current.groupId,
          assignment.id,
          traineeId: traineeId,
        ),
      ),
    );
  }
}
