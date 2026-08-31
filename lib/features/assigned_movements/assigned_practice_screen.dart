import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assessment_mode.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/session_assignment_context.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../features/practice/live_practice_screen.dart';
import '../../features/practice/practice_screen.dart';
import '../../services/auth_service.dart';
import '../../services/tutorial_progress_service.dart';

enum AssignedPracticeDispatch {
  officialGuided,
  teacherReviewed,
  retiredTemplate,
  invalid,
}

AssignedPracticeDispatch dispatchAssignedPractice(GroupAssignment assignment) {
  if (assignment.isRetiredTemplate) {
    return AssignedPracticeDispatch.retiredTemplate;
  }
  if (!assignment.isActive) return AssignedPracticeDispatch.invalid;
  if (assignment.isOfficial) {
    if (assignment.assessmentMode != AssessmentMode.officialGuided) {
      return AssignedPracticeDispatch.invalid;
    }
    return AssignedPracticeDispatch.officialGuided;
  }
  if (assignment.assessmentMode == AssessmentMode.teacherReviewed) {
    if (assignment.assessmentSpec != null) {
      return AssignedPracticeDispatch.invalid;
    }
    return AssignedPracticeDispatch.teacherReviewed;
  }
  return AssignedPracticeDispatch.invalid;
}

class AssignedPracticeScreen extends StatefulWidget {
  const AssignedPracticeScreen({super.key, required this.assignmentId});

  final String assignmentId;

  @override
  State<AssignedPracticeScreen> createState() => _AssignedPracticeScreenState();
}

