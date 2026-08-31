import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/chat_repository.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
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
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../../services/auth_service.dart';
import '../classwork/teacher_classwork_controller.dart';
import '../classwork/teacher_classwork_pane.dart';
import '../movements/teacher_assignment_composer.dart';
import '../../teacher_access/trainee_class_card.dart';
import '../../classroom_announcements/classroom_announcements_controller.dart';
import '../../classroom_announcements/classroom_announcements_pane.dart';
import 'teacher_groups_controller.dart';

class TeacherGroupDetailScreen extends StatefulWidget {
  const TeacherGroupDetailScreen({
    super.key,
    required this.groupId,
    this.controller,
    this.classworkController,
    this.announcementsController,
    this.movementRepository,
    this.initialAssignmentId,
    this.initialTraineeId,
  });

  final String groupId;
  final TeacherGroupsController? controller;
  final TeacherClassworkController? classworkController;
  final ClassroomAnnouncementsController? announcementsController;
  final TeacherMovementRepository? movementRepository;
  final String? initialAssignmentId;
  final String? initialTraineeId;

  @override
  State<TeacherGroupDetailScreen> createState() =>
      _TeacherGroupDetailScreenState();
}

class _TeacherGroupDetailScreenState extends State<TeacherGroupDetailScreen> {
  TeacherGroupsController? _owned;
  TeacherClassworkController? _ownedClasswork;
  ClassroomAnnouncementsController? _ownedAnnouncements;
  late final bool _ownsController;
  late final bool _ownsClassworkController;

