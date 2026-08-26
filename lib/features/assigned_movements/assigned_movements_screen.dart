import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/auth_service.dart';
import 'assigned_movements_controller.dart';

class AssignedMovementsScreen extends StatefulWidget {
  const AssignedMovementsScreen({super.key, this.controller});

  final AssignedMovementsController? controller;

  @override
  State<AssignedMovementsScreen> createState() =>
      _AssignedMovementsScreenState();
}

class _AssignedMovementsScreenState extends State<AssignedMovementsScreen> {
  AssignedMovementsController? _controller;
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
    final traineeId = context.read<AuthService>().currentUser?.id;
    if (traineeId == null) return;
    _controller = AssignedMovementsController(
      traineeId: traineeId,
      groupRepository: context.read<GroupRepository>(),
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
      return const ElixScaffoldPage(content: Center(child: ProgressRing()));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          content: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assigned Movements', style: AppTheme.headingLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Classroom work from your approved groups. Public profile privacy does not hide these assignments.',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: _Body(controller: controller)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final AssignedMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.errorMessage != null && controller.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(controller.errorMessage!),
            const SizedBox(height: AppSpacing.md),
            Button(onPressed: controller.retry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (controller.items.isEmpty) {
      return Center(
        child: Text(
          'No assigned movements yet. When a teacher assigns work to one of your classes, it will appear here.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: controller.items.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = controller.items[index];
        final assignment = item.assignment;
        final canStart = assignment.isActive && !assignment.isRetiredTemplate;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.displayTitle,
                        style: AppTheme.headingMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${assignment.teacherDisplayName} · ${assignment.groupName} · '
                        '${assignment.origin.displayLabel}',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusLine(
                          assignment,
                          item.attempt,
                          item.latestSubmission,
                        ),
                        style: AppTheme.body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton(
                  onPressed: canStart
                      ? () => context.go(
                          AppRoutePaths.assignedPractice(assignment.id),
                        )
                      : null,
                  child: Text(_actionLabel(assignment, item.attempt)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _actionLabel(
    GroupAssignment assignment,
    AssignmentAttempt? attempt,
  ) {
    if (assignment.isRetiredTemplate) return 'Retired';
    if (attempt == null) return 'Start practice';
    if (attempt.status == AssignmentAttemptStatus.needsRetry) {
      return 'Record again';
    }
    if (attempt.status == AssignmentAttemptStatus.inProgress ||
        attempt.status == AssignmentAttemptStatus.draft) {
      return 'Continue practice';
    }
    return 'Practice again';
  }

  static String _statusLine(
    GroupAssignment assignment,
    AssignmentAttempt? attempt,
    AssignmentAttempt? submission,
  ) {
    if (assignment.isRetiredTemplate) {
      final total = attempt?.rubricTotal;
      final level = attempt?.performanceLevel?.label;
      return 'Historical · Automatic template assessment retired'
          '${total == null ? '' : ' · Previous score $total/12'}'
          '${level == null ? '' : ' · $level'}';
    }
    final due = assignment.dueAt;
    final dueText = due == null
        ? 'No due date'
        : assignment.isOverdue
        ? 'Overdue'
        : 'Due ${due.toLocal().toIso8601String().split('T').first}';
    final attemptText = _attemptText(assignment, attempt, submission);
    if (!assignment.isActive) return 'Archived · $attemptText';
    return '$dueText · $attemptText';
  }

  static String _attemptText(
    GroupAssignment assignment,
    AssignmentAttempt? attempt,
    AssignmentAttempt? submission,
  ) {
    if (assignment.isTeacherCreated) {
      final current = submission ?? attempt;
      if (current == null ||
          current.attemptKind == AssignmentAttemptKind.teacherReviewDraft) {
        return 'Practice available · Not submitted';
      }
      final expired = current.videoExpired ? ' · Video expired' : '';
      return switch (current.status) {
        AssignmentAttemptStatus.draft ||
        AssignmentAttemptStatus.inProgress => 'Not submitted',
        AssignmentAttemptStatus.submitted =>
          'Submitted / awaiting review$expired',
        AssignmentAttemptStatus.approved => 'Approved$expired',
        AssignmentAttemptStatus.needsRetry =>
          'Needs retry${current.reviewFeedback == null || current.reviewFeedback!.isEmpty ? '' : ' · ${current.reviewFeedback}'}$expired',
      };
    }
    return switch (attempt?.status) {
      null => 'Not started',
      AssignmentAttemptStatus.draft => 'Draft',
      AssignmentAttemptStatus.inProgress => 'In progress',
      AssignmentAttemptStatus.submitted => 'Submitted',
      AssignmentAttemptStatus.approved => 'Approved',
      AssignmentAttemptStatus.needsRetry => 'Needs retry',
    };
  }
}