class _AssignedPracticeScreenState extends State<AssignedPracticeScreen> {
  bool _loading = true;
  String? _error;
  Widget? _child;
  GroupAssignment? _assignment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final assignmentId = widget.assignmentId.trim();
    if (assignmentId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This assignment link is not valid.';
      });
      return;
    }
    final traineeId = context.read<AuthService>().currentUser?.id;
    if (traineeId == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in as a trainee to open this assignment.';
      });
      return;
    }
    try {
      final assignments = context.read<ClassroomAssignmentRepository>();
      final groups = context.read<GroupRepository>();
      final assignment = await assignments.getAssignment(
        assignmentId: assignmentId,
      );
      if (!mounted) return;
      if (assignment == null) {
        setState(() {
          _loading = false;
          _error = 'This assignment is not available.';
        });
        return;
      }
      _assignment = assignment;
      if (assignment.isRetiredTemplate) {
        setState(() {
          _loading = false;
          _error =
              'Automatic template assessment has been retired. This historical assignment is read-only; previous scores remain available.';
        });
        return;
      }
      if (!assignment.isActive) {
        setState(() {
          _loading = false;
          _error = 'This assignment has been archived.';
        });
        return;
      }
      final memberships = await groups
          .watchTraineeMemberships(traineeId: traineeId)
          .first;
      if (!mounted) return;
      final authorized =
          memberships.any(
            (membership) =>
                membership.groupId == assignment.groupId &&
                membership.teacherId == assignment.teacherId &&
                membership.traineeId == traineeId &&
                membership.hasClassroomAuthorization,
          ) &&
          assignment.isAvailableToTrainee(traineeId);
      if (!authorized) {
        setState(() {
          _loading = false;
          _error = 'This assignment is not available to your account.';
        });
        return;
      }
      if (assignment.isTeacherCreated && assignment.isOverdue) {
        setState(() {
          _loading = false;
          _error = 'This assignment is past its due date.';
        });
        return;
      }
      if (assignment.isTeacherCreated) {
        final current = await _currentSubmission(
          assignments: assignments,
          traineeId: traineeId,
          assignmentId: assignment.id,
        );
        if (!mounted) return;
        if (current?.status == AssignmentAttemptStatus.submitted) {
          setState(() {
            _loading = false;
            _error =
                'This submission is awaiting your Teacher\'s check. Open the assignment to view it.';
          });
          return;
        }
        if (current?.status == AssignmentAttemptStatus.checked) {
          setState(() {
            _loading = false;
            _error =
                'This submission has been checked. Open the assignment to view the grade and feedback.';
          });
          return;
        }
        if (current?.status == AssignmentAttemptStatus.unsubmitting) {
          setState(() {
            _loading = false;
            _error =
                'This submission is being withdrawn. Return to the assignment and retry if needed.';
          });
          return;
        }
      }
      switch (dispatchAssignedPractice(assignment)) {
        case AssignedPracticeDispatch.officialGuided:
          await _openOfficial(assignment);
        case AssignedPracticeDispatch.teacherReviewed:
          setState(() {
            _loading = false;
            _child = LivePracticeScreen(
              teacherCreatedAssignment: TeacherCreatedAssignmentPractice(
                assignment: assignment,
              ),
            );
          });
        case AssignedPracticeDispatch.retiredTemplate:
          setState(() {
            _loading = false;
            _error =
                'Automatic template assessment has been retired. This historical assignment is read-only.';
          });
        case AssignedPracticeDispatch.invalid:
          setState(() {
            _loading = false;
            _error = 'This assignment cannot be opened.';
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this assignment. Try again.';
      });
    }
  }

  Future<AssignmentAttempt?> _currentSubmission({
    required ClassroomAssignmentRepository assignments,
    required String traineeId,
    required String assignmentId,
  }) async {
    final attempts = await assignments
        .watchAttemptsForTrainee(traineeId: traineeId)
        .first;
    AssignmentAttempt? canonical;
    AssignmentAttempt? legacy;
    for (final attempt in attempts) {
      if (attempt.assignmentId != assignmentId ||
          !attempt.isTeacherReviewSubmission ||
          attempt.isAbandonedTeacherReviewDraft) {
        continue;
      }
      if (attempt.isCanonicalTeacherReviewSubmission) {
        canonical = attempt;
      } else if (legacy == null ||
          (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
            legacy.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        legacy = attempt;
      }
    }
    return canonical ?? legacy;
  }

  Future<void> _openOfficial(GroupAssignment assignment) async {
    final catalogName = assignment.officialMovementName ?? '';
    final identity = officialElixrIdentityForName(catalogName);
    if (identity == null ||
        identity.movementId != assignment.movementId ||
        identity.revisionId != assignment.revisionId) {
      setState(() {
        _loading = false;
        _error = 'This official assignment is malformed.';
      });
      return;
    }
    final catalog = movementCatalog.where((m) => m.name == catalogName);
    if (catalog.isEmpty || !catalog.first.enabled) {
      setState(() {
        _loading = false;
        _error = 'This official movement is not available.';
      });
      return;
    }
    final movement = catalog.first;
    final tutorials = context.read<TutorialProgressService>();
    if (!tutorials.hasCompletedLesson(movement.name)) {
      if (!mounted) return;
      context.go(
        AppRoutePaths.movementLesson(
          movement: movement.name,
          difficulty: movement.difficulty,
          prop: movement.supportedProps.first.protocolValue,
          assignmentId: assignment.id,
        ),
      );
      return;
    }
    setState(() {
      _loading = false;
      _child = _OfficialAssignedPractice(
        assignment: assignment,
        movementName: movement.name,
        difficulty: movement.difficulty,
        supportedProps: movement.supportedProps,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_child != null) return _child!;
    return ElixScaffoldPage(
      content: Center(
        child: _loading
            ? const ProgressRing()
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error ?? 'This assignment could not be opened.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Button(
                        onPressed: () {
                          final assignment = _assignment;
                          context.go(
                            assignment == null
                                ? AppRoutePaths.teacherAccess
                                : AppRoutePaths.assignmentDetail(assignment.id),
                          );
                        },
                        child: Text(
                          _assignment == null
                              ? 'Back to Classroom'
                              : 'Back to assignment',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Button(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _load();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Prop choice shown before official guided practice when more than one
/// training prop is supported. Start still mounts [PracticeScreen].
class AssignedPracticePropPicker extends StatelessWidget {
  const AssignedPracticePropPicker({
    super.key,
    required this.movementName,
    required this.selectedProp,
    required this.supportedProps,
    required this.onPropChanged,
    required this.onStart,
    required this.onBack,
  });

  final String movementName;
  final TrainingProp selectedProp;
  final List<TrainingProp> supportedProps;
  final ValueChanged<TrainingProp> onPropChanged;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElixEditorialHeader(
          heading: movementName,
          variant: ElixEditorialHeaderVariant.compact,
        ),
        const SizedBox(height: AppSpacing.md),
        InfoLabel(
          label: 'Training prop',
          child: ComboBox<TrainingProp>(
            value: selectedProp,
            items: [
              for (final prop in supportedProps)
                ComboBoxItem(value: prop, child: Text(prop.displayLabel)),
            ],
            onChanged: (value) {
              if (value == null) return;
              onPropChanged(value);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onStart,
          child: const Text('Start guided practice'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Button(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

class _OfficialAssignedPractice extends StatefulWidget {
  const _OfficialAssignedPractice({
    required this.assignment,
    required this.movementName,
    required this.difficulty,
    required this.supportedProps,
  });

  final GroupAssignment assignment;
  final String movementName;
  final String difficulty;
  final List<TrainingProp> supportedProps;

  @override
  State<_OfficialAssignedPractice> createState() =>
      _OfficialAssignedPracticeState();
}

class _OfficialAssignedPracticeState extends State<_OfficialAssignedPractice> {
  late TrainingProp _prop = widget.supportedProps.first;
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (_started || widget.supportedProps.length == 1) {
      return PracticeScreen(
        movement: widget.movementName,
        difficulty: widget.difficulty,
        prop: _prop,
        assignmentContext: SessionAssignmentContext(
          assignmentId: widget.assignment.id,
          groupId: widget.assignment.groupId,
          teacherId: widget.assignment.teacherId,
          movementId: widget.assignment.movementId,
          revisionId: widget.assignment.revisionId,
        ),
      );
    }
    return ElixScaffoldPage(
      content: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AssignedPracticePropPicker(
              movementName: widget.movementName,
              selectedProp: _prop,
              supportedProps: widget.supportedProps,
              onPropChanged: (value) => setState(() => _prop = value),
              onStart: () => setState(() => _started = true),
              onBack: () => context.go(
                AppRoutePaths.assignmentDetail(widget.assignment.id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
