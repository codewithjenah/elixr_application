import 'dart:async';

import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/progression/assignment_prop_resolution.dart';
import '../../core/progression/practice_variant.dart';
import '../../core/progression/progression_access.dart';
import '../../core/progression/progression_catalog.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/auth_service.dart';
import '../../services/trainee_progression_service.dart';
import '../../services/tutorial_progress_service.dart';
import 'movement_lesson_content.dart';
import 'rubric_guide.dart';

class MovementLessonScreen extends StatefulWidget {
  const MovementLessonScreen({
    super.key,
    required this.movement,
    required this.difficulty,
    required this.prop,
    this.assignmentId,
  });
  final String movement;
  final String difficulty;
  final TrainingProp prop;
  final String? assignmentId;

  @override
  State<MovementLessonScreen> createState() => _MovementLessonScreenState();
}

class _MovementLessonScreenState extends State<MovementLessonScreen> {
  AssignmentGrant? _assignmentGrant;
  var _assignmentGrantLoading = false;
  var _assignmentChecked = false;

  String get movement => widget.movement;
  String get difficulty => widget.difficulty;
  TrainingProp get prop => widget.prop;
  String? get assignmentId => widget.assignmentId;

  bool get _assigned => assignmentId != null && assignmentId!.trim().isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assigned && !_assignmentChecked) {
      _assignmentChecked = true;
      _assignmentGrantLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_verifyAssignmentGrant());
      });
    }
  }

  Future<void> _verifyAssignmentGrant() async {
    final id = assignmentId?.trim() ?? '';
    final auth = Provider.of<AuthService?>(context, listen: false);
    final repo = Provider.of<ClassroomAssignmentRepository?>(
      context,
      listen: false,
    );
    if (id.isEmpty || auth == null || repo == null) {
      if (!mounted) return;
      setState(() {
        _assignmentGrant = const AssignmentGrant(isAuthorized: false);
        _assignmentGrantLoading = false;
      });
      return;
    }
    final traineeId = auth.currentUser?.id?.trim();
    if (traineeId == null || traineeId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _assignmentGrant = const AssignmentGrant(isAuthorized: false);
        _assignmentGrantLoading = false;
      });
      return;
    }
    try {
      final assignment = await repo.getAssignment(assignmentId: id);
      final authorized = _isAuthorizedAssignmentLesson(
        assignment: assignment,
        traineeId: traineeId,
        movementName: movement,
        prop: prop,
      );
      if (!mounted) return;
      setState(() {
        _assignmentGrant = AssignmentGrant(isAuthorized: authorized);
        _assignmentGrantLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assignmentGrant = const AssignmentGrant(isAuthorized: false);
        _assignmentGrantLoading = false;
      });
    }
  }

  static bool _isAuthorizedAssignmentLesson({
    required GroupAssignment? assignment,
    required String traineeId,
    required String movementName,
    required TrainingProp prop,
  }) {
    if (assignment == null || !assignment.isActive) return false;
    if (!assignment.audience.isAvailableToTrainee(traineeId)) return false;
    // Catalog lessons only accept official ELIXR assignment grants that match
    // the exact movement + pinned prop. Teacher-created activity assignments
    // use a different practice path and must not unlock arbitrary catalog rows.
    if (!assignment.isOfficial) return false;
    if (assignment.officialMovementName != movementName) return false;
    final identity = officialElixrIdentityForName(movementName);
    if (identity == null ||
        assignment.movementId != identity.movementId ||
        assignment.revisionId != identity.revisionId) {
      return false;
    }
    final resolved = resolvedAllowedPropForOfficialAssignment(
      officialMovementName: movementName,
      storedAllowedProp: assignment.allowedProp,
    );
    return resolved == prop;
  }

  @override
  Widget build(BuildContext context) {
    final item = movementCatalog.where((m) => m.name == movement).firstOrNull;
    if (item == null) {
      return const ElixScaffoldPage(
        content: Center(child: Text('This movement is not available.')),
      );
    }
    if (_assigned) {
      if (_assignmentGrantLoading) {
        return const ElixScaffoldPage(content: Center(child: ProgressRing()));
      }
      final grant = _assignmentGrant;
      if (grant == null || !grant.isAuthorized) {
        return ElixScaffoldPage(
          content: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'This assignment lesson is not available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Button(
                      onPressed: () => context.go(AppRoutePaths.teacherAccess),
                      child: const Text('Back to Classroom'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      final tutorials = Provider.of<TutorialProgressService?>(
        context,
        listen: true,
      );
      if (tutorials == null) {
        return const ElixScaffoldPage(content: Center(child: ProgressRing()));
      }
      final access = evaluateAssignment(
        variant: PracticeVariant(movementName: movement, trainingProp: prop),
        assignmentGrant: grant,
        tutorialCompleted: tutorials.isInitialized
            ? tutorials.hasCompletedLesson(movement, prop)
            : null,
      );
      if (access == ProgressionAccessResult.assignmentLoading) {
        return const ElixScaffoldPage(content: Center(child: ProgressRing()));
      }
      if (access == ProgressionAccessResult.invalid) {
        return ElixScaffoldPage(
          content: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'This assignment lesson is not available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Button(
                      onPressed: () => context.go(AppRoutePaths.teacherAccess),
                      child: const Text('Back to Classroom'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    } else {
      final progression = Provider.of<TraineeProgressionService?>(
        context,
        listen: true,
      );
      final tutorials = Provider.of<TutorialProgressService?>(
        context,
        listen: true,
      );
      if (progression == null || tutorials == null) {
        return const ElixScaffoldPage(content: Center(child: ProgressRing()));
      }
      final access = evaluatePersonal(
        variant: PracticeVariant(movementName: movement, trainingProp: prop),
        currentLevel: progression.currentLevelOrNull,
        tutorialCompleted: tutorials.isInitialized
            ? tutorials.hasCompletedLesson(movement, prop)
            : null,
      );
      if (access == ProgressionAccessResult.personalLoading) {
        return const ElixScaffoldPage(content: Center(child: ProgressRing()));
      }
      if (access == ProgressionAccessResult.personalLocked ||
          access == ProgressionAccessResult.invalid) {
        final required =
            requiredLevelFor(
              PracticeVariant(movementName: movement, trainingProp: prop),
            ) ??
            '?';
        return ElixScaffoldPage(
          content: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      access == ProgressionAccessResult.personalLocked
                          ? 'This lesson unlocks at Level $required.'
                          : 'This lesson is not available.',
                      textAlign: TextAlign.center,
                      style: AppTheme.body,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Button(
                      onPressed: () => context.go(AppRoutePaths.learn),
                      child: const Text('Back to Learning Center'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    final lesson = MovementLesson.forMovement(item);
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.pageTopInset,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 880;
                final hero = _Hero(item: item, lesson: lesson, prop: prop);
                final steps = _Panel(
                  eyebrow: 'TECHNIQUE',
                  title: 'Build the movement',
                  icon: FluentIcons.number_sequence,
                  child: Column(
                    children: [
                      for (var i = 0; i < lesson.steps.length; i++)
                        _Step(number: i + 1, text: lesson.steps[i]),
                    ],
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(movement: item.name, difficulty: item.difficulty),
                    const SizedBox(height: AppSpacing.md),
                    _Actions(
                      item: item,
                      difficulty: difficulty,
                      prop: prop,
                      assignmentId: assignmentId,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: hero),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(flex: 6, child: steps),
                        ],
                      )
                    else ...[
                      hero,
                      const SizedBox(height: AppSpacing.md),
                      steps,
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Panel(
                                eyebrow: 'SUCCESS TARGET',
                                title: 'What good looks like',
                                icon: FluentIcons.completed,
                                accent: AppColors.success,
                                child: Text(
                                  lesson.successTarget,
                                  style: AppTheme.body.copyWith(height: 1.4),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _Panel(
                                eyebrow: 'AVOID THIS',
                                title: 'Common mistake',
                                icon: FluentIcons.error_badge,
                                accent: AppColors.warning,
                                child: Text(
                                  lesson.commonMistake,
                                  style: AppTheme.body.copyWith(height: 1.4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _Panel(
                        eyebrow: 'SUCCESS TARGET',
                        title: 'What good looks like',
                        icon: FluentIcons.completed,
                        accent: AppColors.success,
                        child: Text(
                          lesson.successTarget,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Panel(
                        eyebrow: 'AVOID THIS',
                        title: 'Common mistake',
                        icon: FluentIcons.error_badge,
                        accent: AppColors.warning,
                        child: Text(
                          lesson.commonMistake,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                    if (lesson.safetyNote != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Panel(
                        eyebrow: 'SAFETY',
                        title: 'Practice safely',
                        icon: FluentIcons.shield,
                        accent: AppColors.error,
                        child: Text(
                          lesson.safetyNote!,
                          style: AppTheme.body.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const RubricGuide(compact: true),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.movement, required this.difficulty});
  final String movement, difficulty;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ElixEditorialHeader(
        heading: movement,
        eyebrow: 'MOVEMENT LESSON',
        variant: ElixEditorialHeaderVariant.compact,
      ),
      const SizedBox(height: AppSpacing.sm),
      _Pill(text: difficulty, color: AppColors.success),
    ],
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.lesson, required this.prop});
  final Movement item;
  final MovementLesson lesson;
  final TrainingProp prop;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppTheme.panelDecoration(context, highlighted: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                FluentIcons.video,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CAMERA READY',
                    style: AppTheme.caption.copyWith(
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                  Text(
                    'Use: ${prop.displayLabel}',
                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.elixBackground.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: MovementImage(movementName: item.name, size: 190),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          lesson.framing,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
  });
  final String eyebrow, title;
  final IconData icon;
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppTheme.panelDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: AppTheme.caption.copyWith(
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTheme.headingMedium.copyWith(fontSize: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final int number;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.difficulty,
    required this.prop,
    this.assignmentId,
  });
  final Movement item;
  final String difficulty;
  final TrainingProp prop;
  final String? assignmentId;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final stacked = c.maxWidth < 520;
      final assigned = assignmentId != null && assignmentId!.trim().isNotEmpty;
      final back = SizedBox(
        width: stacked ? double.infinity : 220,
        height: 52,
        child: Button(
          onPressed: () => context.go(
            assigned
                ? AppRoutePaths.assignmentDetail(assignmentId!.trim())
                : AppRoutePaths.learn,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.back, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(assigned ? 'Back to assignment' : 'Back to tutorials'),
              ],
            ),
          ),
        ),
      );
      final start = SizedBox(
        width: stacked ? double.infinity : 260,
        height: 52,
        child: ElixPrimaryButton(
          label: 'Start guided practice',
          icon: FluentIcons.play_solid,
          expanded: false,
          dense: true,
          onPressed: () async {
            await context.read<TutorialProgressService>().completeLesson(
              item.name,
              prop,
            );
            if (context.mounted) {
              context.go(
                assigned
                    ? AppRoutePaths.assignedPractice(assignmentId!.trim())
                    : '/practice?movement=${Uri.encodeComponent(item.name)}&difficulty=$difficulty&prop=${prop.protocolValue}',
              );
            }
          },
        ),
      );
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                back,
                const SizedBox(height: AppSpacing.sm),
                start,
              ],
            )
          : Row(children: [back, const Spacer(), start]);
    },
  );
}
