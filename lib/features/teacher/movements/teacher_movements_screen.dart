import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../../services/auth_service.dart';
import 'teacher_movement_builder_dialog.dart';
import 'teacher_movements_controller.dart';
import 'teacher_reviews_pane.dart';

class TeacherMovementsScreen extends StatefulWidget {
  const TeacherMovementsScreen({super.key, this.controller});

  final TeacherMovementsController? controller;

  @override
  State<TeacherMovementsScreen> createState() => _TeacherMovementsScreenState();
}

class _TeacherMovementsScreenState extends State<TeacherMovementsScreen> {
  TeacherMovementsController? _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    _controller = TeacherMovementsController(
      teacherId: userId,
      teacherDisplayName: user.fullName,
      groupRepository: context.read<GroupRepository>(),
      movementRepository: context.read<TeacherMovementRepository>(),
      assignmentRepository: context.read<ClassroomAssignmentRepository>(),
      submissionRepository: context.read<AssignmentSubmissionRepository>(),
    )..start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: PageHeader(title: Text('Movements')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: PageHeader(
            title: const Text('Movements'),
            commandBar: controller.tab == TeacherMovementsTab.mine
                ? CommandBar(
                    mainAxisAlignment: MainAxisAlignment.end,
                    primaryItems: [
                      CommandBarButton(
                        icon: const Icon(FluentIcons.add),
                        label: const Text('Create movement'),
                        onPressed: controller.busy
                            ? null
                            : () => _showCreateOrEditMovement(
                                context,
                                controller,
                              ),
                      ),
                    ],
                  )
                : null,
          ),
          scrollable: false,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final tab in TeacherMovementsTab.values)
                    ToggleButton(
                      checked: controller.tab == tab,
                      onChanged: (_) => controller.setTab(tab),
                      child: Text(_tabLabel(tab)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (controller.errorMessage != null) ...[
                InfoBar(
                  title: const Text('Could not complete that action'),
                  content: Text(controller.errorMessage!),
                  severity: InfoBarSeverity.error,
                  onClose: () {},
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Expanded(child: _TabBody(controller: controller)),
            ],
          ),
        );
      },
    );
  }

  static String _tabLabel(TeacherMovementsTab tab) {
    return switch (tab) {
      TeacherMovementsTab.official => 'Official ELIXR',
      TeacherMovementsTab.mine => 'My Movements',
      TeacherMovementsTab.assignments => 'Assignments',
      TeacherMovementsTab.reviews => 'Reviews',
    };
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.errorMessage != null &&
        controller.myMovements.isEmpty &&
        controller.assignments.isEmpty &&
        controller.groups.isEmpty) {
      return ElixStatusPanel(
        message: controller.errorMessage!,
        isError: true,
        actionLabel: 'Retry',
        onAction: controller.retry,
      );
    }
    return switch (controller.tab) {
      TeacherMovementsTab.official => _OfficialList(controller: controller),
      TeacherMovementsTab.mine => _MyMovementsList(controller: controller),
      TeacherMovementsTab.assignments => _AssignmentsList(
        controller: controller,
      ),
      TeacherMovementsTab.reviews => TeacherReviewsPane(controller: controller),
    };
  }
}