  TeacherGroupsController? get _controller => widget.controller ?? _owned;
  TeacherClassworkController? get _classworkController =>
      widget.classworkController ?? _ownedClasswork;
  ClassroomAnnouncementsController? get _announcementsController =>
      widget.announcementsController ?? _ownedAnnouncements;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsClassworkController = widget.classworkController == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final suppliedController = widget.controller;
    final suppliedAssignments = suppliedController?.assignmentRepository;
    if (_ownsClassworkController &&
        _ownedClasswork == null &&
        suppliedController != null &&
        suppliedAssignments != null) {
      _ownedClasswork = TeacherClassworkController(
        teacherId: suppliedController.teacherId,
        teacherDisplayName: suppliedController.teacherDisplayName,
        groupId: widget.groupId,
        groupRepository: suppliedController.repository,
        assignmentRepository: suppliedAssignments,
        submissionRepository: _tryRead<AssignmentSubmissionRepository>(context),
        chatRepository: _tryRead<ChatRepository>(context),
        initialAssignmentId: widget.initialAssignmentId,
        initialTraineeId: widget.initialTraineeId,
        approvedMembershipsProvider: () =>
            suppliedController.approvedMemberships,
        approvedMembershipsListenable: suppliedController,
      )..start();
    }
    AuthService? auth;
    try {
      auth = context.read<AuthService>();
    } on ProviderNotFoundException {
      return;
    }
    final user = auth.currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    PublicProfileRepository? publicProfileRepository;
    try {
      publicProfileRepository = context.read<PublicProfileRepository>();
    } on ProviderNotFoundException {
      publicProfileRepository = null;
    }
    if (_ownsController && _owned == null) {
      _owned = TeacherGroupsController(
        repository: context.read<GroupRepository>(),
        teacherId: userId,
        teacherDisplayName: user.fullName,
        ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
        publicProfileRepository: publicProfileRepository,
      )..startForGroup(widget.groupId);
    }
    if (_ownsClassworkController && _ownedClasswork == null) {
      final assignments = context.read<ClassroomAssignmentRepository>();
      final groupsController = _owned;
      if (groupsController == null) return;
      _ownedClasswork = TeacherClassworkController(
        teacherId: userId,
        teacherDisplayName: user.fullName,
        groupId: widget.groupId,
        groupRepository: context.read<GroupRepository>(),
        assignmentRepository: assignments,
        submissionRepository: _tryRead<AssignmentSubmissionRepository>(context),
        chatRepository: _tryRead<ChatRepository>(context),
        initialAssignmentId: widget.initialAssignmentId,
        initialTraineeId: widget.initialTraineeId,
        approvedMembershipsProvider: () => groupsController.approvedMemberships,
        approvedMembershipsListenable: groupsController,
      )..start();
    }
    if (_ownedAnnouncements == null && widget.announcementsController == null) {
      final announcements = _tryRead<ClassroomAnnouncementRepository>(context);
      if (announcements != null) {
        _ownedAnnouncements = ClassroomAnnouncementsController(
          repository: announcements,
          groupId: widget.groupId,
          currentUserId: userId,
          canManage: true,
          isGroupActive: () => _controller?.selectedGroup?.isActive == true,
          ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
        )..start();
      }
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _owned?.dispose();
    }
    if (_ownsClassworkController) {
      _ownedClasswork?.dispose();
    }
    _ownedAnnouncements?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final classwork = _classworkController;
    if (controller == null || classwork == null) {
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
      animation: Listenable.merge([
        controller,
        classwork,
        ?_announcementsController,
      ]),
      builder: (context, _) {
        final group = controller.selectedGroup;
        final assignment = classwork.selectedAssignment;
        final traineeId = classwork.selectedTraineeId;
        final backButton = traineeId != null && assignment != null
            ? ElixBackButton(
                key: const Key('teacher_classwork_back_to_roster'),
                label: 'Student roster',
                tooltip: 'Back to student roster',
                semanticLabel: 'Back to student roster',
                onPressed: () async {
                  await classwork.selectTrainee(null);
                  if (!context.mounted) return;
                  context.go(
                    AppRoutePaths.teacherGroupClasswork(
                      widget.groupId,
                      assignment.id,
                    ),
                  );
                },
              )
            : assignment != null
            ? ElixBackButton(
                key: const Key('teacher_classwork_back'),
                label: 'Classwork',
                tooltip: 'Back to classwork',
                semanticLabel: 'Back to classwork',
                onPressed: () async {
                  await classwork.selectAssignment(null);
                  if (!context.mounted) return;
                  context.go(AppRoutePaths.teacherGroup(widget.groupId));
                },
              )
            : ElixBackButton(
                key: const Key('teacher_group_back'),
                label: 'Classrooms',
                tooltip: 'Back to classrooms',
                semanticLabel: 'Back to classrooms',
                onPressed: () => context.go(AppRoutePaths.teacherGroups),
              );
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: group?.name ?? 'Group',
            eyebrow: 'TEACHER WORKSPACE',
            variant: ElixEditorialHeaderVariant.compact,
          ),
          // The classroom overview uses the page scroll view so its desktop
          // scrollbar sits at the outer content edge. Assignment work owns a
          // bounded scroll view to keep its roster/review layout stable.
          scrollable: assignment == null,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              backButton,
              const SizedBox(height: AppSpacing.md),
              if (assignment == null)
                _GroupDetailBody(
                  controller: controller,
                  classworkController: classwork,
                  announcementsController: _announcementsController,
                  movementRepository:
                      widget.movementRepository ??
                      _tryReadTeacherMovementRepository(context),
                )
              else
                Expanded(
                  child: TeacherAssignmentWorkPane(
                    controller: classwork,
                    profilePictureUrlFor: controller.profilePictureUrlFor,
                    onOpenTrainee: (selectedTraineeId) async {
                      await classwork.selectTrainee(selectedTraineeId);
                      if (!context.mounted) return;
                      context.go(
                        AppRoutePaths.teacherGroupClasswork(
                          widget.groupId,
                          assignment.id,
                          traineeId: selectedTraineeId,
                        ),
                      );
                    },
                    onEditAssignment:
                        group?.isActive == true && assignment.isActive
                        ? (selectedAssignment) => _showEditAssignmentDialog(
                            context,
                            classwork,
                            selectedAssignment,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({
    required this.controller,
    required this.classworkController,
    required this.announcementsController,
    required this.movementRepository,
  });

  final TeacherGroupsController controller;
  final TeacherClassworkController classworkController;
  final ClassroomAnnouncementsController? announcementsController;
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
        if (controller.tab == TeacherGroupDetailTab.classwork)
          TeacherClassworkAssignmentList(
            key: const Key('teacher_group_assignments_section'),
            controller: classworkController,
            onOpen: (assignment) => context.go(
              AppRoutePaths.teacherGroupClasswork(group.id, assignment.id),
            ),
            onCreate: group.isActive
                ? () => _showGroupAssignmentComposer(
                    context,
                    controller,
                    classworkController,
                    group,
                    movementRepository,
                  )
                : null,
            onEdit: group.isActive && !classworkController.busy
                ? (assignment) => _showEditAssignmentDialog(
                    context,
                    classworkController,
                    assignment,
                  )
                : null,
            onArchive: group.isActive && !classworkController.busy
                ? (assignment) => _confirmArchiveAssignment(
                    context,
                    classworkController,
                    assignment,
                  )
                : null,
          )
        else if (controller.tab == TeacherGroupDetailTab.announcements)
          announcementsController == null
              ? const ElixStatusPanel(
                  message: 'Announcements are not available right now.',
                  isError: true,
                )
              : ClassroomAnnouncementsPane(
                  controller: announcementsController!,
                  teacherDisplayName: controller.teacherDisplayName,
                  canManage: true,
                  groupIsActive: group.isActive,
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
          key: const Key('teacher_group_tab_announcements'),
          label: 'Announcements',
          icon: FluentIcons.megaphone,
          selected: selectedTab == TeacherGroupDetailTab.announcements,
          onPressed: () => onChanged(TeacherGroupDetailTab.announcements),
        ),
        _GroupDetailTab(
          key: const Key('teacher_group_tab_assignments'),
          label: 'Classwork',
          icon: FluentIcons.education,
          selected: selectedTab == TeacherGroupDetailTab.classwork,
          onPressed: () => onChanged(TeacherGroupDetailTab.classwork),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TeacherRosterHeader(title: 'Teachers'),
          _TeacherRosterRow(
            avatarKey: Key(
              'teacher_group_teacher_avatar_${controller.selectedGroup!.id}',
            ),
            initials: userInitials(controller.teacherDisplayName),
            name: controller.teacherDisplayName,
          ),
          const SizedBox(height: AppSpacing.xl),
          _TeacherRosterHeader(
            key: const Key('teacher_group_members_section'),
            title: 'Students',
            trailing:
                '${controller.approvedMemberships.length} '
                '${controller.approvedMemberships.length == 1 ? 'student' : 'students'}',
          ),
          if (controller.approvedMemberships.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('No students in this class yet.'),
            )
          else
            for (final membership in controller.approvedMemberships)
              _TeacherRosterRow(
                key: Key('teacher_group_member_open_${membership.id}'),
                avatarKey: Key('teacher_group_member_avatar_${membership.id}'),
                initials: userInitials(membership.traineeDisplayName),
                networkImageUrl: controller.profilePictureUrlFor(
                  membership.traineeId,
                ),
                name: membership.traineeDisplayName,
                onPressed: () => context.go(
                  AppRoutePaths.teacherStudentDetail(
                    membership.traineeId,
                    groupId: controller.selectedGroup!.id,
                  ),
                ),
                trailing: Button(
                  key: Key('teacher_group_remove_${membership.id}'),
                  onPressed: controller.busy
                      ? null
                      : () => _confirmRemoveMember(
                          context,
                          controller,
                          membership,
                        ),
                  child: const Text('Remove from class'),
                ),
              ),
          const SizedBox(height: AppSpacing.xl),
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
        ],
      ),
    );
  }
}

class _TeacherRosterHeader extends StatelessWidget {
  const _TeacherRosterHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  trailing!,
                  style: AppTheme.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Divider(
          style: DividerThemeData(
            decoration: BoxDecoration(color: context.elixBorder),
            horizontalMargin: EdgeInsets.zero,
            verticalMargin: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _TeacherRosterRow extends StatelessWidget {
  const _TeacherRosterRow({
    super.key,
    required this.avatarKey,
    required this.initials,
    required this.name,
    this.networkImageUrl,
    this.onPressed,
    this.trailing,
  });

  final Key avatarKey;
  final String initials;
  final String name;
  final String? networkImageUrl;
  final VoidCallback? onPressed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nameLabel = Text(
      name,
      style: AppTheme.body.copyWith(
        color: context.elixTextPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          ProfileAvatarWidget(
            key: avatarKey,
            radius: 18,
            showBorder: false,
            initials: initials,
            networkImageUrl: networkImageUrl,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: onPressed == null
                ? nameLabel
                : HoverButton(
                    cursor: SystemMouseCursors.click,
                    onPressed: onPressed,
                    builder: (context, states) => AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 120),
                      style: AppTheme.body.copyWith(
                        color: states.isHovered
                            ? AppColors.primary
                            : context.elixTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Text(name),
                    ),
                  ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.elixBorder)),
      ),
      child: row,
    );
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          ProfileAvatarWidget(
                            key: Key(
                              'teacher_group_member_avatar_${membership.id}',
                            ),
                            radius: 18,
                            showBorder: false,
                            initials: userInitials(
                              membership.traineeDisplayName,
                            ),
                            networkImageUrl: profilePictureUrlFor(
                              membership.traineeId,
                            ),
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
                                  'Wants to join',
                                  style: AppTheme.caption.copyWith(
                                    color: context.elixTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
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

T? _tryRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

Future<void> _showGroupAssignmentComposer(
  BuildContext context,
  TeacherGroupsController controller,
  TeacherClassworkController classworkController,
  ElixrGroup group,
  TeacherMovementRepository? movementRepository,
) async {
  final currentGroup = controller.selectedGroup;
  if (currentGroup == null ||
      currentGroup.id != group.id ||
      !currentGroup.isActive) {
    return;
  }

  final assignmentRepository = classworkController.assignmentRepository;

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
    groupRepository: controller.repository,
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
    groupRepository: controller.repository,
    creationService: service,
    lockedGroup: currentGroup,
  );
}

Future<void> _showEditAssignmentDialog(
  BuildContext context,
  TeacherClassworkController controller,
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
  TeacherClassworkController controller,
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
      title: const Text('Rename classroom'),
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
      title: const Text('Archive this classroom?'),
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
