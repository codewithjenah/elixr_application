import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../movements/movements_presentation.dart';
import '../../../services/auth_service.dart';
import 'teacher_assignment_work_pane.dart';
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
      TeacherMovementsTab.assignments =>
        controller.selectedAssignmentId == null
            ? _AssignmentsList(controller: controller)
            : TeacherAssignmentWorkPane(controller: controller),
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
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: controller.officialCatalog.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final movement = controller.officialCatalog[index];
        final accent = difficultyAccentColor(movement.difficulty);
        return _TeacherMovementHoverCard(
          accent: accent,
          child: Row(
            children: [
              _TeacherMovementThumb(
                movementName: movement.name,
                accent: accent,
              ),
              const SizedBox(width: AppSpacing.md),
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
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: controller.myMovements.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final movement = controller.myMovements[index];
        return _TeacherMovementHoverCard(
          accent: AppColors.accent,
          child: Row(
            children: [
              _TeacherMovementThumb(
                movementName: movement.title,
                accent: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.md),
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
    final official = [
      for (final assignment in controller.assignments)
        if (assignment.isOfficial) assignment,
    ];
    final teacherCreated = [
      for (final assignment in controller.assignments)
        if (!assignment.isOfficial) assignment,
    ];
    return ListView(
      children: [
        if (official.isNotEmpty) ...[
          const _AssignmentOriginHeader(
            sectionKey: Key('teacher_assignments_official_section'),
            title: 'Official ELIXR',
            subtitle: 'Live guided scores. No submission clip to review.',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < official.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _assignmentCard(official[i]),
          ],
        ],
        if (official.isNotEmpty && teacherCreated.isNotEmpty)
          const SizedBox(height: AppSpacing.xl),
        if (teacherCreated.isNotEmpty) ...[
          const _AssignmentOriginHeader(
            sectionKey: Key('teacher_assignments_teacher_section'),
            title: 'Teacher-created',
            subtitle: 'Recorded clips for you to review.',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < teacherCreated.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _assignmentCard(teacherCreated[i]),
          ],
        ],
      ],
    );
  }

  Widget _assignmentCard(GroupAssignment assignment) {
    final counts = controller.rosterCountsFor(assignment.id);
    return HoverButton(
      onPressed: () => controller.selectAssignment(assignment.id),
      builder: (context, states) {
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
                'Turned in ${counts.turnedIn} · '
                'Awaiting review ${counts.awaitingReview} · '
                'Approved ${counts.approved} · '
                'Needs retry ${counts.needsRetry} · '
                'Not turned in ${counts.notTurnedIn}',
                style: AppTheme.body,
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: Button(
                  onPressed: () => controller.selectAssignment(assignment.id),
                  child: const Text('View work'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDue(DateTime dueAt) {
    final local = dueAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _AssignmentOriginHeader extends StatelessWidget {
  const _AssignmentOriginHeader({
    required this.sectionKey,
    required this.title,
    required this.subtitle,
  });

  final Key sectionKey;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: sectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.headingMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
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

class _TeacherMovementHoverCard extends StatefulWidget {
  const _TeacherMovementHoverCard({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  State<_TeacherMovementHoverCard> createState() =>
      _TeacherMovementHoverCardState();
}

class _TeacherMovementHoverCardState extends State<_TeacherMovementHoverCard>
    with SingleTickerProviderStateMixin {
  static const _radius = 16.0;

  late final AnimationController _interactionController;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _interactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _interactionController.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _syncInteraction() {
    if (_reduceMotion) {
      _interactionController.value = _hovered ? 1 : 0;
    } else if (_hovered) {
      _interactionController.forward();
    } else {
      _interactionController.reverse();
    }
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    _hovered = value;
    _syncInteraction();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final reduceMotion = _reduceMotion;
    final baseSurface = isDark
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedBuilder(
        animation: _interactionController,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_interactionController.value);
          final lift = reduceMotion ? 0.0 : 6 * t;
          final scale = reduceMotion ? 1.0 : 1 + (0.008 * t);
          final highContrastSurface = Color.alphaBlend(
            widget.accent.withValues(alpha: isDark ? 0.20 : 0.14),
            baseSurface,
          );
          return AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            transformAlignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(0, -lift, 0, 1)
              ..scaleByDouble(scale, scale, scale, 1),
            decoration: BoxDecoration(
              color: highContrast ? highContrastSurface : null,
              gradient: highContrast
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                          widget.accent.withValues(
                            alpha: (isDark ? 0.18 : 0.11) + (0.04 * t),
                          ),
                          baseSurface,
                        ),
                        Color.alphaBlend(
                          AppColors.accent.withValues(
                            alpha: isDark ? 0.08 : 0.045,
                          ),
                          baseSurface,
                        ),
                        Color.alphaBlend(
                          widget.accent.withValues(alpha: isDark ? 0.10 : 0.06),
                          baseSurface,
                        ),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(
                color: highContrast
                    ? context.elixBorder
                    : Color.lerp(
                        context.elixBorder,
                        widget.accent,
                        0.22 + (0.48 * t),
                      )!,
                width: highContrast ? 2 : 1,
              ),
              boxShadow: highContrast
                  ? const []
                  : [
                      BoxShadow(
                        color: const Color(
                          0xFF000000,
                        ).withValues(alpha: isDark ? 0.42 : 0.12),
                        blurRadius: 14 + (10 * t),
                        offset: Offset(0, 7 + (4 * t)),
                      ),
                      BoxShadow(
                        color: widget.accent.withValues(
                          alpha: (isDark ? 0.22 : 0.13) * t,
                        ),
                        blurRadius: 28,
                        spreadRadius: -6,
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: child,
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _TeacherMovementThumb extends StatelessWidget {
  const _TeacherMovementThumb({
    required this.movementName,
    required this.accent,
  });

  final String movementName;
  final Color accent;
  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withValues(alpha: context.isDarkTheme ? 0.18 : 0.1),
        border: Border.all(color: context.elixBorder),
      ),
      child: MovementImage(movementName: movementName, size: _size),
    );
  }
}
