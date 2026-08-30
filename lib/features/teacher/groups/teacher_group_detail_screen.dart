import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../../services/auth_service.dart';
import '../movements/teacher_assignment_composer.dart';
import '../../teacher_access/trainee_class_card.dart';
import 'teacher_groups_controller.dart';

class TeacherGroupDetailScreen extends StatefulWidget {
  const TeacherGroupDetailScreen({
    super.key,
    required this.groupId,
    this.controller,
    this.movementRepository,
  });

  final String groupId;
  final TeacherGroupsController? controller;
  final TeacherMovementRepository? movementRepository;

  @override
  State<TeacherGroupDetailScreen> createState() =>
      _TeacherGroupDetailScreenState();
}

class _TeacherGroupDetailScreenState extends State<TeacherGroupDetailScreen> {
  TeacherGroupsController? _owned;
  late final bool _ownsController;

  TeacherGroupsController? get _controller => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ownsController || _owned != null) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    PublicProfileRepository? publicProfileRepository;
    try {
      publicProfileRepository = context.read<PublicProfileRepository>();
    } on ProviderNotFoundException {
      publicProfileRepository = null;
    }
    ClassroomAssignmentRepository? assignmentRepository;
    try {
      assignmentRepository = context.read<ClassroomAssignmentRepository>();
    } on ProviderNotFoundException {
      assignmentRepository = null;
    }
    _owned = TeacherGroupsController(
      repository: context.read<GroupRepository>(),
      teacherId: userId,
      teacherDisplayName: user.fullName,
      ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
      publicProfileRepository: publicProfileRepository,
      assignmentRepository: assignmentRepository,
    )..startForGroup(widget.groupId);
  }

  @override
  void dispose() {
    if (_ownsController) {
      _owned?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Group',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final group = controller.selectedGroup;
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: group?.name ?? 'Group',
            eyebrow: 'TEACHER WORKSPACE',
            variant: ElixEditorialHeaderVariant.compact,
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  key: const Key('teacher_group_back'),
                  icon: const Icon(FluentIcons.back),
                  label: const Text('Back to groups'),
                  onPressed: () => context.go(AppRoutePaths.teacherGroups),
                ),
              ],
            ),
          ),
          content: _GroupDetailBody(
            controller: controller,
            movementRepository:
                widget.movementRepository ??
                _tryReadTeacherMovementRepository(context),
          ),
        );
      },
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({
    required this.controller,
    required this.movementRepository,
  });

  final TeacherGroupsController controller;
  final TeacherMovementRepository? movementRepository;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.unauthorized) {
      return ElixStatusPanel(
        key: const Key('teacher_group_unauthorized'),
        message:
            controller.errorMessage ??
            'This class is not available. You can only open classes you teach.',
        isError: true,
      );
    }
    if (controller.selectedGroup == null) {
      if (controller.errorMessage != null) {
        return ElixStatusPanel(
          message: controller.errorMessage!,
          isError: true,
        );
      }
      return const Center(child: ProgressRing());
    }

    final group = controller.selectedGroup!;
    final invite = controller.activeInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TraineeClassHeroBanner(
          groupId: group.id,
          title: group.name,
          subtitle: group.isActive ? 'Active' : 'Archived',
          subtitleIcon: group.isActive
              ? FluentIcons.completed
              : FluentIcons.archive,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(message: controller.errorMessage!, isError: true),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.actionMessage != null) ...[
          ElixStatusPanel(message: controller.actionMessage!),
          const SizedBox(height: AppSpacing.md),
        ],
        ElixPanelCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Button(
                    onPressed: controller.busy
                        ? null
                        : () => _showRenameDialog(context, controller, group),
                    child: const Text('Rename'),
                  ),
                  Button(
                    onPressed: controller.busy || !group.isActive
                        ? null
                        : () => _confirmArchive(context, controller),
                    child: const Text('Archive'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Join code for this class',
                style: AppTheme.headingMedium.copyWith(
                  fontSize: 16,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (invite == null)
                Text(
                  'No join code yet.',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                )
              else ...[
                SelectableText(
                  invite.displayCode,
                  key: const Key('teacher_group_invite_code'),
                  style: AppTheme.headingMedium.copyWith(
                    color: context.elixTextPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    Button(
                      key: const Key('teacher_group_copy_code'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: invite.displayCode),
                        );
                      },
                      child: const Text('Copy code'),
                    ),
                    Button(
                      onPressed: controller.busy
                          ? null
                          : () => _confirmRotateInvite(context, controller),
                      child: const Text('Make a new code'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _GroupDetailTabBar(
          key: const Key('teacher_group_detail_tabs'),
          selectedTab: controller.tab,
          onChanged: controller.setTab,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (controller.tab == TeacherGroupDetailTab.assignments)
          _AssignmentsSection(
            key: const Key('teacher_group_assignments_section'),
            group: group,
            assignments: controller.assignmentsFor(group.id),
            onCreateAssignment: group.isActive
                ? () => _showGroupAssignmentComposer(
                    context,
                    controller,
                    group,
                    movementRepository,
                  )
                : null,
            onEditAssignment: group.isActive && !controller.busy
                ? (assignment) =>
                      _showEditAssignmentDialog(context, controller, assignment)
                : null,
            onArchiveAssignment: group.isActive && !controller.busy
                ? (assignment) =>
                      _confirmArchiveAssignment(context, controller, assignment)
                : null,
          )
        else
          _StudentsSection(controller: controller),
      ],
    );
  }
}

class _GroupDetailTabBar extends StatelessWidget {
  const _GroupDetailTabBar({
    super.key,
    required this.selectedTab,
    required this.onChanged,
  });

  final TeacherGroupDetailTab selectedTab;
  final ValueChanged<TeacherGroupDetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _GroupDetailTab(
          key: const Key('teacher_group_tab_assignments'),
          label: 'Assignments',
          icon: FluentIcons.education,
          selected: selectedTab == TeacherGroupDetailTab.assignments,
          onPressed: () => onChanged(TeacherGroupDetailTab.assignments),
        ),
        _GroupDetailTab(
          key: const Key('teacher_group_tab_students'),
          label: 'Students',
          icon: FluentIcons.people,
          selected: selectedTab == TeacherGroupDetailTab.students,
          onPressed: () => onChanged(TeacherGroupDetailTab.students),
        ),
      ],
    );
  }
}

