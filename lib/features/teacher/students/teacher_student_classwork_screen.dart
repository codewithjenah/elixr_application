import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../../assigned_movements/assigned_movement_list.dart';
import '../classwork/teacher_classwork_controller.dart';
import '../classwork/teacher_classwork_pane.dart';

class TeacherStudentClassworkScreen extends StatefulWidget {
  const TeacherStudentClassworkScreen({
    super.key,
    required this.traineeId,
    required this.groupId,
    this.assignmentId,
  });
  final String traineeId;
  final String groupId;
  final String? assignmentId;
  @override
  State<TeacherStudentClassworkScreen> createState() =>
      _TeacherStudentClassworkScreenState();
}

class _TeacherStudentClassworkScreenState
    extends State<TeacherStudentClassworkScreen> {
  TeacherClassworkController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final teacher = auth.currentUser;
    final assignments = _maybeRead<ClassroomAssignmentRepository>(context);
    final teacherId = teacher?.id;
    if (teacher == null || teacherId == null || assignments == null) return;
    _controller = TeacherClassworkController(
      teacherId: teacherId,
      teacherDisplayName: teacher.fullName,
      groupId: widget.groupId,
      groupRepository: context.read<GroupRepository>(),
      assignmentRepository: assignments,
      submissionRepository: _maybeRead<AssignmentSubmissionRepository>(context),
      chatRepository: _maybeRead<ChatRepository>(context),
      fixedTraineeId: widget.traineeId,
      initialAssignmentId: widget.assignmentId,
    )..start();
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const Center(child: ProgressRing());
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: widget.assignmentId == null
              ? 'Student classwork'
              : 'Assignment review',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              label: widget.assignmentId == null
                  ? 'Student details'
                  : 'Classwork',
              tooltip: 'Back',
              semanticLabel: 'Back',
              onPressed: () => context.go(
                widget.assignmentId == null
                    ? AppRoutePaths.teacherStudentDetail(
                        widget.traineeId,
                        groupId: widget.groupId,
                      )
                    : AppRoutePaths.teacherStudentClasswork(
                        widget.traineeId,
                        groupId: widget.groupId,
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _ClassworkBody(
                controller: controller,
                traineeId: widget.traineeId,
                groupId: widget.groupId,
                assignmentId: widget.assignmentId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassworkBody extends StatelessWidget {
  const _ClassworkBody({
    required this.controller,
    required this.traineeId,
    required this.groupId,
    required this.assignmentId,
  });
  final TeacherClassworkController controller;
  final String traineeId;
  final String groupId;
  final String? assignmentId;
  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const Center(child: ProgressRing());
    if (controller.unauthorized || !controller.fixedStudentAuthorized)
      return ElixStatusPanel(
        isError: true,
        message:
            controller.errorMessage ??
            'This student is not approved for this class.',
      );
    final review = assignmentId == null
        ? null
        : controller.assignmentById(assignmentId!);
    if (assignmentId != null && review == null)
      return const ElixStatusPanel(
        message: 'This assignment is not available.',
      );
    if (review != null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(review.displayTitle, style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${review.groupName}${review.dueAt == null ? '' : ' · Due ${review.dueAt}'}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: TeacherSubmissionReviewDetail(
              controller: controller,
              assignment: review,
              traineeId: traineeId,
              desktopReview: true,
            ),
          ),
        ],
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(controller.traineeName(traineeId), style: AppTheme.headingMedium),
        Text(
          'Assignments and submissions in ${controller.group?.name ?? 'this classroom'}.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: controller.assignments.isEmpty
              ? const ElixStatusPanel(
                  message:
                      'No classwork has been assigned to this student yet.',
                )
              : ListView.separated(
                  itemCount: controller.assignments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _AssignmentRow(
                    controller: controller,
                    assignment: controller.assignments[index],
                    traineeId: traineeId,
                    // Replace this route so the list controller is disposed before
                    // the dedicated review workspace starts its own live streams.
                    onOpen: () => context.go(
                      AppRoutePaths.teacherStudentAssignmentReview(
                        traineeId,
                        groupId: groupId,
                        assignmentId: controller.assignments[index].id,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.controller,
    required this.assignment,
    required this.traineeId,
    required this.onOpen,
  });
  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final String traineeId;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final attempt = controller.latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: traineeId,
    );
    final status = _status(assignment, attempt);
    return Semantics(
      button: true,
      label: 'Open ${assignment.displayTitle}, $status',
      child: HoverButton(
        cursor: SystemMouseCursors.click,
        onPressed: onOpen,
        builder: (context, states) => ElixPanelCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.displayTitle,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${assignment.isOfficial ? 'Official ELIXR' : 'Teacher-created'}${assignment.topic == null ? '' : ' · ${assignment.topic}'}${assignment.dueAt == null ? '' : ' · Due ${assignment.dueAt}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status,
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(FluentIcons.chevron_right, size: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _status(GroupAssignment assignment, AssignmentAttempt? attempt) {
  if (attempt == null || !isAssignmentAttemptTurnedIn(attempt))
    return assignment.isOverdue ? 'Missing' : 'Not turned in';
  return assignedMovementStatusLabel(
    assignment,
    attempt,
    attempt.isTeacherReviewSubmission ? attempt : null,
  );
}
