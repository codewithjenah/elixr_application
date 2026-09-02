import 'dart:io';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/chat_repository.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player_win/video_player_win.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/router/navigation_helpers.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/elix_toast.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/assignment_attempt_policy.dart';
import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../../services/auth_service.dart';
import '../classwork/teacher_classwork_controller.dart';
import '../classwork/teacher_gradebook_pane.dart';
import '../classwork/teacher_classwork_pane.dart';
import '../movements/teacher_assignment_composer.dart';
import '../movements/teacher_demo_recording_dialog.dart';
import '../movements/teacher_movement_builder_dialog.dart';
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
    this.initialTab,
  });

  final String groupId;
  final TeacherGroupsController? controller;
  final TeacherClassworkController? classworkController;
  final ClassroomAnnouncementsController? announcementsController;
  final TeacherMovementRepository? movementRepository;
  final String? initialAssignmentId;
  final String? initialTraineeId;
  final String? initialTab;

  @override
  State<TeacherGroupDetailScreen> createState() =>
      _TeacherGroupDetailScreenState();
}

class _TeacherGroupDetailScreenState extends State<TeacherGroupDetailScreen> {
  TeacherGroupsController? _owned;
  TeacherGroupsController? _feedbackController;
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
      _owned =
          TeacherGroupsController(
              repository: context.read<GroupRepository>(),
              teacherId: userId,
              teacherDisplayName: user.fullName,
              ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
              publicProfileRepository: publicProfileRepository,
            )
            ..setTab(_teacherTabFromQuery(widget.initialTab))
            ..startForGroup(widget.groupId);
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
    _feedbackController?.removeListener(_showActionMessage);
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
    _listenForFeedback();
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
                label: 'Students',
                tooltip: 'Back to students',
                semanticLabel: 'Back to students',
                onPressed: () async {
                  await classwork.selectTrainee(null);
                  if (!context.mounted) return;
                  popOrGo(
                    context,
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
                  popOrGo(context, AppRoutePaths.teacherGroup(widget.groupId));
                },
              )
            : ElixBackButton(
                key: const Key('teacher_group_back'),
                label: 'Classrooms',
                tooltip: 'Back to classrooms',
                semanticLabel: 'Back to classrooms',
                onPressed: () => popOrGo(context, AppRoutePaths.teacherGroups),
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
              const SizedBox(height: AppSpacing.sm),
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
                      context.push(
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

  void _listenForFeedback() {
    final controller = _controller;
    if (identical(_feedbackController, controller)) return;
    _feedbackController?.removeListener(_showActionMessage);
    _feedbackController = controller;
    _feedbackController?.addListener(_showActionMessage);
  }

  void _showActionMessage() {
    if (!mounted) return;
    final message = _feedbackController?.consumeActionMessage();
    if (message != null) ElixToast.showSuccess(context, message: message);
  }
}

TeacherGroupDetailTab _teacherTabFromQuery(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'classwork' => TeacherGroupDetailTab.classwork,
    'grades' => TeacherGroupDetailTab.grades,
    'people' => TeacherGroupDetailTab.students,
    _ => TeacherGroupDetailTab.announcements,
  };
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
    final showStreamContext =
        controller.tab == TeacherGroupDetailTab.announcements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStreamContext) ...[
          TraineeClassHeroBanner(
            groupId: group.id,
            title: group.name,
            subtitle: () {
              final classMetadata = [group.section, group.schedule]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' · ');
              if (!group.isActive) return 'Archived';
              return classMetadata.isEmpty ? 'Active' : classMetadata;
            }(),
            height: 128,
            subtitleIcon: group.isActive
                ? FluentIcons.completed
                : FluentIcons.archive,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(message: controller.errorMessage!, isError: true),
          const SizedBox(height: AppSpacing.md),
        ],
        if (showStreamContext)
          ElixPanelCard(
            padding: const EdgeInsets.all(AppSpacing.md),
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
                    if (group.isActive)
                      Button(
                        onPressed: controller.busy
                            ? null
                            : () => _confirmArchive(context, controller),
                        child: const Text('Archive'),
                      )
                    else
                      Button(
                        key: const Key('teacher_group_unarchive_classroom'),
                        onPressed: controller.busy
                            ? null
                            : () => _confirmUnarchive(context, controller),
                        child: const Text('Unarchive'),
                      ),
                    Button(
                      key: const Key('teacher_group_delete_classroom'),
                      onPressed: controller.busy
                          ? null
                          : () => _confirmPermanentlyDeleteClassroom(
                              context,
                              controller,
                              group,
                            ),
                      child: const Text('Delete classroom'),
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
        if (showStreamContext) const SizedBox(height: AppSpacing.md),
        _GroupDetailTabBar(
          key: const Key('teacher_group_detail_tabs'),
          selectedTab: controller.tab,
          onChanged: controller.setTab,
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.tab == TeacherGroupDetailTab.classwork)
          TeacherClassworkAssignmentList(
            key: const Key('teacher_group_assignments_section'),
            controller: classworkController,
            onOpen: (assignment) => context.push(
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
            onDelete: group.isActive && !classworkController.busy
                ? (assignment) => _confirmPermanentlyDeleteAssignment(
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
                  teacherProfilePictureUrl: _tryRead<AuthService>(
                    context,
                  )?.currentUser?.profilePictureUrl,
                  canManage: true,
                  groupIsActive: group.isActive,
                  assignments: classworkController.assignments,
                  onOpenAssignment: (assignment) => context.push(
                    AppRoutePaths.teacherGroupClasswork(
                      group.id,
                      assignment.id,
                    ),
                  ),
                )
        else if (controller.tab == TeacherGroupDetailTab.grades)
          TeacherGradebookPane(
            key: const Key('teacher_group_grades_section'),
            controller: classworkController,
            profilePictureUrlFor: controller.profilePictureUrlFor,
            onOpenStudent: (membership) => context.push(
              AppRoutePaths.teacherStudentDetail(
                membership.traineeId,
                groupId: group.id,
              ),
            ),
            onOpenAssignment: (assignment) => context.push(
              AppRoutePaths.teacherGroupClasswork(group.id, assignment.id),
            ),
            onOpenCell: (assignment, traineeId) => context.push(
              AppRoutePaths.teacherGroupClasswork(
                group.id,
                assignment.id,
                traineeId: traineeId,
              ),
            ),
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
          label: 'Stream',
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
          key: const Key('teacher_group_tab_grades'),
          label: 'Grades',
          icon: FluentIcons.assessment_group,
          selected: selectedTab == TeacherGroupDetailTab.grades,
          onPressed: () => onChanged(TeacherGroupDetailTab.grades),
        ),
        _GroupDetailTab(
          key: const Key('teacher_group_tab_students'),
          label: 'People',
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                onPressed: () => context.push(
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
  final currentAssignment =
      await controller.assignmentRepository.getAssignment(
        assignmentId: assignment.id,
      ) ??
      assignment;
  if (!context.mounted) return;
  assignment = currentAssignment;
  if (assignment.isTeacherCreated) {
    await _showTeacherActivityAssignmentEditor(context, controller, assignment);
    return;
  }
  final initialScore = assignment.maxScore?.toString() ?? '';
  final scoreController = TextEditingController(text: initialScore);
  var dueAt = assignment.dueAt;
  var hasDueDate = dueAt != null;
  String? validationMessage;

  var saving = false;
  await showDialog<void>(
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
                onChanged: saving
                    ? null
                    : (value) {
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
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => dueAt = value),
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
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('teacher_assignment_save_changes'),
            onPressed: saving
                ? null
                : () async {
                    final maxScore =
                        assignment.isTeacherCreated && !assignment.gradingLocked
                        ? int.tryParse(scoreController.text.trim())
                        : null;
                    if (assignment.isTeacherCreated &&
                        !assignment.gradingLocked &&
                        (maxScore == null || maxScore < 1 || maxScore > 100)) {
                      setDialogState(() {
                        validationMessage =
                            'Enter a maximum score from 1 to 100.';
                      });
                      return;
                    }
                    setDialogState(() {
                      saving = true;
                      validationMessage = null;
                    });
                    final saved = await controller.updateAssignmentSettings(
                      assignment,
                      dueAt: hasDueDate ? dueAt : null,
                      maxScore: maxScore,
                    );
                    if (!dialogContext.mounted) return;
                    if (!saved) {
                      setDialogState(() {
                        saving = false;
                        validationMessage =
                            controller.errorMessage ??
                            'This assignment could not be saved.';
                      });
                      return;
                    }
                    Navigator.pop(dialogContext);
                  },
            child: Text(saving ? 'Saving...' : 'Save changes'),
          ),
        ],
      ),
    ),
  );
  scoreController.dispose();
}

Future<void> _showTeacherActivityAssignmentEditor(
  BuildContext context,
  TeacherClassworkController controller,
  GroupAssignment assignment,
) async {
  final movementRepository = _tryReadTeacherMovementRepository(context);
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => TeacherMovementBuilderDialog(
        assignment: assignment,
        approvedMemberships: controller.approvedMemberships,
        onCreateTeacherReviewed:
            ({
              required title,
              required instructions,
              required requiredProp,
              safetyGuidance,
            }) async {
              throw StateError('Classroom Activities cannot be created here.');
            },
        onEditAssignment:
            ({
              required title,
              required instructions,
              required requiredProp,
              required assessment,
              required attemptPolicy,
              required audience,
              dueAt,
              safetyGuidance,
              topic,
            }) async {
              final saved = await controller.updateTeacherActivityAssignment(
                assignment: assignment,
                displayTitle: title,
                instructions: instructions,
                safetyGuidance: safetyGuidance,
                topic: topic,
                dueAt: dueAt,
                audience: audience,
                activityAssessment: assessment,
                attemptPolicy: attemptPolicy,
                requiredProp: requiredProp,
              );
              if (!saved) {
                throw StateError(
                  controller.errorMessage ??
                      'This Classroom Activity could not be saved.',
                );
              }
            },
        onUploadDemonstration: movementRepository == null
            ? null
            : ({required localFile, required duration, required source}) =>
                  movementRepository.uploadActivityDemonstration(
                    teacherId: controller.teacherId,
                    localFile: localFile,
                    duration: duration,
                    source: source,
                    assignmentId: assignment.id,
                  ),
      ),
    ),
  );
}