class _GroupDetailTab extends StatelessWidget {
  const _GroupDetailTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: HoverButton(
        onPressed: onPressed,
        cursor: SystemMouseCursors.click,
        builder: (context, states) {
          final hovered = states.isHovered;
          final foreground = selected ? Colors.white : context.elixTextPrimary;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? (highContrast ? AppColors.primary : null)
                  : Color.alphaBlend(
                      (hovered ? AppColors.primary : Colors.transparent)
                          .withValues(alpha: hovered ? 0.06 : 0),
                      context.elixCardSurface,
                    ),
              gradient: selected && !highContrast
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.accent],
                    )
                  : null,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? (highContrast ? context.elixBorder : Colors.transparent)
                    : context.elixBorder.withValues(
                        alpha: highContrast ? 1 : 0.9,
                      ),
                width: highContrast ? 2 : 1,
              ),
              boxShadow: selected && !highContrast
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StudentsSection extends StatelessWidget {
  const _StudentsSection({required this.controller});

  final TeacherGroupsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MembershipSection(
          key: const Key('teacher_group_pending_section'),
          title: 'Waiting to join',
          emptyMessage: 'No one is waiting to join this class.',
          memberships: controller.pendingMemberships,
          profilePictureUrlFor: controller.profilePictureUrlFor,
          builder: (membership) => Wrap(
            spacing: AppSpacing.sm,
            children: [
              ElixPrimaryButton(
                key: Key('teacher_group_approve_${membership.id}'),
                label: 'Approve',
                expanded: false,
                isLoading: controller.busy,
                onPressed: controller.busy
                    ? null
                    : () => controller.approveMembership(membership),
              ),
              Button(
                key: Key('teacher_group_reject_${membership.id}'),
                onPressed: controller.busy
                    ? null
                    : () => controller.rejectMembership(membership),
                child: const Text('Reject'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _MembershipSection(
          key: const Key('teacher_group_members_section'),
          title: 'Students in this class',
          emptyMessage: 'No students in this class yet.',
          memberships: controller.approvedMemberships,
          profilePictureUrlFor: controller.profilePictureUrlFor,
          builder: (membership) => Button(
            key: Key('teacher_group_remove_${membership.id}'),
            onPressed: controller.busy
                ? null
                : () => _confirmRemoveMember(context, controller, membership),
            child: const Text('Remove from class'),
          ),
        ),
      ],
    );
  }
}

class _AssignmentsSection extends StatelessWidget {
  const _AssignmentsSection({
    super.key,
    required this.group,
    required this.assignments,
    required this.onCreateAssignment,
    required this.onEditAssignment,
    required this.onArchiveAssignment,
  });

  final ElixrGroup group;
  final List<GroupAssignment> assignments;
  final VoidCallback? onCreateAssignment;
  final ValueChanged<GroupAssignment>? onEditAssignment;
  final ValueChanged<GroupAssignment>? onArchiveAssignment;

  @override
  Widget build(BuildContext context) {
    final sortedAssignments = [...assignments]..sort(_compareAssignments);
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assignments',
                    style: AppTheme.headingMedium.copyWith(
                      fontSize: 16,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Practice assigned to this class.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
              ElixPrimaryButton(
                key: const Key('teacher_group_create_assignment'),
                label: 'New assignment',
                icon: FluentIcons.add,
                expanded: false,
                dense: true,
                onPressed: onCreateAssignment,
              ),
            ],
          ),
          if (!group.isActive) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This class is archived. New assignments cannot be created, but historical assignments remain visible.',
              key: const Key('teacher_group_archived_assignments_message'),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (sortedAssignments.isEmpty)
            Column(
              key: const Key('teacher_group_assignments_empty'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No assignments yet.',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                if (group.isActive) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Use New assignment to send an existing movement to this class.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sortedAssignments.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _AssignmentPreview(
                    key: Key(
                      'teacher_group_assignment_${sortedAssignments[i].id}',
                    ),
                    assignment: sortedAssignments[i],
                    onEdit: sortedAssignments[i].isActive
                        ? () => onEditAssignment?.call(sortedAssignments[i])
                        : null,
                    onArchive: sortedAssignments[i].isActive
                        ? () => onArchiveAssignment?.call(sortedAssignments[i])
                        : null,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  int _compareAssignments(GroupAssignment a, GroupAssignment b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    final aTimestamp = a.updatedAt ?? a.createdAt;
    final bTimestamp = b.updatedAt ?? b.createdAt;
    if (aTimestamp == null && bTimestamp != null) return 1;
    if (aTimestamp != null && bTimestamp == null) return -1;
    if (aTimestamp == null || bTimestamp == null) return 0;
    return bTimestamp.compareTo(aTimestamp);
  }
}

class _AssignmentPreview extends StatelessWidget {
  const _AssignmentPreview({
    super.key,
    required this.assignment,
    required this.onEdit,
    required this.onArchive,
  });

  final GroupAssignment assignment;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final statusColor = assignment.isActive
        ? context.elixColors.success
        : context.elixTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assignment.displayTitle,
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${assignment.origin.displayLabel}${assignment.dueAt == null ? '' : ' · ${_formatDue(assignment.dueAt!)}'}',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ElixPill(
            text: assignment.isActive ? 'Active' : 'Archived',
            color: statusColor,
            compact: true,
          ),
          if (assignment.isActive) ...[
            const SizedBox(width: AppSpacing.sm),
            Button(
              key: Key('teacher_group_edit_assignment_${assignment.id}'),
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
            const SizedBox(width: AppSpacing.xs),
            Button(
              key: Key('teacher_group_archive_assignment_${assignment.id}'),
              onPressed: onArchive,
              child: const Text('Archive'),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDue(DateTime dueAt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final manila = dueAt.toUtc().add(const Duration(hours: 8));
    return 'Due ${months[manila.month - 1]} ${manila.day}, ${manila.year}';
  }
}

class _MembershipSection extends StatelessWidget {
  const _MembershipSection({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.memberships,
    required this.profilePictureUrlFor,
    required this.builder,
  });

  final String title;
  final String emptyMessage;
  final List<GroupMembership> memberships;
  final String? Function(String traineeId) profilePictureUrlFor;
  final Widget Function(GroupMembership membership) builder;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (memberships.isEmpty)
            Text(
              emptyMessage,
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else
            for (final membership in memberships) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ProfileAvatarWidget(
                    key: Key('teacher_group_member_avatar_${membership.id}'),
                    radius: 18,
                    showBorder: false,
                    initials: userInitials(membership.traineeDisplayName),
                    networkImageUrl: profilePictureUrlFor(membership.traineeId),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          membership.traineeDisplayName,
                          style: AppTheme.body.copyWith(
                            color: context.elixTextPrimary,
                          ),
                        ),
                        Text(
                          membership.isPending
                              ? 'Wants to join'
                              : 'In this class',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  builder(membership),
                ],
              ),
              if (membership != memberships.last)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(),
                ),
            ],
        ],
      ),
    );
  }
}

