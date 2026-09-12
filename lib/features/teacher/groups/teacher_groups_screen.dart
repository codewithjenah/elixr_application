import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/elix_toast.dart';
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
  TeacherGroupsController? _feedbackController;
  late final bool _ownsController;
  bool _showArchived = false;

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
    _listenForFeedback();
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

  @override
  void dispose() {
    _feedbackController?.removeListener(_showActionMessage);
    if (_ownsController) {
      _owned?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _listenForFeedback();
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Classrooms',
          eyebrow: 'TEACHER WORKSPACE',
        ),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixShadThemeBridge(
          child: TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: 'Classrooms',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'Organize your trainee classes and access.',
          ),
          content: controller.loading
              ? const Center(child: ProgressRing())
              : _GroupsGrid(
                  controller: controller,
                  showArchived: _showArchived,
                  onArchivedChanged: (value) {
                    setState(() => _showArchived = value);
                  },
                ),
          ),
        );
      },
    );
  }
}

class _GroupsGrid extends StatelessWidget {
  const _GroupsGrid({
    required this.controller,
    required this.showArchived,
    required this.onArchivedChanged,
  });

  final TeacherGroupsController controller;
  final bool showArchived;
  final ValueChanged<bool> onArchivedChanged;

  @override
  Widget build(BuildContext context) {
    final visibleGroups = [
      for (final group in controller.groups)
        if (group.isActive != showArchived) group,
    ];
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
        if (controller.groups.isEmpty)
          const ElixStatusPanel(
            key: Key('teacher_groups_empty'),
            message:
                'No classes yet. Create one class per section, like BSHM 4A. '
                'Students in each class stay in their own group.',
          )
        else ...[
          ElixPanelCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final heading = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showArchived ? 'Archived classrooms' : 'Your classrooms',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 16,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${visibleGroups.length} classroom${visibleGroups.length == 1 ? '' : 's'}',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                );
                final filter = SizedBox(
                  width: 180,
                  child: shad.ShadSelect<bool>(
                    key: const Key('teacher_groups_status_filter'),
                    initialValue: showArchived,
                    options: const [
                      shad.ShadOption(value: false, child: Text('Active')),
                      shad.ShadOption(value: true, child: Text('Archived')),
                    ],
                    onChanged: (value) {
                      if (value != null) onArchivedChanged(value);
                    },
                    selectedOptionBuilder: (context, value) => Text(
                      value == true ? 'Archived' : 'Active',
                    ),
                  ),
                );
                final create = ElixPrimaryButton(
                  key: const Key('teacher_groups_create'),
                  label: 'Create classroom',
                  icon: FluentIcons.add,
                  expanded: false,
                  dense: true,
                  onPressed: controller.busy
                      ? null
                      : () => _showCreateGroupDialog(context, controller),
                );
                if (constraints.maxWidth >= _groupsCompactBreakpoint) {
                  return Row(
                    children: [
                      Expanded(child: heading),
                      filter,
                      const SizedBox(width: AppSpacing.sm),
                      create,
                    ],
                  );
                }
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [heading, filter, create],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (visibleGroups.isEmpty)
            ElixStatusPanel(
              key: const Key('teacher_groups_status_empty'),
              message: showArchived
                  ? 'No archived classrooms.'
                  : 'No active classrooms. Create a classroom to get started.',
            )
          else
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
                    for (final group in visibleGroups)
                      SizedBox(
                        width: cardWidth,
                        child: TraineeClassCard(
                          groupId: group.id,
                          className: group.name,
                          teacherName: controller.teacherDisplayName,
                          sectionLabel: () {
                            final classMetadata =
                                [group.section, group.schedule]
                                    .whereType<String>()
                                    .where((value) => value.isNotEmpty)
                                    .join(' · ');
                            if (!group.isActive) return 'Archived';
                            return classMetadata.isEmpty
                                ? 'Active'
                                : classMetadata;
                          }(),
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
                            context.push(
                              '${AppRoutePaths.teacherGroup(group.id)}?tab=overview',
                            );
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
                            if (!group.isActive)
                              MenuFlyoutItem(
                                text: const Text('Unarchive'),
                                onPressed: controller.busy
                                    ? null
                                    : () => _confirmUnarchiveGroup(
                                        context,
                                        controller,
                                        group,
                                      ),
                              ),
                            MenuFlyoutItem(
                              text: const Text('Delete permanently'),
                              onPressed: controller.busy
                                  ? null
                                  : () => _confirmPermanentlyDeleteGroup(
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
  final sectionController = TextEditingController();
  final scheduleController = TextEditingController();
  final accepted = await ElixDialog.show<bool>(
    context,
    title: 'Create classroom',
    subtitle: 'Set up a classroom workspace',
    content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter a class name, such as BSHM 4A.'),
          const SizedBox(height: AppSpacing.sm),
          shad.ShadInput(
            key: const Key('teacher_groups_create_name'),
            controller: nameController,
            placeholder: const Text('BSHM 4A'),
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          shad.ShadInput(
            controller: sectionController,
            placeholder: const Text('Section (optional)'),
          ),
          const SizedBox(height: AppSpacing.sm),
          shad.ShadInput(
            controller: scheduleController,
            placeholder: const Text('Schedule (optional, e.g. MWF 2:30–4:00 PM)'),
          ),
        ],
      ),
    actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElixPrimaryButton(
          label: 'Create', expanded: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
  );
  if (accepted == true) {
    final group = await controller.createGroup(
      nameController.text,
      section: sectionController.text,
      schedule: scheduleController.text,
    );
    if (group != null && context.mounted) {
      context.push('${AppRoutePaths.teacherGroup(group.id)}?tab=overview');
    }
  }
  nameController.dispose();
  sectionController.dispose();
  scheduleController.dispose();
}

Future<void> _showRenameGroupDialog(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final nameController = TextEditingController(text: group.name);
  final accepted = await ElixDialog.show<bool>(
    context,
    title: 'Rename classroom',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Enter a new class name.'),
        const SizedBox(height: AppSpacing.sm),
        shad.ShadInput(
          controller: nameController,
          placeholder: const Text('BSHM 4A'),
          autofocus: true,
        ),
      ],
    ),
    actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElixPrimaryButton(
          label: 'Rename', expanded: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
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
  final accepted = await ElixDialog.show<bool>(
    context,
    title: 'Archive this classroom?',
    content: const Text(
        'Students already in this class stay. New students will not be able '
        'to join with this class code.',
    ),
    actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElixPrimaryButton(
          label: 'Archive', expanded: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
  );
  if (accepted == true) await controller.archiveGroup(group);
}

Future<void> _confirmUnarchiveGroup(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final accepted = await ElixDialog.show<bool>(
    context,
    title: 'Unarchive this classroom?',
    content: const Text(
        'This classroom will return to your active classrooms. Its students, '
        'classwork, and existing class code will remain available.',
    ),
    actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElixPrimaryButton(
          key: const Key('teacher_groups_confirm_unarchive'),
          label: 'Unarchive', expanded: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
  );
  if (accepted == true) await controller.unarchiveGroup(group);
}

Future<void> _confirmPermanentlyDeleteGroup(
  BuildContext context,
  TeacherGroupsController controller,
  ElixrGroup group,
) async {
  final confirmation = TextEditingController();
  final phraseMatches = ValueNotifier(false);
  await ElixDialog.show<bool>(
    context,
    title: 'Permanently delete classroom?',
    barrierDismissible: false,
    maxWidth: 460,
    content: AnimatedBuilder(
      animation: controller,
      builder: (dialogContext, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This permanently deletes “${group.name}” and all classroom '
                      'assignments, submissions, memberships, and uploaded media.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text('Type DELETE CLASSROOM to continue.'),
                    const SizedBox(height: AppSpacing.xs),
                    shad.ShadInput(
                      key: const Key('teacher_groups_delete_confirmation'),
                      controller: confirmation,
                      enabled: !controller.busy,
                      autofocus: true,
                      onChanged: (value) =>
                          phraseMatches.value = value == 'DELETE CLASSROOM',
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      shad.ShadAlert.destructive(
                        title: Text('Could not delete classroom'),
                        description: Text(controller.errorMessage!),
                      ),
                    ],
                  ],
                ),
              ),
    actions: [
      AnimatedBuilder(
        animation: controller,
        builder: (dialogContext, _) => Button(
          onPressed: controller.busy
              ? null
              : () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
      ),
      AnimatedBuilder(
        animation: Listenable.merge([controller, phraseMatches]),
        builder: (dialogContext, _) => shad.ShadButton.destructive(
                  key: const Key('teacher_groups_confirm_delete'),
                  onPressed: phraseMatches.value && !controller.busy
                      ? () async {
                          // The controller sets busy synchronously before its first await.
                          if (controller.busy) return;
                          await controller.permanentlyDeleteClassroom(group);
                          if (!dialogContext.mounted) return;
                          if (controller.errorMessage == null) {
                            Navigator.pop(dialogContext, true);
                          }
                        }
                      : null,
                  enabled: phraseMatches.value && !controller.busy,
                  child: controller.busy
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Flexible(child: Text('Deleting...')),
                          ],
                        )
                      : const Text('Delete permanently'),
        ),
      ),
    ],
  );
  confirmation.dispose();
  phraseMatches.dispose();
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
