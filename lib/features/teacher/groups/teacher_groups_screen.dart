import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import 'teacher_groups_controller.dart';

class TeacherGroupsScreen extends StatefulWidget {
  const TeacherGroupsScreen({super.key});

  @override
  State<TeacherGroupsScreen> createState() => _TeacherGroupsScreenState();
}

class _TeacherGroupsScreenState extends State<TeacherGroupsScreen> {
  TeacherGroupsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    _controller = TeacherGroupsController(
      repository: context.read<GroupRepository>(),
      teacherId: userId,
      teacherDisplayName: user.fullName,
      ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
      publicProfileRepository: context.read<PublicProfileRepository>(),
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: PageHeader(title: Text('Groups')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: PageHeader(
            title: const Text('Groups'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.add),
                  label: const Text('Create group'),
                  onPressed: controller.busy
                      ? null
                      : () => _showCreateGroupDialog(context, controller),
                ),
              ],
            ),
          ),
          content: controller.loading
              ? const Center(child: ProgressRing())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _GroupsListPanel(controller: controller),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      flex: 3,
                      child: controller.selectedGroup == null
                          ? _EmptyDetailPanel(
                              hasGroups: controller.groups.isNotEmpty,
                            )
                          : _GroupDetailPanel(controller: controller),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _GroupsListPanel extends StatelessWidget {
  const _GroupsListPanel({required this.controller});

  final TeacherGroupsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null && controller.groups.isEmpty) {
      return ElixStatusPanel(
        key: const Key('teacher_groups_error'),
        message: controller.errorMessage!,
        isError: true,
      );
    }
    if (controller.groups.isEmpty) {
      return const ElixStatusPanel(
        key: Key('teacher_groups_empty'),
        message:
            'No groups yet. Create a class such as BSHM 4A to share a group invite code.',
      );
    }

    return ElixPanelCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: controller.groups.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final group = controller.groups[index];
          final selected = controller.selectedGroup?.id == group.id;
          return ListTile(
            key: Key('teacher_group_tile_${group.id}'),
            title: Text(group.name),
            subtitle: Text(
              group.isActive ? 'Active' : 'Archived',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            trailing: selected ? const Icon(FluentIcons.chevron_right) : null,
            onPressed: () => controller.selectGroup(group),
          );
        },
      ),
    );
  }
}

class _EmptyDetailPanel extends StatelessWidget {
  const _EmptyDetailPanel({required this.hasGroups});

  final bool hasGroups;

  @override
  Widget build(BuildContext context) {
    return ElixStatusPanel(
      message: hasGroups
          ? 'Select a group to manage invite codes and membership.'
          : 'Create your first group to get started.',
    );
  }
}

class _GroupDetailPanel extends StatelessWidget {
  const _GroupDetailPanel({required this.controller});

  final TeacherGroupsController controller;

  @override
  Widget build(BuildContext context) {
    final group = controller.selectedGroup!;
    final invite = controller.activeInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              Text(
                group.name,
                style: AppTheme.headingLarge.copyWith(
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
                'Group invite code',
                style: AppTheme.headingMedium.copyWith(
                  fontSize: 16,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (invite == null)
                Text(
                  'No active invite code.',
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
                      child: const Text('Rotate code'),
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
          title: 'Pending join requests',
          emptyMessage: 'No pending requests.',
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
          title: 'Approved members',
          emptyMessage: 'No approved members yet.',
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
                          membership.status.name,
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

Future<void> _showCreateGroupDialog(
  BuildContext context,
  TeacherGroupsController controller,
) async {
  final nameController = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Create group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter a class or group name.'),
          const SizedBox(height: AppSpacing.sm),
          TextBox(
            controller: nameController,
            placeholder: 'BSHM 4A',
            autofocus: true,
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Create'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.createGroup(nameController.text);
  }
  nameController.dispose();
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
        'Archived groups stop accepting new join requests. Existing approved '
        'memberships remain for Classroom Authorization until you remove members.',
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
  if (accepted == true) await controller.archiveSelectedGroup();
}

Future<void> _confirmRotateInvite(
  BuildContext context,
  TeacherGroupsController controller,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Rotate invite code?'),
      content: const Text(
        'The current group code will stop working. Share the new code with '
        'Trainees who still need to join.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Rotate code'),
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
        'This removes Classroom Authorization for this group. It does not revoke '
        'Progress Access or General Evidence Access on the legacy Teacher link.',
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