TeacherMovementRepository? _tryReadTeacherMovementRepository(
  BuildContext context,
) {
  try {
    return context.read<TeacherMovementRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

Future<void> _showGroupAssignmentComposer(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
  TeacherMovementRepository? movementRepository,
) async {
  final currentGroup = controller.selectedGroup;
  if (currentGroup == null ||
      currentGroup.id != group.id ||
      !currentGroup.isActive) {
    return;
  }

  final assignmentRepository = controller.assignmentRepository;
  if (assignmentRepository == null) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('Assignments unavailable'),
        content: const Text(
          'Assignments could not be connected for this classroom right now.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  Future<bool> Function()? ensureTeacherAuthorization;
  try {
    ensureTeacherAuthorization = context
        .read<AuthService>()
        .ensureTeacherAuthorizationFresh;
  } on ProviderNotFoundException {
    ensureTeacherAuthorization = null;
  }

  final service = TeacherAssignmentCreationService(
    teacherId: controller.teacherId,
    teacherDisplayName: controller.teacherDisplayName,
    assignmentRepository: assignmentRepository,
    movementRepository: movementRepository,
    ensureTeacherAuthorization: ensureTeacherAuthorization,
  );
  await showTeacherAssignmentComposer(
    context,
    teacherId: controller.teacherId,
    teacherDisplayName: controller.teacherDisplayName,
    groups: [currentGroup],
    movementRepository: movementRepository,
    assignmentRepository: assignmentRepository,
    creationService: service,
    lockedGroup: currentGroup,
  );
}

Future<void> _showEditAssignmentDialog(
  BuildContext context,
  TeacherGroupsController controller,
  GroupAssignment assignment,
) async {
  final initialScore = assignment.maxScore?.toString() ?? '';
  final scoreController = TextEditingController(text: initialScore);
  var dueAt = assignment.dueAt;
  var hasDueDate = dueAt != null;
  String? validationMessage;

  final settings = await showDialog<_AssignmentSettings>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: Text('Edit ${assignment.displayTitle}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update the deadline${assignment.isTeacherCreated ? ' and maximum score' : ''}.',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Checkbox(
                key: const Key('teacher_assignment_edit_due_date_toggle'),
                checked: hasDueDate,
                content: const Text('Set a due date'),
                onChanged: (value) {
                  setDialogState(() {
                    hasDueDate = value ?? false;
                    dueAt ??= DateTime.now().add(const Duration(days: 7));
                  });
                },
              ),
              if (hasDueDate) ...[
                const SizedBox(height: AppSpacing.sm),
                DatePicker(
                  key: const Key('teacher_assignment_edit_due_date'),
                  selected: dueAt ?? DateTime.now(),
                  onChanged: (value) => setDialogState(() => dueAt = value),
                ),
              ],
              if (assignment.isTeacherCreated) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Maximum score (1–100)',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextBox(
                  key: const Key('teacher_assignment_edit_max_score'),
                  controller: scoreController,
                  enabled: !assignment.gradingLocked,
                  keyboardType: TextInputType.number,
                ),
                if (assignment.gradingLocked) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The score is locked because this assignment already has a checked submission.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
              if (validationMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  validationMessage!,
                  key: const Key('teacher_assignment_edit_validation'),
                  style: AppTheme.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('teacher_assignment_save_changes'),
            onPressed: () {
              final maxScore =
                  assignment.isTeacherCreated && !assignment.gradingLocked
                  ? int.tryParse(scoreController.text.trim())
                  : null;
              if (assignment.isTeacherCreated &&
                  !assignment.gradingLocked &&
                  (maxScore == null || maxScore < 1 || maxScore > 100)) {
                setDialogState(() {
                  validationMessage = 'Enter a maximum score from 1 to 100.';
                });
                return;
              }
              Navigator.pop(
                dialogContext,
                _AssignmentSettings(
                  dueAt: hasDueDate ? dueAt : null,
                  maxScore: maxScore,
                ),
              );
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    ),
  );
  scoreController.dispose();
  if (settings == null) return;
  await controller.updateAssignmentSettings(
    assignment,
    dueAt: settings.dueAt,
    maxScore: settings.maxScore,
  );
}

Future<void> _confirmArchiveAssignment(
  BuildContext context,
  TeacherGroupsController controller,
  GroupAssignment assignment,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: const Text('Archive this assignment?'),
      content: const Text(
        'It will no longer be available for new trainee submissions. Existing records stay available for review.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('teacher_assignment_confirm_archive'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Archive assignment'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.archiveAssignment(assignment);
  }
}

class _AssignmentSettings {
  const _AssignmentSettings({required this.dueAt, required this.maxScore});

  final DateTime? dueAt;
  final int? maxScore;
}

Future<void> _showRenameDialog(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final nameController = TextEditingController(text: group.name);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Rename group'),
      content: TextBox(controller: nameController, autofocus: true),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Save'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.renameSelectedGroup(nameController.text);
  }
  nameController.dispose();
}

Future<void> _confirmArchive(
  BuildContext context,
  TeacherGroupsController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Archive this group?'),
      content: const Text(
        'Students already in this class stay. New students will not be able '
        'to join with this class code.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Archive'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted != true) return;
  await controller.archiveSelectedGroup();
  if (controller.selectedGroup == null &&
      controller.errorMessage == null &&
      context.mounted) {
    context.go(AppRoutePaths.teacherGroups);
  }
}

Future<void> _confirmRotateInvite(
  BuildContext context,
  TeacherGroupsController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Make a new class code?'),
      content: const Text(
        'The old code will stop working. Share the new code with students '
        'who still need to join.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Make a new code'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.rotateInvite();
}

Future<void> _confirmRemoveMember(
  BuildContext context,
  TeacherGroupsController controller,
  GroupMembership membership,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text('Remove ${membership.traineeDisplayName}?'),
      content: const Text(
        'This student will leave the class. They can join again later with '
        'the class code.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Remove from class'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.removeMembership(membership);
}
