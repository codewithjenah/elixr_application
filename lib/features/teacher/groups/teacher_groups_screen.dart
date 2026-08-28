import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../../teacher_access/trainee_class_card.dart';
import 'teacher_groups_controller.dart';

const double _groupsWideBreakpoint = 1080;
const double _groupsCompactBreakpoint = 760;

class TeacherGroupsScreen extends StatefulWidget {
  const TeacherGroupsScreen({super.key, this.controller});

  final TeacherGroupsController? controller;

  @override
  State<TeacherGroupsScreen> createState() => _TeacherGroupsScreenState();
}

class _TeacherGroupsScreenState extends State<TeacherGroupsScreen> {
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
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    _owned = TeacherGroupsController(
      repository: context.read<GroupRepository>(),
      teacherId: userId,
      teacherDisplayName: user.fullName,
      ensureTeacherAuthorization: context
          .read<AuthService>()
          .ensureTeacherAuthorizationFresh,
      assignmentRepository: _maybeRead<ClassroomAssignmentRepository>(context),
    )..start();
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
          heading: 'Groups',
          eyebrow: 'TEACHER WORKSPACE',
        ),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: 'Groups',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'Organize your trainee classes and access.',
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  key: const Key('teacher_groups_create'),
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
              : _GroupsGrid(controller: controller),
        );
      },
    );
  }
}

class _GroupsGrid extends StatelessWidget {
  const _GroupsGrid({required this.controller});

  final TeacherGroupsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(
            key: const Key('teacher_groups_error'),
            message: controller.errorMessage!,
            isError: true,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.actionMessage != null) ...[
          ElixStatusPanel(message: controller.actionMessage!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.groups.isEmpty)
          const ElixStatusPanel(
            key: Key('teacher_groups_empty'),
            message:
                'No classes yet. Create one class per section, like BSHM 4A. '
                'Students in each class stay in their own group.',
          )
        else ...[
          Row(
            children: [
              Text(
                'Your classes',
                style: AppTheme.headingMedium.copyWith(
                  fontSize: 16,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${controller.groups.length}',
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= _groupsWideBreakpoint
                  ? 3
                  : width >= _groupsCompactBreakpoint
                  ? 2
                  : 1;
              final gap = AppSpacing.md;
              final cardWidth = columns == 1
                  ? width
                  : (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final group in controller.groups)
                    SizedBox(
                      width: cardWidth,
                      child: TraineeClassCard(
                        groupId: group.id,
                        className: group.name,
                        teacherName: controller.teacherDisplayName,
                        sectionLabel: group.isActive ? 'Active' : 'Archived',
                        workItems: classCardWorkItemsFromAssignments(
                          controller.assignmentsFor(group.id),
                        ),
                        ownerInitials: userInitials(
                          controller.teacherDisplayName,
                        ),
                        ownerPhotoUrl: context
                            .read<AuthService>()
                            .currentUser
                            ?.profilePictureUrl,
                        cardKey: Key('teacher_group_card_${group.id}'),
                        onOpen: () {
                          context.go(AppRoutePaths.teacherGroup(group.id));
                        },
                        menuItems: (_) => [
                          MenuFlyoutItem(
                            text: const Text('Rename'),
                            onPressed: controller.busy
                                ? null
                                : () => _showRenameGroupDialog(
                                    context,
                                    controller,
                                    group,
                                  ),
                          ),
                          if (group.isActive)
                            MenuFlyoutItem(
                              text: const Text('Archive'),
                              onPressed: controller.busy
                                  ? null
                                  : () => _confirmArchiveGroup(
                                      context,
                                      controller,
                                      group,
                                    ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
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
          const Text('Enter a class name, such as BSHM 4A.'),
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
    final group = await controller.createGroup(nameController.text);
    if (group != null && context.mounted) {
      context.go(AppRoutePaths.teacherGroup(group.id));
    }
  }
  nameController.dispose();
}

Future<void> _showRenameGroupDialog(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final nameController = TextEditingController(text: group.name);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Rename group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter a new class name.'),
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
          child: const Text('Rename'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.renameGroup(group, nameController.text);
  }
  nameController.dispose();
}

Future<void> _confirmArchiveGroup(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
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
  if (accepted == true) await controller.archiveGroup(group);
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
