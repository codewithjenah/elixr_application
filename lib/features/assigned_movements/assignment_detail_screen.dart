import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/auth_service.dart';
import 'assigned_movement_list.dart';
import 'assignment_detail_controller.dart';
import 'widgets/submission_detail_body.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.assignmentId,
    this.controller,
  });

  final String assignmentId;
  final AssignmentDetailController? controller;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  AssignmentDetailController? _controller;
  late final bool _ownsController;
  String? _selectedAttemptId;

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
    _controller = AssignmentDetailController(
      assignmentId: widget.assignmentId,
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

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutePaths.assignedMovements);
    }
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
          padding: EdgeInsets.zero,
          content: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.pageTopInset,
              0,
              AppSpacing.lg,
            ),
            child: _Body(
              controller: controller,
              selectedAttemptId: _selectedAttemptId,
              onSelectAttempt: (id) => setState(() => _selectedAttemptId = id),
              onBack: _goBack,
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.onBack,
    required this.onSelectAttempt,
    this.selectedAttemptId,
  });

  final AssignmentDetailController controller;
  final String? selectedAttemptId;
  final ValueChanged<String> onSelectAttempt;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (!controller.authorized) {
      return _Message(
        message: controller.assignment == null
            ? (controller.errorMessage ?? 'This assignment is not available.')
            : 'You need to be accepted into this class before you can open this assignment.',
        onBack: onBack,
        onRetry: controller.errorMessage != null ? controller.retry : null,
      );
    }
    final assignment = controller.assignment;
    if (assignment == null) {
      return _Message(
        message: controller.errorMessage ?? 'This assignment is not available.',
        onBack: onBack,
        onRetry: controller.retry,
      );
    }

    final selected = _selectedAttempt(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final header = _AssignmentHeader(assignment: assignment);
        final work = _YourWork(
          controller: controller,
          assignment: assignment,
          selected: selected,
          onSelectAttempt: onSelectAttempt,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              key: const Key('assignment_detail_back'),
              label: 'Assigned movements',
              tooltip: 'Back to assigned movements',
              semanticLabel: 'Back to assigned movements',
              onPressed: onBack,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(child: header),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            key: const Key('assignment_detail_work_scroll'),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.lg,
                              ),
                              child: work,
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: AppSpacing.lg),
                            work,
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  AssignmentAttempt? _selectedAttempt(AssignmentDetailController controller) {
    if (controller.assignment?.isTeacherCreated == true) {
      return controller.currentSubmission ?? controller.latestAttempt;
    }
    final id = selectedAttemptId;
    if (id != null) {
      for (final attempt in controller.attempts) {
        if (attempt.id == id) return attempt;
      }
    }
    return controller.latestClipSubmission ?? controller.latestAttempt;
  }
}

class _AssignmentHeader extends StatelessWidget {
  const _AssignmentHeader({required this.assignment});

  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElixEditorialHeader(
            heading: assignment.displayTitle,
            variant: ElixEditorialHeaderVariant.compact,
            subtitle:
                '${assignment.teacherDisplayName} · ${assignment.groupName}',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ElixPill(
                text: assignment.origin.displayLabel,
                color: context.elixTextSecondary,
                compact: true,
              ),
              ElixPill(
                text: assignedMovementDueLabel(assignment),
                color: assignment.isOverdue
                    ? AppColors.error
                    : context.elixTextSecondary,
                compact: true,
              ),
              if (!assignment.isActive)
                ElixPill(
                  text: 'Archived',
                  color: context.elixTextSecondary,
                  compact: true,
                ),
            ],
          ),
          if (assignment.displayInstructions != null &&
              assignment.displayInstructions!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Instructions', style: AppTheme.headingMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(assignment.displayInstructions!, style: AppTheme.body),
          ],
          if (assignment.displaySafetyGuidance != null &&
              assignment.displaySafetyGuidance!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Safety', style: AppTheme.headingMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(assignment.displaySafetyGuidance!, style: AppTheme.body),
          ],
        ],
      ),
    );
  }
}

class _YourWork extends StatelessWidget {
  const _YourWork({
    required this.controller,
    required this.assignment,
    required this.onSelectAttempt,
    this.selected,
  });

  final AssignmentDetailController controller;
  final GroupAssignment assignment;
  final AssignmentAttempt? selected;
  final ValueChanged<String> onSelectAttempt;

