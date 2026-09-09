import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assessment_spec.dart';
import '../../data/models/classroom_exceptions.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../features/practice/practice_screen.dart';
import '../../services/auth_service.dart';

/// Assigned automatic Wrist Stall practice. Uses the frozen assignment spec
/// and never writes official sessions, XP, or Teacher Review reservations.
class TemplateScoredPracticeScreen extends StatefulWidget {
  const TemplateScoredPracticeScreen({super.key, required this.assignment});

  final GroupAssignment assignment;

  @override
  State<TemplateScoredPracticeScreen> createState() =>
      _TemplateScoredPracticeScreenState();
}

class _TemplateScoredPracticeScreenState
    extends State<TemplateScoredPracticeScreen> {
  bool _started = false;

  GroupAssignment get _assignment => widget.assignment;

  void _leave() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(AppRoutePaths.assignmentDetail(_assignment.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _assignment.assessmentSpec;
    if (spec == null || !spec.isCanonicalWristStallV1) {
      return ElixScaffoldPage(
        content: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'This automatic assessment is not available.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Button(
                    onPressed: _leave,
                    child: const Text('Back to assignment'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_started) {
      return PracticeScreen(
        movement: AssessmentSpec.protocolMovementName,
        difficulty: 'Easy',
        prop: TrainingProp.bottle,
        assessmentSpec: spec,
        sessionPurpose: 'template_scored',
        presentationTitle: _assignment.displayTitle,
        exitLocation: AppRoutePaths.assignmentDetail(_assignment.id),
        onCustomAssessmentComplete:
            ({required rubric, required durationSeconds}) {
              final traineeId = context.read<AuthService>().currentUser?.id;
              if (traineeId == null) {
                throw const ClassroomException(ClassroomError.forbidden);
              }
              return context
                  .read<ClassroomAssignmentRepository>()
                  .submitTemplateScore(
                    traineeId: traineeId,
                    assignment: _assignment,
                    rubric: rubric,
                    durationSeconds: durationSeconds,
                  );
            },
      );
    }
    return ElixScaffoldPage(
      content: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ElixPanelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_assignment.displayTitle, style: AppTheme.headingMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      const ElixPill(
                        text: 'Automatic ELIXR Assessment',
                        color: AppColors.accent,
                        compact: true,
                      ),
                      ElixPill(
                        text: spec.templateLabel,
                        color: AppColors.accent,
                        compact: true,
                      ),
                      const ElixPill(
                        text: 'Bottle',
                        color: AppColors.accent,
                        compact: true,
                      ),
                      ElixPill(
                        text: spec.lateralityLabel,
                        color: AppColors.accent,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'ELIXR will automatically check this Wrist Stall using a '
                    'Bottle and the selected wrist.',
                    style: AppTheme.body.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  if (_assignment.displayInstructions != null &&
                      _assignment.displayInstructions!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Instructions', style: AppTheme.cardTitle()),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _assignment.displayInstructions!,
                      style: AppTheme.body,
                    ),
                  ],
                  if (_assignment.displaySafetyGuidance != null &&
                      _assignment
                          .displaySafetyGuidance!
                          .trim()
                          .isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Safety', style: AppTheme.cardTitle()),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _assignment.displaySafetyGuidance!,
                      style: AppTheme.body,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElixPrimaryButton(
                    label: 'Start Activity',
                    expanded: true,
                    icon: FluentIcons.play,
                    onPressed: () => setState(() => _started = true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Button(
                    onPressed: _leave,
                    child: const Text('Back to assignment'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
