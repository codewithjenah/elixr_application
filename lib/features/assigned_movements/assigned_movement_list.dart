import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import 'assigned_movements_controller.dart';

/// Shared assignment rows for Assigned Movements and the class detail page.
class AssignedMovementList extends StatelessWidget {
  const AssignedMovementList({
    super.key,
    required this.items,
    this.showGroupName = true,
  });

  final List<AssignedMovementItem> items;
  final bool showGroupName;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = items[index];
        final assignment = item.assignment;
        final canStart = assignment.isActive && !assignment.isRetiredTemplate;
        final subtitle = showGroupName
            ? '${assignment.teacherDisplayName} · ${assignment.groupName} · '
                  '${assignment.origin.displayLabel}'
            : '${assignment.teacherDisplayName} · '
                  '${assignment.origin.displayLabel}';
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
                        subtitle,
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        assignedMovementStatusLine(
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
                  child: Text(
                    assignedMovementActionLabel(assignment, item.attempt),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String assignedMovementActionLabel(
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

String assignedMovementStatusLine(
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

String _attemptText(
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
