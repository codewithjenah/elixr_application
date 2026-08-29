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
  final _grade = TextEditingController();
  final _feedback = TextEditingController();
  String? _feedbackAttemptId;

  TeacherMovementsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onController);
    _grade.addListener(_onGradeChanged);
    _syncFeedback();
  }

  @override
  void dispose() {
    controller.removeListener(_onController);
    _grade.removeListener(_onGradeChanged);
    _grade.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _onController() {
    _syncFeedback();
    if (mounted) setState(() {});
  }

  void _onGradeChanged() {
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
    _grade.text = selected.gradeScore?.toString() ?? '';
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
                grade: _grade,
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
                text: 'Awaiting check ${counts.awaitingCheck}',
                color: AppColors.warning,
                compact: true,
              ),
              ElixPill(
                text: 'Checked ${counts.checked}',
                color: AppColors.success,
                compact: true,
              ),
              ElixPill(
                text: 'Not turned in ${counts.notTurnedIn}',
                color: context.elixTextSecondary,
                compact: true,
              ),
            ],
          ),
          if (assignment.isTeacherCreated) ...[
            const SizedBox(height: AppSpacing.sm),
            _MaxScoreEditor(controller: controller, assignment: assignment),
          ],
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

class _MaxScoreEditor extends StatefulWidget {
  const _MaxScoreEditor({required this.controller, required this.assignment});

  final TeacherMovementsController controller;
  final GroupAssignment assignment;

  @override
  State<_MaxScoreEditor> createState() => _MaxScoreEditorState();
}

class _MaxScoreEditorState extends State<_MaxScoreEditor> {
  late final TextEditingController _maxScore;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _maxScore = TextEditingController(
      text: (widget.assignment.maxScore ?? 100).toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _MaxScoreEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignment.maxScore != widget.assignment.maxScore &&
        !_editing) {
      _maxScore.text = (widget.assignment.maxScore ?? 100).toString();
    }
  }

  @override
  void dispose() {
    _maxScore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.assignment.gradingLocked;
    if (locked) {
      return Text(
        'Maximum score: ${widget.assignment.maxScore ?? 100} · Locked after first check',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      );
    }
    final value = int.tryParse(_maxScore.text.trim());
    return Row(
      children: [
        SizedBox(
          width: 180,
          child: InfoLabel(
            label: 'Maximum score',
            child: TextBox(
              controller: _maxScore,
              maxLength: 3,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                _editing = true;
                setState(() {});
              },
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Button(
          onPressed:
              widget.controller.busy ||
                  value == null ||
                  value < 1 ||
                  value > 100
              ? null
              : () => widget.controller.editAssignmentMaxScore(
                  assignmentId: widget.assignment.id,
                  maxScore: value,
                ),
          child: const Text('Save maximum'),
        ),
      ],
    );
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
    required this.grade,
    required this.feedback,
  });

  final TeacherMovementsController controller;
  final GroupAssignment assignment;
  final TextEditingController grade;
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
    final canGrade =
        attempt != null &&
        attempt.isTeacherReviewSubmission &&
        attempt.status != AssignmentAttemptStatus.unsubmitting &&
        attempt.status != AssignmentAttemptStatus.inProgress &&
        attempt.status != AssignmentAttemptStatus.draft;
    final maxScore = attempt?.gradeMaxScore ?? assignment.maxScore ?? 100;
    final parsedGrade = int.tryParse(grade.text.trim());
    final canSaveGrade =
        canGrade &&
        parsedGrade != null &&
        parsedGrade >= 0 &&
        parsedGrade <= maxScore;
    final showLegacyVerdictActions =
        attempt?.status == AssignmentAttemptStatus.submitted &&
        attempt?.isCanonicalTeacherReviewSubmission != true;
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
          if (canGrade) ...[
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Grade (0–$maxScore)',
              child: TextBox(
                controller: grade,
                maxLength: 3,
                keyboardType: TextInputType.number,
                placeholder: 'Required',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                  onPressed: controller.busy || !canSaveGrade
                      ? null
                      : () => controller.saveSelectedReview(
                          gradeScore: parsedGrade,
                          feedback: feedback.text,
                        ),
                  child: Text(
                    attempt.isChecked ? 'Update review' : 'Save review',
                  ),
                ),
                if (attempt.isChecked) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Button(
                    onPressed:
                        controller.busy || attempt.resultSentForCurrentRevision
                        ? null
                        : controller.sendSelectedReviewResult,
                    child: Text(
                      attempt.resultSentForCurrentRevision
                          ? 'Result sent'
                          : 'Send to student',
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (showLegacyVerdictActions) ...[
            const SizedBox(height: AppSpacing.sm),
            Button(
              onPressed: controller.busy
                  ? null
                  : () => controller.reviewSelected(
                      verdict: AssignmentReviewVerdict.approved,
                      feedback: feedback.text,
                    ),
              child: const Text('Approve legacy review'),
            ),
          ],
        ],
      ),
    );
  }
}
