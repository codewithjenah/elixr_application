import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movements.dart';
import '../../../core/layout/balanced_card_grid.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/activity_learning_material_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import '../../movements/movements_presentation.dart';
import '../../learning/movement_lesson_content.dart';
import '../../../services/auth_service.dart';
import 'teacher_assignment_composer.dart';
import 'teacher_movement_builder_dialog.dart';
import 'teacher_movements_controller.dart';

String _officialVariantKey(String movementName, TrainingProp prop) =>
    '${movementName}_${prop.protocolValue}';

/// Presentation-only order for the Official ELIXR library.
///
/// Keep the shared movement catalog order unchanged: it drives practice
/// progression, while this contract keeps the teacher library pedagogically
/// ordered within each difficulty section.
const _teacherOfficialMovementDisplayOrder = <String, List<String>>{
  'Easy': [
    'Body Grip',
    'Normal Grip',
    "Bartender's Grip",
    'Reverse Grip',
    'Claw Grip',
  ],
  'Medium': [
    'Hand Stall',
    'Forearm Stall',
    'Elbow Stall',
    'Wrist Stall',
    'One Finger Stall',
  ],
  'Hard': [
    'Reverse Forearm Stall',
    'Shoulder Stall',
    'Double Hand Stall',
    'Double Forearm Stall',
    'Bottle in a tin',
  ],
};

const _teacherOfficialDifficulties = ['Easy', 'Medium', 'Hard'];

int _teacherOfficialDifficultyOrder(String difficulty) {
  final index = _teacherOfficialDifficulties.indexOf(difficulty);
  return index < 0 ? _teacherOfficialDifficulties.length : index;
}

int _teacherOfficialPropOrder(TrainingProp prop) => switch (prop) {
  TrainingProp.bottle => 0,
  TrainingProp.shaker => 1,
  TrainingProp.bottleAndShaker => 2,
};

/// Returns a presentation-ordered copy of the Official ELIXR activity steps.
///
/// This deliberately does not reorder [enabledPracticeSteps], which remains
/// the source of truth for shared trainee practice progression.
List<PracticeCatalogStep> sortTeacherOfficialActivities(
  Iterable<PracticeCatalogStep> activities,
) {
  final steps = activities.toList();
  final indexedSteps = [
    for (var index = 0; index < steps.length; index++)
      (step: steps[index], index: index),
  ];

  indexedSteps.sort((a, b) {
    final difficultyOrder = _teacherOfficialDifficultyOrder(
      a.step.movement.difficulty,
    ).compareTo(_teacherOfficialDifficultyOrder(b.step.movement.difficulty));
    if (difficultyOrder != 0) return difficultyOrder;

    final aOrder =
        _teacherOfficialMovementDisplayOrder[a.step.movement.difficulty];
    final bOrder =
        _teacherOfficialMovementDisplayOrder[b.step.movement.difficulty];
    final aMovementIndex = aOrder?.indexOf(a.step.movement.name) ?? -1;
    final bMovementIndex = bOrder?.indexOf(b.step.movement.name) ?? -1;
    final aKnown = aMovementIndex >= 0;
    final bKnown = bMovementIndex >= 0;

    if (aKnown != bKnown) return aKnown ? -1 : 1;
    if (aKnown && aMovementIndex != bMovementIndex) {
      return aMovementIndex.compareTo(bMovementIndex);
    }

    if (a.step.movement.name == b.step.movement.name) {
      final propOrder = _teacherOfficialPropOrder(
        a.step.prop,
      ).compareTo(_teacherOfficialPropOrder(b.step.prop));
      if (propOrder != 0) return propOrder;
    }

    // Keep future/unrecognized entries visible after known entries and retain
    // their input order for a stable, non-alphabetical fallback.
    return a.index.compareTo(b.index);
  });

  return [for (final item in indexedSteps) item.step];
}

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
      ensureTeacherAuthorization: auth.ensureTeacherAuthorizationFresh,
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
        header: ElixEditorialPageHeader(
          heading: 'Activity Library',
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
            heading: 'Activity Library',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle:
                'Choose official ELIXR activities or manage activities you create.',
            commandBar: controller.tab == TeacherMovementsTab.mine
                ? CommandBar(
                    mainAxisAlignment: MainAxisAlignment.end,
                    primaryItems: [
                      CommandBarButton(
                        icon: const Icon(FluentIcons.add),
                        label: const Text('Create activity'),
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
          contentPadding: EdgeInsets.zero,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElixPanelCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final tab in TeacherMovementsTab.values)
                            ToggleButton(
                              checked: controller.tab == tab,
                              onChanged: (_) => controller.setTab(tab),
                              child: Text(_tabLabel(tab)),
                            ),
                          Text(
                            controller.tab == TeacherMovementsTab.official
                                ? '${controller.officialActivities.length} guided ELIXR activities'
                                : '${controller.myMovements.length} teacher-created activities',
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                          ),
                        ],
                      ),
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
                  ],
                ),
              ),
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
      TeacherMovementsTab.mine => 'My activities',
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
        controller.groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: ElixStatusPanel(
          message: controller.errorMessage!,
          isError: true,
          actionLabel: 'Retry',
          onAction: controller.retry,
        ),
      );
    }
    return switch (controller.tab) {
      TeacherMovementsTab.official => _OfficialList(controller: controller),
      TeacherMovementsTab.mine => _MyMovementsList(controller: controller),
    };
  }
}

