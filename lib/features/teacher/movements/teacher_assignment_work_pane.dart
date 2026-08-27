import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../assigned_movements/assigned_movement_list.dart';
import '../../assigned_movements/widgets/submission_detail_body.dart';
import 'teacher_movements_controller.dart';

class TeacherAssignmentWorkPane extends StatefulWidget {
  const TeacherAssignmentWorkPane({super.key, required this.controller});

  final TeacherMovementsController controller;

  @override
  State<TeacherAssignmentWorkPane> createState() =>
      _TeacherAssignmentWorkPaneState();
}

class _TeacherAssignmentWorkPaneState extends State<TeacherAssignmentWorkPane> {
  final _feedback = TextEditingController();
  String? _feedbackAttemptId;

  TeacherMovementsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _syncFeedback();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _feedback.dispose();
    super.dispose();
  }

  void _onController() {
    _syncFeedback();
    if (mounted) setState(() {});
  }

  void _syncFeedback() {
    final selected = controller.selectedReview;
    if (selected == null) {
      _feedbackAttemptId = null;
      return;
    }
    if (_feedbackAttemptId == selected.id) return;
    _feedbackAttemptId = selected.id;
    _feedback.text = controller.reviewFeedbackDraft ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final assignmentId = controller.selectedAssignmentId;
    final assignment = assignmentId == null
        ? null
        : controller.assignmentById(assignmentId);
    if (assignment == null) {
      return const ElixStatusPanel(
        message: 'This assignment is not available.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Button(
            onPressed: () => controller.selectAssignment(null),
            child: const Text('Back to assignments'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Header(controller: controller, assignment: assignment),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final roster = _Roster(
                controller: controller,
                assignment: assignment,
              );
              final detail = _StudentDetail(
                controller: controller,
                assignment: assignment,
                feedback: _feedback,
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: roster),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: detail),
                  ],
                );
              }
              if (controller.selectedWorkTraineeId != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Button(
                        onPressed: () => controller.selectWorkTrainee(null),
                        child: const Text('Back to roster'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(child: detail),
                  ],
                );
              }
              return roster;
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.assignment});

  final TeacherMovementsController controller;
  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final counts = controller.rosterCountsFor(assignment.id);
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
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ElixPill(
                text: 'Turned in ${counts.turnedIn}',
                color: AppColors.accent,
                compact: true,
              ),
              ElixPill(
                text: 'Awaiting review ${counts.awaitingReview}',
                color: AppColors.warning,
                compact: true,
              ),
              ElixPill(
                text: 'Approved ${counts.approved}',
                color: AppColors.success,
                compact: true,
              ),
              ElixPill(
                text: 'Needs retry ${counts.needsRetry}',
                color: AppColors.error,
                compact: true,
              ),
              ElixPill(
                text: 'Not turned in ${counts.notTurnedIn}',
                color: context.elixTextSecondary,
                compact: true,
              ),
            ],
          ),
        ],
      ),
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

class _Roster extends StatelessWidget {
  const _Roster({required this.controller, required this.assignment});

  final TeacherMovementsController controller;
  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final members = controller.approvedMembersForGroup(assignment.groupId);
    if (members.isEmpty) {
      return const ElixStatusPanel(
        message: 'No approved students in this class yet.',
      );
    }
    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final member = members[index];
        final attempt = controller.latestVisibleAttemptFor(
          assignmentId: assignment.id,
          traineeId: member.traineeId,
        );
        final selected = controller.selectedWorkTraineeId == member.traineeId;
        final when =
            attempt?.submittedAt ?? attempt?.completedAt ?? attempt?.reviewedAt;
        final turnedIn =
            attempt != null &&
            (attempt.isReviewFacingSubmission ||
                attempt.attemptKind == AssignmentAttemptKind.practicePointer ||
                attempt.attemptKind == AssignmentAttemptKind.templateScore);
        final statusLabel = turnedIn
            ? assignedMovementStatusLabel(
                assignment,
                attempt,
                attempt.isTeacherReviewSubmission ? attempt : null,
              )
            : 'Not turned in';
        final statusColor = turnedIn
            ? assignedMovementStatusColor(
                assignment,
                attempt,
                attempt.isTeacherReviewSubmission ? attempt : null,
              )
            : context.elixTextSecondary;
        return HoverButton(
          onPressed: () => controller.selectWorkTrainee(member.traineeId),
          builder: (context, states) {
            return ElixPanelCard(
              accent: selected ? AppColors.accent : null,
              showAccentBar: selected,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.traineeDisplayName,
                          style: AppTheme.headingMedium,
                        ),
                        const SizedBox(height: 4),
                        ElixPill(
                          text: statusLabel,
                          color: statusColor,
                          compact: true,
                        ),
                        if (when != null)
                          Text(
                            formatSubmissionTimestamp(when),
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(FluentIcons.chevron_right, size: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StudentDetail extends StatelessWidget {
  const _StudentDetail({
    required this.controller,
    required this.assignment,
    required this.feedback,
  });

  final TeacherMovementsController controller;
  final GroupAssignment assignment;
  final TextEditingController feedback;

  @override
  Widget build(BuildContext context) {
    final traineeId = controller.selectedWorkTraineeId;
    if (traineeId == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const ElixStatusPanel(
            message: 'Select a student to view their submitted work.',
          ),
        ),
      );
    }
    final attempt = controller.latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: traineeId,
    );
    final canReview =
        attempt != null &&
        attempt.isReviewFacingSubmission &&
        attempt.status == AssignmentAttemptStatus.submitted;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            controller.traineeName(traineeId),
            style: AppTheme.headingMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (attempt == null)
            const ElixStatusPanel(
              message: 'This student has not turned in work yet.',
            )
          else
            SubmissionDetailBody(
              key: ValueKey(attempt.id),
              assignment: assignment,
              attempt: attempt,
              viewerRole: SubmissionDetailViewerRole.teacher,
              submissionRepository: controller.submissionRepository,
              openLocalPlayback: controller.openLocalPlayback,
              releaseLocalPlayback: controller.releaseLocalPlayback,
            ),
          if (canReview) ...[
            const SizedBox(height: AppSpacing.md),
            TextBox(
              controller: feedback,
              maxLength: 1000,
              maxLines: 4,
              placeholder: 'Feedback for the student',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                FilledButton(
                  onPressed: controller.busy
                      ? null
                      : () => controller.reviewSelected(
                          verdict: AssignmentReviewVerdict.approved,
                          feedback: feedback.text,
                        ),
                  child: const Text('Approve'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Button(
                  onPressed: controller.busy
                      ? null
                      : () => controller.reviewSelected(
                          verdict: AssignmentReviewVerdict.needsRetry,
                          feedback: feedback.text,
                        ),
                  child: const Text('Needs Retry'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
