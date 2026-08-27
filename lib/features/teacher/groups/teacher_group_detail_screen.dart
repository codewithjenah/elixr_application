import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../../teacher_access/trainee_class_card.dart';
import 'teacher_groups_controller.dart';

class TeacherGroupDetailScreen extends StatefulWidget {
  const TeacherGroupDetailScreen({
    super.key,
    required this.groupId,
    this.controller,
  });

  final String groupId;
  final TeacherGroupsController? controller;

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
        header: PageHeader(title: Text('Group')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final group = controller.selectedGroup;
        return TeacherScaffoldPage(
          header: PageHeader(
            title: Text(group?.name ?? 'Group'),
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
          content: _GroupDetailBody(controller: controller),
        );
      },
    );
  }
}

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({required this.controller});

  final TeacherGroupsController controller;

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
            child: const Text('Remove'),
          ),
        ),
      ],
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
          child: const Text('Remove member'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.removeMembership(membership);
}