class _OfficialList extends StatelessWidget {
  const _OfficialList({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    final activities = controller.officialActivities;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            4,
            0,
            AppSpacing.lg,
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: CustomScrollView(
              clipBehavior: Clip.hardEdge,
              slivers: [
                for (final difficulty in _teacherOfficialDifficulties) ...[
                  ..._officialDifficultySlivers(
                    context,
                    difficulty: difficulty,
                    activities: sortTeacherOfficialActivities(
                      activities.where(
                        (step) => step.movement.difficulty == difficulty,
                      ),
                    ),
                    availableWidth: constraints.maxWidth,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _officialDifficultySlivers(
    BuildContext context, {
    required String difficulty,
    required List<PracticeCatalogStep> activities,
    required double availableWidth,
  }) {
    return [
      SliverPadding(
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.md,
            ),
            child: _DifficultyHeading(
              difficulty: difficulty,
              count: activities.length,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            final step = activities[index];
            return _OfficialMovementCard(
              movement: step.movement,
              prop: step.prop,
              busy: controller.busy,
              onViewGuide: () =>
                  _showMovementGuide(context, step.movement, step.prop),
              onAssign: () => _showAssignToClass(
                context,
                controller,
                official: step.movement,
                officialProp: step.prop,
              ),
            );
          }, childCount: activities.length),
          gridDelegate: BalancedSliverGridDelegate(
            crossAxisCount: _gridColumnsFor(availableWidth, activities.length),
            childCount: activities.length,
            mainAxisExtent: _cardExtent(
              context,
              // Five-column cards use the compact vertical layout.
              base: 430,
              growth: 180,
            ),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            maxSingleCardWidth: 460,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
    ];
  }
}

class _MyMovementsList extends StatelessWidget {
  const _MyMovementsList({required this.controller});

  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.myMovements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          title: 'Build your first Activity',
          message:
              'No activities yet. Create one to assign a teacher-reviewed exercise.',
          icon: FluentIcons.add,
          actionLabel: 'Create activity',
          onAction: controller.busy
              ? null
              : () => _showCreateOrEditMovement(context, controller),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: GridView.builder(
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            4,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          itemCount: controller.myMovements.length,
          gridDelegate: BalancedSliverGridDelegate(
            crossAxisCount: _gridColumnsFor(
              constraints.maxWidth,
              controller.myMovements.length,
            ),
            childCount: controller.myMovements.length,
            maxSingleCardWidth: 460,
            mainAxisExtent: _cardExtent(context, base: 450, growth: 200),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemBuilder: (context, index) => _CustomMovementCard(
            movement: controller.myMovements[index],
            controller: controller,
          ),
        ),
      ),
    );
  }
}

int _gridColumnsFor(double availableWidth, int itemCount) =>
    BalancedCardGrid.columnsFor(
      availableWidth: availableWidth,
      itemCount: itemCount,
      // Teacher cards use a compact vertical composition below 760px, so a
      // 180px track keeps the five-card desktop catalog in one clean row
      // after the teacher shell reserves its sidebar.
      minCardWidth: 180,
      maxColumns: 5,
      spacing: AppSpacing.md,
    );

double _cardExtent(
  BuildContext context, {
  required double base,
  required double growth,
}) {
  final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return base + ((textScale - 1).clamp(0.0, 1.5) * growth);
}

class _DifficultyHeading extends StatelessWidget {
  const _DifficultyHeading({required this.difficulty, required this.count});

  final String difficulty;
  final int count;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(difficulty);
    return Row(
      children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            difficultySectionTitle(difficulty),
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
            ),
          ),
        ),
        Text(
          '$count activities',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _OfficialMovementCard extends StatelessWidget {
  const _OfficialMovementCard({
    required this.movement,
    required this.prop,
    required this.busy,
    required this.onViewGuide,
    required this.onAssign,
  });

  final Movement movement;
  final TrainingProp prop;
  final bool busy;
  final VoidCallback onViewGuide;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(movement.difficulty);
    final variantKey = _officialVariantKey(movement.name, prop);
    return Semantics(
      container: true,
      label:
          'Official ELIXR activity: ${movement.name}, ${movement.difficulty}, ${prop.displayLabel}',
      child: _TeacherMovementHoverCard(
        focusKey: Key('teacher_movement_card_official_$variantKey'),
        accent: accent,
        onTap: onViewGuide,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760;
            final details = _OfficialMovementDetails(movement: movement);
            final actions = _OfficialMovementActions(
              movement: movement,
              prop: prop,
              busy: busy,
              onAssign: onAssign,
            );
            if (!horizontal) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MovementCardVisual(
                    movementName: movement.name,
                    accent: accent,
                    propLabel: prop.displayLabel,
                    prop: prop,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(child: details),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(width: double.infinity, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: _MovementCardVisual(
                    movementName: movement.name,
                    accent: accent,
                    propLabel: prop.displayLabel,
                    prop: prop,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 230, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OfficialMovementDetails extends StatelessWidget {
  const _OfficialMovementDetails({required this.movement});

  final Movement movement;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          movement.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: _descriptionHeight(context),
          child: Text(
            movement.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body.copyWith(
              color: context.elixTextSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  double _descriptionHeight(BuildContext context) {
    const lines = 3;
    final style = AppTheme.body.copyWith(height: 1.35);
    final textPainter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return textPainter.height * lines;
  }
}

class _OfficialMovementActions extends StatelessWidget {
  const _OfficialMovementActions({
    required this.movement,
    required this.prop,
    required this.busy,
    required this.onAssign,
  });

  final Movement movement;
  final TrainingProp prop;
  final bool busy;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final variantKey = _officialVariantKey(movement.name, prop);
    return FilledButton(
      key: Key('teacher_movement_assign_official_$variantKey'),
      onPressed: busy ? null : onAssign,
      child: const Text('Assign to class'),
    );
  }
}

class _CustomMovementCard extends StatelessWidget {
  const _CustomMovementCard({required this.movement, required this.controller});

  final TeacherMovement movement;
  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    final canManage = controller.canManageMovement(movement);
    final canDelete = controller.canDeleteMovement(movement);
    return Semantics(
      container: true,
      label: 'Teacher-created activity: ${movement.title}',
      child: _TeacherMovementHoverCard(
        focusKey: Key('teacher_movement_card_custom_${movement.id}'),
        accent: AppColors.accent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760;
            final details = _CustomMovementDetails(
              movement: movement,
              controller: controller,
            );
            final actions = _CustomMovementActions(
              movement: movement,
              controller: controller,
              canManage: canManage,
              canDelete: canDelete,
            );
            if (!horizontal) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MovementCardVisual(
                    movementName: movement.title,
                    accent: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(child: details),
                  const SizedBox(height: AppSpacing.md),
                  actions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: _MovementCardVisual(
                    movementName: movement.title,
                    accent: AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 300, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CustomMovementDetails extends StatelessWidget {
  const _CustomMovementDetails({
    required this.movement,
    required this.controller,
  });

  final TeacherMovement movement;
  final TeacherMovementsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MetadataChip(
          label: 'TEACHER-CREATED ACTIVITY',
          color: AppColors.accent,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          movement.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          controller.movementModeLabel(movement),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body.copyWith(
            color: context.elixTextSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _CustomMovementActions extends StatelessWidget {
  const _CustomMovementActions({
    required this.movement,
    required this.controller,
    required this.canManage,
    required this.canDelete,
  });

  final TeacherMovement movement;
  final TeacherMovementsController controller;
  final bool canManage;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (!canManage) {
      return Text(
        'This activity cannot be managed from this account.',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
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
            Tooltip(
              message: canDelete
                  ? 'Permanently delete this unused movement.'
                  : 'This movement is used by an assignment and cannot be deleted.',
              child: Button(
                onPressed: controller.busy || !canDelete
                    ? null
                    : () =>
                          _confirmDeleteMovement(context, controller, movement),
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: Key('teacher_movement_assign_custom_${movement.id}'),
            onPressed: controller.busy
                ? null
                : () =>
                      _showAssignToClass(context, controller, custom: movement),
            child: const Text('Assign to class'),
          ),
        ),
      ],
    );
  }
}

class _MovementCardVisual extends StatelessWidget {
  const _MovementCardVisual({
    required this.movementName,
    required this.accent,
    this.propLabel,
    this.prop,
  });

  final String movementName;
  final Color accent;
  final String? propLabel;
  final TrainingProp? prop;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Container(
      height: 132,
      width: double.infinity,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: context.isDarkTheme ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Stack(
        children: [
          Center(
            child: MovementImage(
              movementName: movementName,
              size: 118,
              prop: prop,
            ),
          ),
          if (propLabel != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: highContrast
                      ? context.elixCardSurface
                      : context.elixCardSurface.withValues(
                          alpha: context.isDarkTheme ? 0.94 : 0.90,
                        ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: Border(top: BorderSide(color: context.elixBorder)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 5,
                  ),
                  child: Text(
                    propLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: context.elixTextPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteMovement(
  BuildContext context,
  TeacherMovementsController controller,
  TeacherMovement movement,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Delete this movement?'),
      content: Text(
        '${movement.title} and all of its Activity revisions will be permanently removed. '
        'This cannot be undone.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.deleteMovement(movement);
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
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => TeacherMovementBuilderDialog(
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
        onCreateActivity:
            ({
              required title,
              required instructions,
              required requiredProp,
              required assessment,
              safetyGuidance,
            }) {
              return controller.createMovement(
                title: title,
                instructions: instructions,
                requiredProp: requiredProp,
                safetyGuidance: safetyGuidance,
                assessment: assessment,
              );
            },
        onUploadDemonstration:
            ({required localFile, required duration, required source}) =>
                controller.uploadActivityDemonstration(
                  localFile: localFile,
                  duration: duration,
                  source: source,
                ),
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
        onEditActivity: existing == null
            ? null
            : ({
                required title,
                required instructions,
                required requiredProp,
                required assessment,
                safetyGuidance,
              }) {
                return controller.editMovement(
                  movement: existing,
                  title: title,
                  instructions: instructions,
                  requiredProp: requiredProp,
                  safetyGuidance: safetyGuidance,
                  assessment: assessment,
                );
              },
      ),
    ),
  );
}

Future<void> _showAssignToClass(
  BuildContext context,
  TeacherMovementsController controller, {
  Movement? official,
  TrainingProp? officialProp,
  TeacherMovement? custom,
}) async {
  await showTeacherAssignmentComposer(
    context,
    teacherId: controller.teacherId,
    teacherDisplayName: controller.teacherDisplayName,
    groups: controller.activeGroups,
    movementRepository: controller.movementRepository,
    assignmentRepository: controller.assignmentRepository,
    groupRepository: controller.groupRepository,
    creationService: controller.assignmentCreationService,
    officialMovement: official,
    initialOfficialProp: officialProp,
    teacherCreatedMovement: custom,
    materialRepository: _tryRead<ActivityLearningMaterialRepository>(context),
  );
}

/// Read-only teacher view of the same lesson content used by trainee lessons.
/// It deliberately has no progression-service dependency or completion action.
Future<void> _showMovementGuide(
  BuildContext context,
  Movement movement,
  TrainingProp prop,
) async {
  final lesson = MovementLesson.forMovement(movement);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final screen = MediaQuery.sizeOf(dialogContext);
      // Keep enough horizontal room for the upcoming instructional video while
      // still leaving a clear margin around the dialog on smaller windows.
      final dialogWidth = (screen.width - 48).clamp(320.0, 1440.0).toDouble();
      return ContentDialog(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        title: Row(
          children: [
            Expanded(
              child: Text('${movement.name} · ${prop.displayLabel} guide'),
            ),
            Tooltip(
              message: 'Close guide',
              child: Semantics(
                label: 'Close guide',
                button: true,
                child: IconButton(
                  key: const Key('teacher_movement_guide_close'),
                  icon: const Icon(FluentIcons.chrome_close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          height: screen.height * 0.70,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              dialogContext,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumn = constraints.maxWidth >= 760;
                  final overview = _GuideOverview(
                    movement: movement,
                    prop: prop,
                    lesson: lesson,
                  );
                  final technique = _GuidePanel(
                    eyebrow: 'TECHNIQUE',
                    title: 'How to perform it',
                    icon: FluentIcons.number_sequence,
                    accent: difficultyAccentColor(movement.difficulty),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < lesson.steps.length;
                          index++
                        )
                          _GuideStep(
                            number: index + 1,
                            text: lesson.steps[index],
                          ),
                      ],
                    ),
                  );
                  final supporting = [
                    _GuidePanel(
                      eyebrow: 'SUCCESS TARGET',
                      title: 'What good looks like',
                      icon: FluentIcons.completed,
                      accent: AppColors.success,
                      child: Text(lesson.successTarget, style: AppTheme.body),
                    ),
                    _GuidePanel(
                      eyebrow: 'AVOID THIS',
                      title: 'Common mistake',
                      icon: FluentIcons.error_badge,
                      accent: AppColors.warning,
                      child: Text(lesson.commonMistake, style: AppTheme.body),
                    ),
                    if (lesson.safetyNote != null)
                      _GuidePanel(
                        eyebrow: 'SAFETY',
                        title: 'Practice safely',
                        icon: FluentIcons.shield,
                        accent: AppColors.error,
                        child: Text(lesson.safetyNote!, style: AppTheme.body),
                      ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (twoColumn)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: overview),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(flex: 3, child: technique),
                          ],
                        )
                      else ...[
                        overview,
                        const SizedBox(height: AppSpacing.md),
                        technique,
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (twoColumn)
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          children: [
                            for (final panel in supporting)
                              SizedBox(
                                width:
                                    (constraints.maxWidth - AppSpacing.md) / 2,
                                child: panel,
                              ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (final panel in supporting) ...[
                              panel,
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _GuideOverview extends StatelessWidget {
  const _GuideOverview({
    required this.movement,
    required this.prop,
    required this.lesson,
  });

  final Movement movement;
  final TrainingProp prop;
  final MovementLesson lesson;

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(movement.difficulty);
    return _GuidePanel(
      eyebrow: 'OFFICIAL ELIXR',
      title: movement.name,
      icon: FluentIcons.book_answers,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MovementCardVisual(
            movementName: movement.name,
            accent: accent,
            propLabel: prop.displayLabel,
            prop: prop,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _MetadataChip(label: movement.difficulty, color: accent),
              _MetadataChip(label: prop.displayLabel, color: accent),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            lesson.objective,
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            lesson.framing,
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  eyebrow,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTheme.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: AppTheme.body.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }
}

T? _tryRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

class _TeacherMovementHoverCard extends StatefulWidget {
  const _TeacherMovementHoverCard({
    required this.focusKey,
    required this.accent,
    required this.child,
    this.onTap,
  });

  final Key focusKey;
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_TeacherMovementHoverCard> createState() =>
      _TeacherMovementHoverCardState();
}

class _TeacherMovementHoverCardState extends State<_TeacherMovementHoverCard>
    with SingleTickerProviderStateMixin {
  static const _radius = 16.0;

  late final AnimationController _interactionController;
  late final FocusNode _focusNode;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _interactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _focusNode = FocusNode(debugLabel: 'Teacher movement card');
    _focusNode.addListener(_syncFocus);
  }

  @override
  void dispose() {
    _interactionController.dispose();
    _focusNode.dispose();
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

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _syncFocus() => _setFocused(_focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final reduceMotion = _reduceMotion;
    final baseSurface = isDark
        ? AppColors.panelSurface
        : context.elixCardSurface;

    return Focus(
      key: widget.focusKey,
      focusNode: _focusNode,
      skipTraversal: true,
      onFocusChange: _setFocused,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: AnimatedBuilder(
          animation: _interactionController,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(
              _interactionController.value,
            );
            final highContrastSurface = Color.alphaBlend(
              widget.accent.withValues(alpha: isDark ? 0.20 : 0.14),
              baseSurface,
            );
            final hoverSurface = Color.alphaBlend(
              widget.accent.withValues(alpha: (isDark ? 0.16 : 0.08) * t),
              baseSurface,
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: highContrast ? highContrastSurface : hoverSurface,
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: highContrast
                        ? context.elixBorder
                        : _focused
                        ? widget.accent
                        : Color.lerp(
                            context.elixBorder,
                            widget.accent,
                            0.22 + (0.28 * t),
                          )!,
                    width: highContrast || _focused ? 2 : 1,
                  ),
                  boxShadow: highContrast
                      ? const []
                      : [
                          BoxShadow(
                            color: const Color(
                              0xFF000000,
                            ).withValues(alpha: isDark ? 0.42 : 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 7),
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
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