@Deprecated('Use the full-page Classroom Activity editor instead.')
Future<void> showTeacherActivityAssignmentEditDialogLegacy(
  BuildContext context,
  TeacherClassworkController controller,
  GroupAssignment assignment,
) async {
  final original =
      assignment.activityAssessment ??
      _legacyActivityAssessmentFromAssignment(assignment);
  final title = TextEditingController(text: assignment.displayTitle);
  final instructions = TextEditingController(
    text: assignment.displayInstructions ?? '',
  );
  final safety = TextEditingController(
    text: assignment.displaySafetyGuidance ?? '',
  );
  final topic = TextEditingController(text: assignment.topic ?? '');
  var dueAt = assignment.dueAt;
  var hasDueDate = dueAt != null;
  var readiness = original.readiness;
  var requiredProp = assignment.allowedProp ?? TrainingProp.bottle;
  var template = original.rubric.template;
  var maximumScore = original.rubric.maximumScore;
  final customMaximum = TextEditingController(text: '$maximumScore');
  final customCriteria = <_ActivityEditCriterionControllers>[
    for (final criterion in original.rubric.criteria)
      _ActivityEditCriterionControllers.fromCriterion(criterion),
  ];
  var nextCriterionId = customCriteria.length + 1;
  var attempts = assignment.attemptPolicy;
  var duration = original.recordingDurationSeconds;
  var audienceType = assignment.audience.type;
  final targets = <String>{...assignment.audience.targetTraineeIds};
  var demonstrationVideo = original.demonstrationVideo;
  var demoBusy = false;
  String? validation;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: Text('Edit ${assignment.displayTitle}'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Changes apply to future submissions. Existing recordings keep '
                  'their original readiness and rubric snapshot.',
                ),
                const SizedBox(height: AppSpacing.md),
                InfoLabel(
                  label: 'Title',
                  child: TextBox(
                    key: const Key('teacher_activity_edit_title'),
                    controller: title,
                    maxLength: 160,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Instructions',
                  child: TextBox(
                    key: const Key('teacher_activity_edit_instructions'),
                    controller: instructions,
                    maxLength: 4000,
                    minLines: 3,
                    maxLines: 6,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Safety guidance (optional)',
                  child: TextBox(
                    key: const Key('teacher_activity_edit_safety'),
                    controller: safety,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Topic (optional)',
                  child: TextBox(
                    key: const Key('teacher_activity_edit_topic'),
                    controller: topic,
                    maxLength: GroupAssignment.maxTopicLength,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Checkbox(
                  key: const Key('teacher_activity_edit_due_date_toggle'),
                  checked: hasDueDate,
                  content: const Text('Set a due date'),
                  onChanged: (value) => setDialogState(() {
                    hasDueDate = value ?? false;
                    dueAt ??= DateTime.now().add(const Duration(days: 7));
                  }),
                ),
                if (hasDueDate)
                  DatePicker(
                    key: const Key('teacher_activity_edit_due_date'),
                    selected: dueAt ?? DateTime.now(),
                    onChanged: (value) => setDialogState(() => dueAt = value),
                  ),
                const SizedBox(height: AppSpacing.md),
                _activityEditPicker<TrainingProp>(
                  label: 'Required prop',
                  value: requiredProp,
                  values: TrainingProp.values,
                  labelFor: (value) => value.displayLabel,
                  onChanged: (value) =>
                      setDialogState(() => requiredProp = value!),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Readiness',
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                _activityEditPicker<ActivityHandRequirement>(
                  label: 'Hands',
                  value: readiness.hands,
                  values: ActivityHandRequirement.values,
                  labelFor: (value) => value.displayLabel,
                  onChanged: (value) => setDialogState(
                    () => readiness = TeacherActivityReadinessSpec(
                      hands: value!,
                      body: readiness.body,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _activityEditPicker<ActivityBodyRequirement>(
                  label: 'Body',
                  value: readiness.body,
                  values: ActivityBodyRequirement.values,
                  labelFor: (value) => value.displayLabel,
                  onChanged: (value) => setDialogState(
                    () => readiness = TeacherActivityReadinessSpec(
                      hands: readiness.hands,
                      body: value!,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InfoLabel(
                  label: 'Rubric template',
                  child: ComboBox<TeacherActivityRubricTemplate>(
                    key: const Key('teacher_activity_edit_rubric_template'),
                    value: template,
                    isExpanded: true,
                    items: [
                      for (final value in TeacherActivityRubricTemplate.values)
                        ComboBoxItem(
                          value: value,
                          child: Text(value.displayLabel),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      template = value!;
                      if (template == TeacherActivityRubricTemplate.custom) {
                        customMaximum.text = '$maximumScore';
                      }
                    }),
                  ),
                ),
                if (template == TeacherActivityRubricTemplate.custom) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Use 3–5 complete criteria. The maximum score is derived from their total.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (
                    var index = 0;
                    index < customCriteria.length;
                    index++
                  ) ...[
                    _ActivityEditCriterionEditor(
                      index: index,
                      controllers: customCriteria[index],
                      canRemove: customCriteria.length > 3,
                      onRemove: () => setDialogState(
                        () => customCriteria.removeAt(index).dispose(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Button(
                    key: const Key('teacher_activity_edit_add_criterion'),
                    onPressed: customCriteria.length >= 5
                        ? null
                        : () => setDialogState(
                            () => customCriteria.add(
                              _ActivityEditCriterionControllers.empty(
                                nextCriterionId++,
                              ),
                            ),
                          ),
                    child: const Text('Add criterion'),
                  ),
                ] else ...[
                  const SizedBox(height: AppSpacing.sm),
                  InfoLabel(
                    label: 'Maximum score',
                    child: Column(
                      children: [
                        ComboBox<String>(
                          key: const Key('teacher_activity_edit_maximum_score'),
                          value:
                              TeacherActivityAssessmentContract
                                  .supportedMaximumScores
                                  .contains(maximumScore)
                              ? '$maximumScore'
                              : 'custom',
                          isExpanded: true,
                          items: const [
                            ComboBoxItem(value: '30', child: Text('30 points')),
                            ComboBoxItem(value: '50', child: Text('50 points')),
                            ComboBoxItem(
                              value: '100',
                              child: Text('100 points'),
                            ),
                            ComboBoxItem(
                              value: 'custom',
                              child: Text('Custom maximum'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            if (value == 'custom') {
                              maximumScore = 0;
                              customMaximum.clear();
                            } else if (value != null) {
                              maximumScore = int.parse(value);
                              customMaximum.text = value;
                            }
                          }),
                        ),
                        if (!TeacherActivityAssessmentContract
                            .supportedMaximumScores
                            .contains(maximumScore)) ...[
                          const SizedBox(height: AppSpacing.xs),
                          TextBox(
                            key: const Key(
                              'teacher_activity_edit_custom_builtin_maximum',
                            ),
                            controller: customMaximum,
                            placeholder: '1–100',
                            onChanged: (value) => setDialogState(
                              () => maximumScore =
                                  int.tryParse(value.trim()) ?? 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Try limit',
                  child: ComboBox<String>(
                    key: const Key('teacher_activity_edit_attempt_policy'),
                    value: attempts.isUnlimited
                        ? 'unlimited'
                        : '${attempts.maximumAttempts}',
                    isExpanded: true,
                    items: const [
                      ComboBoxItem(value: '1', child: Text('1 try')),
                      ComboBoxItem(value: '2', child: Text('2 tries')),
                      ComboBoxItem(value: '3', child: Text('3 tries')),
                      ComboBoxItem(
                        value: 'unlimited',
                        child: Text('Unlimited'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => attempts = value == 'unlimited'
                          ? const AssignmentAttemptPolicy.unlimited()
                          : AssignmentAttemptPolicy.finite(int.parse(value!)),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Recording duration',
                  child: ComboBox<int>(
                    key: const Key('teacher_activity_edit_duration'),
                    value: duration,
                    isExpanded: true,
                    items: [
                      for (final seconds
                          in TeacherActivityAssessmentContract
                              .supportedRecordingDurations)
                        ComboBoxItem(
                          value: seconds,
                          child: Text('$seconds seconds'),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => duration = value!),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  demonstrationVideo == null
                      ? 'No demonstration video attached.'
                      : 'Demonstration: ${demonstrationVideo!.durationMs ~/ 1000}s MP4',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    Button(
                      onPressed: demoBusy
                          ? null
                          : () async {
                              final repository =
                                  _tryReadTeacherMovementRepository(context);
                              if (repository == null) return;
                              final selected = await ImagePicker().pickVideo(
                                source: ImageSource.gallery,
                              );
                              if (selected == null) return;
                              setDialogState(() => demoBusy = true);
                              try {
                                if (!selected.name.toLowerCase().endsWith(
                                  '.mp4',
                                )) {
                                  throw const FormatException('Invalid type');
                                }
                                final file = File(selected.path);
                                final stat = await file.stat();
                                if (stat.type != FileSystemEntityType.file ||
                                    stat.size < 1 ||
                                    stat.size >
                                        TeacherActivityAssessmentContract
                                            .maximumVideoSizeBytes) {
                                  throw const FormatException('Invalid size');
                                }
                                final player = WinVideoPlayerController.file(
                                  file,
                                );
                                Duration videoDuration;
                                try {
                                  await player.initialize();
                                  videoDuration = player.value.duration;
                                } finally {
                                  await player.dispose();
                                }
                                if (videoDuration.inMilliseconds < 1 ||
                                    videoDuration.inMilliseconds > 60000) {
                                  throw const FormatException(
                                    'Invalid duration',
                                  );
                                }
                                final uploaded = await repository
                                    .uploadActivityDemonstration(
                                      teacherId: controller.teacherId,
                                      localFile: file,
                                      duration: videoDuration,
                                      source:
                                          TeacherActivityDemoSource.uploaded,
                                      assignmentId: assignment.id,
                                    );
                                setDialogState(
                                  () => demonstrationVideo = uploaded,
                                );
                              } catch (_) {
                                setDialogState(
                                  () => validation =
                                      'Choose a playable MP4 up to 60 seconds and 50 MiB.',
                                );
                              } finally {
                                setDialogState(() => demoBusy = false);
                              }
                            },
                      child: const Text('Upload MP4'),
                    ),
                    Button(
                      onPressed: demoBusy
                          ? null
                          : () async {
                              final repository =
                                  _tryReadTeacherMovementRepository(context);
                              if (repository == null) return;
                              final recorded =
                                  await showTeacherDemoRecordingDialog(
                                    context,
                                    upload:
                                        ({
                                          required localFile,
                                          required duration,
                                          required source,
                                        }) => repository
                                            .uploadActivityDemonstration(
                                              teacherId: controller.teacherId,
                                              localFile: localFile,
                                              duration: duration,
                                              source: source,
                                              assignmentId: assignment.id,
                                            ),
                                  );
                              if (recorded != null) {
                                setDialogState(
                                  () => demonstrationVideo = recorded,
                                );
                              }
                            },
                      child: const Text('Record with ELIXR'),
                    ),
                    if (demonstrationVideo != null)
                      Button(
                        onPressed: demoBusy
                            ? null
                            : () => setDialogState(
                                () => demonstrationVideo = null,
                              ),
                        child: const Text('Remove demo'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                InfoLabel(
                  label: 'Assign to',
                  child: ComboBox<AssignmentAudienceType>(
                    key: const Key('teacher_activity_edit_audience'),
                    value: audienceType,
                    isExpanded: true,
                    items: const [
                      ComboBoxItem(
                        value: AssignmentAudienceType.entireClass,
                        child: Text('Entire class'),
                      ),
                      ComboBoxItem(
                        value: AssignmentAudienceType.selectedStudents,
                        child: Text('Selected students'),
                      ),
                      ComboBoxItem(
                        value: AssignmentAudienceType.individualStudent,
                        child: Text('One student'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      audienceType = value!;
                      if (audienceType ==
                              AssignmentAudienceType.individualStudent &&
                          targets.length > 1) {
                        targets.removeWhere((id) => id != targets.first);
                      }
                    }),
                  ),
                ),
                if (audienceType != AssignmentAudienceType.entireClass)
                  for (final member in controller.approvedMemberships)
                    Checkbox(
                      checked: targets.contains(member.traineeId),
                      content: Text(member.traineeDisplayName),
                      onChanged: (checked) => setDialogState(() {
                        if (checked == true) {
                          if (audienceType ==
                              AssignmentAudienceType.individualStudent) {
                            targets.clear();
                          }
                          targets.add(member.traineeId);
                        } else {
                          targets.remove(member.traineeId);
                        }
                      }),
                    ),
                if (validation != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    validation!,
                    key: const Key('teacher_activity_edit_validation'),
                    style: AppTheme.caption.copyWith(color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('teacher_activity_save_changes'),
            onPressed: () async {
              if (title.text.trim().isEmpty ||
                  instructions.text.trim().isEmpty) {
                setDialogState(
                  () => validation = 'Enter both a title and instructions.',
                );
                return;
              }
              if (audienceType != AssignmentAudienceType.entireClass &&
                  targets.isEmpty) {
                setDialogState(
                  () => validation = 'Choose at least one approved student.',
                );
                return;
              }
              try {
                final audience = switch (audienceType) {
                  AssignmentAudienceType.entireClass =>
                    const AssignmentAudience.entireClass(),
                  AssignmentAudienceType.selectedStudents =>
                    AssignmentAudience.selectedStudents(targets),
                  AssignmentAudienceType.individualStudent =>
                    AssignmentAudience.individualStudent(targets),
                };
                late final TeacherActivityRubric rubric;
                if (template == TeacherActivityRubricTemplate.custom) {
                  final resolvedCriteria = customCriteria
                      .map((item) => item.toCriterion())
                      .whereType<TeacherActivityRubricCriterion>()
                      .toList(growable: false);
                  if (resolvedCriteria.length != customCriteria.length) {
                    throw StateError('incomplete rubric');
                  }
                  maximumScore = resolvedCriteria.fold<int>(
                    0,
                    (total, criterion) => total + criterion.maximumPoints,
                  );
                  rubric = TeacherActivityRubric(
                    template: TeacherActivityRubricTemplate.custom,
                    maximumScore: maximumScore,
                    criteria: resolvedCriteria,
                  );
                } else {
                  rubric = TeacherActivityRubric.builtIn(
                    template,
                    maximumScore,
                  );
                }
                final assessment = TeacherActivityAssessmentConfig(
                  readiness: readiness,
                  rubric: rubric,
                  recordingDurationSeconds: duration,
                  demonstrationVideo: demonstrationVideo,
                );
                if (!assessment.isValid) throw StateError('invalid assessment');
                final saved = await controller.updateTeacherActivityAssignment(
                  assignment: assignment,
                  displayTitle: title.text,
                  instructions: instructions.text,
                  safetyGuidance: safety.text,
                  topic: topic.text,
                  dueAt: hasDueDate ? dueAt : null,
                  audience: audience,
                  activityAssessment: assessment,
                  attemptPolicy: attempts,
                  requiredProp: requiredProp,
                );
                if (context.mounted && saved) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (_) {
                setDialogState(
                  () => validation = 'Check the Teacher Activity settings.',
                );
              }
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  instructions.dispose();
  safety.dispose();
  topic.dispose();
  customMaximum.dispose();
  for (final criterion in customCriteria) {
    criterion.dispose();
  }
  if (saved == true && context.mounted) {
    // The assignment watcher supplies the updated configuration and revision.
  }
}

TeacherActivityAssessmentConfig _legacyActivityAssessmentFromAssignment(
  GroupAssignment assignment,
) {
  final score = assignment.maxScore;
  final maximumScore = score != null && score >= 1 && score <= 100
      ? score
      : TeacherActivityAssessmentContract.defaultMaximumScore;
  return TeacherActivityAssessmentConfig(
    readiness: const TeacherActivityReadinessSpec(),
    rubric: TeacherActivityRubric.builtIn(
      TeacherActivityRubricTemplate.standardTechnique,
      maximumScore,
    ),
    recordingDurationSeconds:
        TeacherActivityAssessmentContract.defaultRecordingDurationSeconds,
  );
}

class _ActivityEditCriterionControllers {
  _ActivityEditCriterionControllers({
    required this.id,
    required String label,
    required String description,
    required int maximumPoints,
  }) : label = TextEditingController(text: label),
       description = TextEditingController(text: description),
       maximumPoints = TextEditingController(text: '$maximumPoints');

  factory _ActivityEditCriterionControllers.fromCriterion(
    TeacherActivityRubricCriterion criterion,
  ) => _ActivityEditCriterionControllers(
    id: criterion.id,
    label: criterion.label,
    description: criterion.description,
    maximumPoints: criterion.maximumPoints,
  );

  factory _ActivityEditCriterionControllers.empty(int ordinal) =>
      _ActivityEditCriterionControllers(
        id: 'custom_$ordinal',
        label: '',
        description: '',
        maximumPoints: 1,
      );

  final String id;
  final TextEditingController label;
  final TextEditingController description;
  final TextEditingController maximumPoints;

  TeacherActivityRubricCriterion? toCriterion() {
    final criterionLabel = label.text.trim();
    final criterionDescription = description.text.trim();
    final points = int.tryParse(maximumPoints.text.trim());
    if (criterionLabel.isEmpty ||
        criterionLabel.length > 80 ||
        criterionDescription.isEmpty ||
        criterionDescription.length > 500 ||
        points == null ||
        points < 1 ||
        points > 100) {
      return null;
    }
    return TeacherActivityRubricCriterion(
      id: id,
      label: criterionLabel,
      description: criterionDescription,
      maximumPoints: points,
    );
  }

  void dispose() {
    label.dispose();
    description.dispose();
    maximumPoints.dispose();
  }
}

class _ActivityEditCriterionEditor extends StatelessWidget {
  const _ActivityEditCriterionEditor({
    required this.index,
    required this.controllers,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _ActivityEditCriterionControllers controllers;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: context.elixBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Criterion ${index + 1}')),
            if (canRemove)
              IconButton(
                key: Key('teacher_activity_edit_remove_criterion_$index'),
                icon: const Icon(FluentIcons.delete),
                onPressed: onRemove,
              ),
          ],
        ),
        TextBox(
          key: Key('teacher_activity_edit_criterion_label_$index'),
          controller: controllers.label,
          placeholder: 'Criterion label',
          maxLength: 80,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: Key('teacher_activity_edit_criterion_description_$index'),
          controller: controllers.description,
          placeholder: 'What the Teacher will assess',
          maxLength: 500,
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: Key('teacher_activity_edit_criterion_points_$index'),
          controller: controllers.maximumPoints,
          placeholder: 'Maximum points',
        ),
      ],
    ),
  );
}

Widget _activityEditPicker<T>({
  required String label,
  required T value,
  required List<T> values,
  required String Function(T value) labelFor,
  required ValueChanged<T?> onChanged,
}) => InfoLabel(
  label: label,
  child: ComboBox<T>(
    value: value,
    isExpanded: true,
    items: [
      for (final item in values)
        ComboBoxItem(value: item, child: Text(labelFor(item))),
    ],
    onChanged: onChanged,
  ),
);

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

Future<void> _confirmPermanentlyDeleteAssignment(
  BuildContext context,
  TeacherClassworkController controller,
  GroupAssignment assignment,
) async {
  final confirmation = TextEditingController();
  var phraseMatches = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: const Text('Permanently delete assignment?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes “${assignment.displayTitle}”, its '
                'recipient records, submissions, and uploaded media. This '
                'cannot be undone.',
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Type DELETE ASSIGNMENT to continue.'),
              const SizedBox(height: AppSpacing.xs),
              TextBox(
                key: const Key('teacher_assignment_delete_confirmation'),
                controller: confirmation,
                autofocus: true,
                onChanged: (value) => setDialogState(
                  () => phraseMatches = value == 'DELETE ASSIGNMENT',
                ),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('teacher_assignment_confirm_delete'),
            onPressed: phraseMatches
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    ),
  );
  confirmation.dispose();
  if (accepted == true) {
    await controller.permanentlyDeleteAssignment(assignment);
  }
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
      content: SizedBox(
        width: 420,
        height: 44,
        child: TextBox(
          controller: nameController,
          autofocus: true,
          maxLines: 1,
        ),
      ),
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
  await controller.archiveSelectedGroup(showSuccess: false);
  if (controller.selectedGroup == null &&
      controller.errorMessage == null &&
      context.mounted) {
    context.go(AppRoutePaths.teacherGroups);
  }
}

Future<void> _confirmUnarchive(
  BuildContext context,
  TeacherGroupsController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Unarchive this classroom?'),
      content: const Text(
        'This classroom will return to your active classrooms. Its students, '
        'classwork, and existing class code will remain available.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          key: const Key('teacher_group_confirm_unarchive'),
          child: const Text('Unarchive'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted != true) return;
  await controller.unarchiveSelectedGroup();
}

Future<void> _confirmPermanentlyDeleteClassroom(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final confirmation = TextEditingController();
  var phraseMatches = false;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: const Text('Permanently delete classroom?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes “${group.name}”, its class code, '
                'memberships, assignments, submissions, and uploaded media. '
                'This cannot be undone.',
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Type DELETE CLASSROOM to continue.'),
              const SizedBox(height: AppSpacing.xs),
              TextBox(
                key: const Key('teacher_group_delete_confirmation'),
                controller: confirmation,
                autofocus: true,
                onChanged: (value) => setDialogState(
                  () => phraseMatches = value == 'DELETE CLASSROOM',
                ),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('teacher_group_confirm_delete'),
            onPressed: phraseMatches
                ? () => Navigator.pop(dialogContext, true)
                : null,
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    ),
  );
  confirmation.dispose();
  if (accepted != true) return;
  await controller.permanentlyDeleteClassroom(group, showSuccess: false);
  if (controller.selectedGroup == null && context.mounted) {
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