  @override
  Widget build(BuildContext context) {
    final current = assignment.isTeacherCreated
        ? controller.currentSubmission
        : selected;
    final canStart = canStartAssignedMovement(assignment, current, current);
    return Column(
      key: const Key('assignment_detail_your_work'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your work', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        if (current == null)
          ElixPanelCard(
            child: Text(
              'You have not submitted work for this assignment yet.',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            ),
          )
        else
          SubmissionDetailBody(
            key: ValueKey(current.id),
            assignment: assignment,
            attempt: current,
            viewerRole: SubmissionDetailViewerRole.trainee,
            submissionRepository: controller.submissionRepository,
            openLocalPlayback: controller.openLocalPlayback,
            releaseLocalPlayback: controller.releaseLocalPlayback,
          ),
        if (assignment.isTeacherCreated &&
            current?.hasAttachedDraftClip == true) ...[
          const SizedBox(height: AppSpacing.md),
          if (controller.turnInErrorMessage != null)
            InfoBar(
              title: const Text('Could not turn in recording'),
              content: Text(controller.turnInErrorMessage!),
              severity: InfoBarSeverity.error,
              onClose: () {},
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Recording attached. Your Teacher cannot see it until you turn it in.',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: controller.turnInBusy
                      ? null
                      : () => _confirmTurnIn(
                          context,
                          controller,
                          assignment,
                          current!,
                        ),
                  child: controller.turnInBusy
                      ? const ProgressRing()
                      : const Text('Turn in'),
                ),
                Button(
                  onPressed: controller.draftRemovalBusy
                      ? null
                      : () => controller.removeAttachedDraft(),
                  child: Text(
                    controller.draftRemovalBusy
                        ? 'Removing…'
                        : 'Remove recording',
                  ),
                ),
              ],
            ),
          ),
        ],
        if (assignment.isTeacherCreated &&
            current?.isDraftClipRemovalPending == true) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            controller.draftRemovalErrorMessage ??
                'Removing the attached recording…',
            style: AppTheme.bodySecondary.copyWith(
              color: controller.draftRemovalErrorMessage == null
                  ? context.elixTextSecondary
                  : AppColors.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            onPressed: controller.draftRemovalBusy
                ? null
                : controller.removeAttachedDraft,
            child: const Text('Retry removal'),
          ),
        ],
        if (!assignment.isTeacherCreated && controller.attempts.length > 1) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Attempt history', style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final attempt in controller.attempts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AttemptHistoryRow(
                assignment: assignment,
                attempt: attempt,
                selected: selected?.id == attempt.id,
                onTap: () => onSelectAttempt(attempt.id),
              ),
            ),
        ],
        if (assignment.isTeacherCreated &&
            current?.status == AssignmentAttemptStatus.submitted) ...[
          const SizedBox(height: AppSpacing.md),
          if (controller.unsubmitErrorMessage != null)
            InfoBar(
              title: const Text('Could not withdraw the clip'),
              content: Text(controller.unsubmitErrorMessage!),
              severity: InfoBarSeverity.error,
              onClose: () {},
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: controller.unsubmitBusy || !controller.canUnsubmit
                  ? null
                  : () => _confirmUnsubmit(context, controller),
              child: controller.unsubmitBusy
                  ? const ProgressRing()
                  : const Text('Unsubmit'),
            ),
          ),
          if (!controller.canUnsubmit && !controller.unsubmitBusy)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                assignment.isOverdue
                    ? 'Unsubmit is unavailable after the deadline.'
                    : 'This submission can no longer be withdrawn.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ),
        ],
        if (assignment.isTeacherCreated &&
            current?.status == AssignmentAttemptStatus.unsubmitting) ...[
          const SizedBox(height: AppSpacing.md),
          if (controller.unsubmitErrorMessage != null)
            InfoBar(
              title: const Text('Clip withdrawal needs a retry'),
              content: Text(controller.unsubmitErrorMessage!),
              severity: InfoBarSeverity.error,
              onClose: () {},
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: controller.unsubmitBusy || !controller.canUnsubmit
                  ? null
                  : () => _confirmUnsubmit(context, controller),
              child: controller.unsubmitBusy
                  ? const ProgressRing()
                  : const Text('Retry withdrawal'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (canStart)
          ElixPrimaryButton(
            label: assignedMovementActionLabel(assignment, current),
            expanded: true,
            icon: FluentIcons.play,
            onPressed: () =>
                context.go(AppRoutePaths.assignedPractice(assignment.id)),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: ElixPill(
              text: assignedMovementActionLabel(assignment, current),
              color: context.elixTextSecondary,
            ),
          ),
      ],
    );
  }
}

Future<void> _confirmUnsubmit(
  BuildContext context,
  AssignmentDetailController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Unsubmit this clip?'),
      content: const Text(
        'The submitted clip will be removed and this assignment will return '
        'to in progress. You can record and submit a new clip while the '
        'assignment is still open.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Unsubmit'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.unsubmit();
}

Future<void> _confirmTurnIn(
  BuildContext context,
  AssignmentDetailController controller,
  GroupAssignment assignment,
  AssignmentAttempt attempt,
) async {
  final duration = attempt.videoDurationMs == null
      ? 'Recording attached'
      : 'Recording duration ${formatSubmissionDurationMs(attempt.videoDurationMs!)}';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Turn in your work?'),
      content: Text(
        '${assignment.displayTitle}\n$duration\n\n'
        'This recording will be submitted to ${assignment.teacherDisplayName} for checking.',
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Turn in'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.turnIn();
}

class _AttemptHistoryRow extends StatelessWidget {
  const _AttemptHistoryRow({
    required this.assignment,
    required this.attempt,
    required this.selected,
    required this.onTap,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt attempt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when =
        attempt.submittedAt ?? attempt.completedAt ?? attempt.createdAt;
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        return ElixPanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignedMovementStatusLabel(
                        assignment,
                        attempt,
                        attempt.isTeacherReviewSubmission ? attempt : null,
                      ),
                      style: AppTheme.body,
                    ),
                    if (when != null)
                      Text(
                        formatSubmissionTimestamp(when),
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    if (attempt.supersedesAttemptId != null)
                      Text(
                        'Resubmission',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(FluentIcons.check_mark, size: 16)
              else
                const Icon(FluentIcons.chevron_right, size: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onBack, this.onRetry});

  final String message;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message, textAlign: TextAlign.center, style: AppTheme.body),
            const SizedBox(height: AppSpacing.md),
            ElixBackButton(
              key: const Key('assignment_detail_message_back'),
              label: 'Assigned movements',
              tooltip: 'Back to assigned movements',
              semanticLabel: 'Back to assigned movements',
              onPressed: onBack,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Button(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