class _OfficialList extends StatelessWidget {
  const _OfficialList({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: controller.officialCatalog.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final movement = controller.officialCatalog[index];
        return ElixPanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(movement.name, style: AppTheme.headingMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${movement.difficulty} · Official ELIXR guided assessment · '
                      '${movement.supportedProps.map((prop) => prop.displayLabel).join(', ')}',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      movement.description,
                      style: AppTheme.body.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Button(
                onPressed: controller.busy
                    ? null
                    : () => _showAssignDialog(
                        context,
                        controller,
                        official: movement,
                      ),
                child: const Text('Assign'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MyMovementsList extends StatelessWidget {
  const _MyMovementsList({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.myMovements.isEmpty) {
      return const ElixStatusPanel(
        message:
            'No Teacher-created movements yet. Create one to assign a teacher-reviewed exercise.',
      );
    }
    return ListView.separated(
      itemCount: controller.myMovements.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final movement = controller.myMovements[index];
        return ElixPanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(movement.title, style: AppTheme.headingMedium),
                    const SizedBox(height: 4),
                    Text(
                      controller.movementModeLabel(movement),
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (controller.canManageMovement(movement)) ...[
                Button(
                  onPressed: controller.busy
                      ? null
                      : () => _showCreateOrEditMovement(
                          context,
                          controller,
                          existing: movement,
                        ),
                  child: const Text('Edit'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Button(
                  onPressed: controller.busy
                      ? null
                      : () => _showAssignDialog(
                          context,
                          controller,
                          custom: movement,
                        ),
                  child: const Text('Assign'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Button(
                  onPressed: controller.busy
                      ? null
                      : () => _confirmArchiveMovement(
                          context,
                          controller,
                          movement,
                        ),
                  child: const Text('Archive'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AssignmentsList extends StatelessWidget {
  const _AssignmentsList({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.assignments.isEmpty) {
      return const ElixStatusPanel(
        message:
            'No assignments yet. Assign an Official ELIXR or My Movement item to a class.',
      );
    }
    return ListView.separated(
      itemCount: controller.assignments.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final assignment = controller.assignments[index];
        final attempts = controller.attemptsFor(assignment.id);
        final submitted = attempts
            .where(
              (attempt) =>
                  attempt.status == AssignmentAttemptStatus.submitted ||
                  attempt.attemptKind == AssignmentAttemptKind.practicePointer,
            )
            .length;
        final inProgress = attempts.length - submitted;
        return ElixPanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(assignment.displayTitle, style: AppTheme.headingMedium),
              const SizedBox(height: 4),
              Text(
                '${controller.groupName(assignment.groupId)} · '
                '${assignment.origin.displayLabel} · '
                '${assignment.isActive ? 'Active' : 'Archived'}'
                '${assignment.dueAt == null ? '' : ' · Due ${_formatDue(assignment.dueAt!)}'}',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                assignment.isOfficial
                    ? 'Classroom results: $submitted completed'
                    : 'Classroom attempts: $inProgress in progress, $submitted submitted',
                style: AppTheme.body,
              ),
              if (attempts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final attempt in attempts.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _attemptLine(attempt),
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _attemptLine(AssignmentAttempt attempt) {
    if (attempt.attemptKind == AssignmentAttemptKind.practicePointer) {
      final total = attempt.rubricTotal;
      final level = attempt.performanceLevel?.label;
      return 'Completed official practice'
          '${total == null ? '' : ' · $total/12'}'
          '${level == null ? '' : ' · $level'}';
    }
    if (attempt.attemptKind == AssignmentAttemptKind.templateScore) {
      final total = attempt.rubricTotal;
      final level = attempt.performanceLevel?.label;
      return 'Historical template score'
          '${total == null ? '' : ' · $total/12'}'
          '${level == null ? '' : ' · $level'}';
    }
    return 'Teacher-reviewed practice · ${attempt.status.wireValue}';
  }

  static String _formatDue(DateTime dueAt) {
    final local = dueAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

Future<void> _confirmArchiveMovement(
  BuildContext context,
  TeacherMovementsController controller,
  TeacherMovement movement,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Archive this movement?'),
      content: Text(
        '${movement.title} will no longer be available for new assignments. '
        'Existing assignments stay pinned to their revision.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.archiveMovement(movement);
  }
}

Future<void> _showCreateOrEditMovement(
  BuildContext context,
  TeacherMovementsController controller, {
  TeacherMovement? existing,
}) async {
  TeacherMovementRevision? revision;
  if (existing != null) {
    revision = await controller.movementRepository.getRevision(
      movementId: existing.id,
      revisionId: existing.currentRevisionId,
    );
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) {
      return TeacherMovementBuilderDialog(
        existing: existing,
        existingRevision: revision,
        onCreateTeacherReviewed:
            ({
              required title,
              required instructions,
              required requiredProp,
              safetyGuidance,
            }) {
              return controller.createMovement(
                title: title,
                instructions: instructions,
                requiredProp: requiredProp,
                safetyGuidance: safetyGuidance,
              );
            },
        onEditTeacherReviewed: existing == null
            ? null
            : ({
                required title,
                required instructions,
                required requiredProp,
                safetyGuidance,
              }) {
                return controller.editMovement(
                  movement: existing,
                  title: title,
                  instructions: instructions,
                  requiredProp: requiredProp,
                  safetyGuidance: safetyGuidance,
                );
              },
      );
    },
  );
}

Future<void> _showAssignDialog(
  BuildContext context,
  TeacherMovementsController controller, {
  Movement? official,
  TeacherMovement? custom,
}) async {
  if (controller.activeGroups.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('No active class'),
        content: const Text(
          'Create an active group before assigning a movement.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  ElixrGroup selected = controller.activeGroups.first;
  DateTime? dueAt;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ContentDialog(
            title: const Text('Assign movement'),
            constraints: const BoxConstraints(maxWidth: 520),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  official?.name ?? custom?.title ?? '',
                  style: AppTheme.headingMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  official == null
                      ? controller.movementModeLabel(custom!)
                      : 'Official ELIXR guided assessment',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InfoLabel(
                  label: 'Class',
                  child: ComboBox<String>(
                    value: selected.id,
                    items: [
                      for (final group in controller.activeGroups)
                        ComboBoxItem(value: group.id, child: Text(group.name)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selected = controller.activeGroups.firstWhere(
                          (group) => group.id == value,
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Checkbox(
                  checked: dueAt != null,
                  content: const Text('Set a due date'),
                  onChanged: (checked) {
                    setState(() {
                      dueAt = checked == true
                          ? DateTime.now().toUtc().add(const Duration(days: 7))
                          : null;
                    });
                  },
                ),
                if (dueAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  DatePicker(
                    selected: dueAt!.toLocal(),
                    onChanged: (value) => setState(() => dueAt = value.toUtc()),
                  ),
                ],
              ],
            ),
            actions: [
              Button(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElixPrimaryButton(
                label: 'Assign',
                expanded: false,
                dense: true,
                onPressed: controller.busy
                    ? null
                    : () async {
                        if (official != null) {
                          await controller.assignOfficial(
                            movement: official,
                            group: selected,
                            dueAt: dueAt,
                          );
                        } else if (custom != null) {
                          await controller.assignTeacherCreated(
                            movement: custom,
                            group: selected,
                            dueAt: dueAt,
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
              ),
            ],
          );
        },
      );
    },
  );
}
