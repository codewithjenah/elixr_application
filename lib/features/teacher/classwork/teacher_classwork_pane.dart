import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../assigned_movements/assigned_movement_list.dart';
import '../../assigned_movements/widgets/submission_detail_body.dart';
import 'teacher_classwork_controller.dart';

class TeacherClassworkAssignmentList extends StatelessWidget {
  const TeacherClassworkAssignmentList({
    super.key,
    required this.controller,
    required this.onOpen,
    this.onCreate,
    this.onEdit,
    this.onArchive,
  });

  final TeacherClassworkController controller;
  final ValueChanged<GroupAssignment> onOpen;
  final VoidCallback? onCreate;
  final ValueChanged<GroupAssignment>? onEdit;
  final ValueChanged<GroupAssignment>? onArchive;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const Center(child: ProgressRing());
    if (controller.unauthorized) {
      return ElixStatusPanel(
        key: const Key('teacher_classwork_unauthorized'),
        isError: true,
        message: controller.errorMessage ?? 'This class is not available.',
      );
    }
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Classwork', style: AppTheme.headingMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Assignments and submitted work for this class.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
              ElixPrimaryButton(
                key: const Key('teacher_group_create_assignment'),
                label: 'New assignment',
                icon: FluentIcons.add,
                expanded: false,
                dense: true,
                onPressed: onCreate,
              ),
            ],
          ),
          if (controller.group?.isActive == false) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This class is archived. Existing classwork remains readable.',
              key: const Key('teacher_group_archived_assignments_message'),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          if (controller.errorMessage != null && !controller.unauthorized) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: const Text('Classwork action not completed'),
              content: Text(controller.errorMessage!),
              severity: InfoBarSeverity.error,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (controller.assignments.isEmpty)
            Column(
              key: const Key('teacher_group_assignments_empty'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No classwork yet.', style: AppTheme.bodySecondary),
                if (controller.group?.isActive == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Create an assignment to give this class its next movement.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
            )
          else
            for (
              var index = 0;
              index < controller.assignments.length;
              index++
            ) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              _AssignmentRow(
                assignment: controller.assignments[index],
                counts: controller.rosterCountsFor(
                  controller.assignments[index].id,
                ),
                statusUnavailable: controller.hasAttemptLoadError(
                  controller.assignments[index].id,
                ),
                onOpen: () => onOpen(controller.assignments[index]),
                onEdit:
                    controller.group?.isActive == true &&
                        controller.assignments[index].isActive
                    ? () => onEdit?.call(controller.assignments[index])
                    : null,
                onArchive:
                    controller.group?.isActive == true &&
                        controller.assignments[index].isActive
                    ? () => onArchive?.call(controller.assignments[index])
                    : null,
              ),
            ],
        ],
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.assignment,
    required this.counts,
    required this.statusUnavailable,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
  });

  final GroupAssignment assignment;
  final TeacherAssignmentRosterCounts counts;
  final bool statusUnavailable;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('teacher_group_assignment_${assignment.id}'),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Open ${assignment.displayTitle}',
              child: HoverButton(
                key: Key('teacher_classwork_open_${assignment.id}'),
                cursor: SystemMouseCursors.click,
                onPressed: onOpen,
                builder: (context, states) => Padding(
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
                            const SizedBox(height: 4),
                            Text(
                              '${assignment.origin.displayLabel} · '
                              '${assignment.isActive ? 'Active' : 'Archived'}'
                              '${assignment.dueAt == null ? '' : ' · Due ${_formatDue(assignment.dueAt!)}'}',
                              style: AppTheme.caption.copyWith(
                                color: context.elixTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusUnavailable
                                  ? 'Work status unavailable'
                                  : '${counts.turnedIn} turned in · '
                                        '${counts.awaitingCheck} ready to check · '
                                        '${counts.checked} checked · '
                                        '${counts.notTurnedIn} not turned in',
                              style: AppTheme.caption.copyWith(
                                color: context.elixTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(FluentIcons.chevron_right, size: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (assignment.isActive) ...[
            Button(
              key: Key('teacher_group_edit_assignment_${assignment.id}'),
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
            const SizedBox(width: AppSpacing.xs),
            Button(
              key: Key('teacher_group_archive_assignment_${assignment.id}'),
              onPressed: onArchive,
              child: const Text('Archive'),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class TeacherAssignmentWorkPane extends StatelessWidget {
  const TeacherAssignmentWorkPane({
    super.key,
    required this.controller,
    required this.onBackToClasswork,
  });

  final TeacherClassworkController controller;
  final VoidCallback onBackToClasswork;

  @override
  Widget build(BuildContext context) {
    final assignment = controller.selectedAssignment;
    if (controller.loading) return const Center(child: ProgressRing());
    if (assignment == null) {
      return const ElixStatusPanel(
        message: 'This assignment is not available.',
      );
    }
    if (controller.hasAttemptLoadError(assignment.id)) {
      return const ElixStatusPanel(
        key: Key('teacher_classwork_attempts_error'),
        isError: true,
        message: 'Work status could not be loaded. Try again.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Button(
            key: const Key('teacher_classwork_back'),
            onPressed: onBackToClasswork,
            child: const Text('Back to Classwork'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AssignmentHeader(controller: controller, assignment: assignment),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final roster = _Roster(
                controller: controller,
                assignment: assignment,
              );
              final detail = _SelectedStudentDetail(
                controller: controller,
                assignment: assignment,
              );
              if (wide) {
                return Row(
                  key: const Key('teacher_classwork_wide_layout'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: roster),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: detail),
                  ],
                );
              }
              if (controller.selectedTraineeId != null) {
                return Column(
                  key: const Key('teacher_classwork_narrow_detail'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Button(
                        key: const Key('teacher_classwork_back_to_roster'),
                        onPressed: () => controller.selectTrainee(null),
                        child: const Text('Back to students'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(child: detail),
                  ],
                );
              }
              return KeyedSubtree(
                key: const Key('teacher_classwork_narrow_roster'),
                child: roster,
              );
            },
          ),
        ),
      ],
    );
  }
}

class TeacherStudentClassworkSection extends StatelessWidget {
  const TeacherStudentClassworkSection({super.key, required this.controller});

  final TeacherClassworkController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const ElixPanelCard(child: Center(child: ProgressRing()));
    }
    if (controller.unauthorized || !controller.fixedStudentAuthorized) {
      return ElixStatusPanel(
        key: const Key('teacher_student_classwork_unauthorized'),
        isError: true,
        message:
            controller.errorMessage ??
            'This student is not approved for this class.',
      );
    }
    final assignment = controller.selectedAssignment;
    if (assignment != null) {
      if (controller.hasAttemptLoadError(assignment.id)) {
        return const ElixStatusPanel(
          key: Key('teacher_student_classwork_attempts_error'),
          isError: true,
          message: 'Work status could not be loaded. Try again.',
        );
      }
      return Column(
        key: const Key('teacher_student_classwork_detail'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: () => controller.selectAssignment(null),
              child: const Text('Back to assigned work'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(assignment.displayTitle, style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          TeacherSubmissionReviewDetail(
            controller: controller,
            assignment: assignment,
            traineeId: controller.fixedTraineeId!,
          ),
        ],
      );
    }
    return ElixPanelCard(
      key: const Key('teacher_student_classwork'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Classwork', style: AppTheme.headingMedium),
          const SizedBox(height: 4),
          Text(
            'Assigned work in ${controller.group?.name ?? 'this class'}.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (controller.assignments.isEmpty)
            Text(
              'No assignments in this class yet.',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            )
          else
            for (
              var index = 0;
              index < controller.assignments.length;
              index++
            ) ...[
              if (index > 0) const Divider(),
              _StudentAssignmentRow(
                controller: controller,
                assignment: controller.assignments[index],
              ),
            ],
        ],
      ),
    );
  }
}

class _StudentAssignmentRow extends StatelessWidget {
  const _StudentAssignmentRow({
    required this.controller,
    required this.assignment,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final traineeId = controller.fixedTraineeId!;
    final attempt = controller.latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: traineeId,
    );
    final statusUnavailable = controller.hasAttemptLoadError(assignment.id);
    final turnedIn = attempt != null && isAssignmentAttemptTurnedIn(attempt);
    final label = statusUnavailable
        ? 'Status unavailable'
        : turnedIn
        ? assignedMovementStatusLabel(
            assignment,
            attempt,
            attempt.isTeacherReviewSubmission ? attempt : null,
          )
        : 'Not turned in';
    return Semantics(
      button: true,
      label: 'Open ${assignment.displayTitle}, $label',
      child: HoverButton(
        key: Key('teacher_student_classwork_${assignment.id}'),
        cursor: SystemMouseCursors.click,
        onPressed: () => controller.selectAssignment(assignment.id),
        builder: (context, states) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(assignment.displayTitle, style: AppTheme.body),
                    const SizedBox(height: 4),
                    Text(
                      '$label · ${assignment.isActive ? 'Active' : 'Archived'}',
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
        ),
      ),
    );
  }
}

class _AssignmentHeader extends StatelessWidget {
  const _AssignmentHeader({required this.controller, required this.assignment});

  final TeacherClassworkController controller;
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
            '${assignment.origin.displayLabel} · '
            '${assignment.isActive ? 'Active' : 'Archived'}'
            '${assignment.dueAt == null ? '' : ' · Due ${_formatDue(assignment.dueAt!)}'}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${counts.turnedIn} turned in · '
            '${counts.awaitingCheck} ready to check · '
            '${counts.checked} checked · '
            '${counts.notTurnedIn} not turned in',
            style: AppTheme.body,
          ),
          if (assignment.isTeacherCreated) ...[
            const SizedBox(height: AppSpacing.sm),
            _MaximumScoreEditor(controller: controller, assignment: assignment),
          ],
        ],
      ),
    );
  }
}

class _MaximumScoreEditor extends StatefulWidget {
  const _MaximumScoreEditor({
    required this.controller,
    required this.assignment,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;

  @override
  State<_MaximumScoreEditor> createState() => _MaximumScoreEditorState();
}

class _MaximumScoreEditorState extends State<_MaximumScoreEditor> {
  late final TextEditingController _score;

  @override
  void initState() {
    super.initState();
    _score = TextEditingController(
      text: (widget.assignment.maxScore ?? 100).toString(),
    )..addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _score
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assignment.gradingLocked) {
      return Text(
        'Maximum score: ${widget.assignment.maxScore ?? 100} · Locked after the first check',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      );
    }
    final value = int.tryParse(_score.text.trim());
    return Row(
      children: [
        SizedBox(
          width: 180,
          child: InfoLabel(
            label: 'Maximum score',
            child: TextBox(
              controller: _score,
              maxLength: 3,
              keyboardType: TextInputType.number,
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
              : () => widget.controller.updateMaximumScore(
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

  final TeacherClassworkController controller;
  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final members = controller.approvedMemberships;
    if (members.isEmpty) {
      return const ElixStatusPanel(
        title: 'No students yet',
        message: 'Share the class code, then approve students who join.',
      );
    }
    return ListView.separated(
      key: const Key('teacher_classwork_roster'),
      itemCount: members.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final member = members[index];
        final attempt = controller.latestVisibleAttemptFor(
          assignmentId: assignment.id,
          traineeId: member.traineeId,
        );
        final turnedIn =
            attempt != null && isAssignmentAttemptTurnedIn(attempt);
        final status = turnedIn
            ? assignedMovementStatusLabel(
                assignment,
                attempt,
                attempt.isTeacherReviewSubmission ? attempt : null,
              )
            : 'Not turned in';
        final selected = controller.selectedTraineeId == member.traineeId;
        return Semantics(
          button: true,
          selected: selected,
          label: '${member.traineeDisplayName}, $status',
          child: HoverButton(
            key: Key('teacher_classwork_student_${member.traineeId}'),
            cursor: SystemMouseCursors.click,
            onPressed: () => controller.selectTrainee(member.traineeId),
            builder: (context, states) => ElixPanelCard(
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
                        Text(
                          status,
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
            ),
          ),
        );
      },
    );
  }
}

class _SelectedStudentDetail extends StatelessWidget {
  const _SelectedStudentDetail({
    required this.controller,
    required this.assignment,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final traineeId = controller.selectedTraineeId;
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            controller.traineeName(traineeId),
            style: AppTheme.headingMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TeacherSubmissionReviewDetail(
            controller: controller,
            assignment: assignment,
            traineeId: traineeId,
          ),
        ],
      ),
    );
  }
}

class TeacherSubmissionReviewDetail extends StatefulWidget {
  const TeacherSubmissionReviewDetail({
    super.key,
    required this.controller,
    required this.assignment,
    required this.traineeId,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final String traineeId;

  @override
  State<TeacherSubmissionReviewDetail> createState() =>
      _TeacherSubmissionReviewDetailState();
}

class _TeacherSubmissionReviewDetailState
    extends State<TeacherSubmissionReviewDetail> {
  final _grade = TextEditingController();
  final _feedback = TextEditingController();
  String? _syncedAttemptKey;

  AssignmentAttempt? get attempt => widget.controller.latestVisibleAttemptFor(
    assignmentId: widget.assignment.id,
    traineeId: widget.traineeId,
  );

  @override
  void initState() {
    super.initState();
    _grade.addListener(_onChanged);
    _syncFields();
  }

  @override
  void didUpdateWidget(covariant TeacherSubmissionReviewDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFields();
  }

  void _onChanged() => setState(() {});

  void _syncFields() {
    final current = attempt;
    final key = current == null
        ? null
        : '${current.id}:${current.reviewRevision}:${current.status.wireValue}';
    if (_syncedAttemptKey == key) return;
    _syncedAttemptKey = key;
    _grade.text = current?.gradeScore?.toString() ?? '';
    _feedback.text = current?.reviewFeedback ?? '';
  }

  @override
  void dispose() {
    _grade
      ..removeListener(_onChanged)
      ..dispose();
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = attempt;
    if (current == null || !isAssignmentAttemptTurnedIn(current)) {
      return const ElixStatusPanel(
        key: Key('teacher_classwork_not_turned_in'),
        title: 'Not turned in',
        message: 'This student has not turned in work for this assignment.',
      );
    }
    final canGrade =
        current.isTeacherReviewSubmission &&
        current.status != AssignmentAttemptStatus.unsubmitting &&
        current.status != AssignmentAttemptStatus.inProgress &&
        current.status != AssignmentAttemptStatus.draft;
    final maximum = current.gradeMaxScore ?? widget.assignment.maxScore ?? 100;
    final parsedGrade = int.tryParse(_grade.text.trim());
    final validGrade =
        parsedGrade != null && parsedGrade >= 0 && parsedGrade <= maximum;
    final legacySubmitted =
        current.status == AssignmentAttemptStatus.submitted &&
        !current.isCanonicalTeacherReviewSubmission;
    return Column(
      key: const Key('teacher_classwork_submission_detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SubmissionDetailBody(
          key: ValueKey('${current.id}:${current.reviewRevision}'),
          assignment: widget.assignment,
          attempt: current,
          viewerRole: SubmissionDetailViewerRole.teacher,
          submissionRepository: widget.controller.submissionRepository,
          openLocalPlayback: widget.controller.openLocalPlayback,
          releaseLocalPlayback: widget.controller.releaseLocalPlayback,
        ),
        if (canGrade) ...[
          const SizedBox(height: AppSpacing.md),
          InfoLabel(
            label: 'Grade (0–$maximum)',
            child: TextBox(
              key: const Key('teacher_classwork_grade'),
              controller: _grade,
              maxLength: 3,
              keyboardType: TextInputType.number,
              placeholder: 'Required',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextBox(
            key: const Key('teacher_classwork_feedback'),
            controller: _feedback,
            maxLength: 1000,
            maxLines: 4,
            placeholder: 'Feedback for the student',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: const Key('teacher_classwork_save_review'),
                onPressed: widget.controller.busy || !validGrade
                    ? null
                    : () => widget.controller.saveReview(
                        attempt: current,
                        assignment: widget.assignment,
                        gradeScore: parsedGrade,
                        feedback: _feedback.text,
                      ),
                child: Text(
                  current.isChecked ? 'Update review' : 'Save review',
                ),
              ),
              if (current.isChecked)
                Button(
                  key: const Key('teacher_classwork_send_result'),
                  onPressed:
                      widget.controller.busy ||
                          current.resultSentForCurrentRevision
                      ? null
                      : () => widget.controller.sendReviewResult(
                          attempt: current,
                          assignment: widget.assignment,
                        ),
                  child: Text(
                    current.resultSentForCurrentRevision
                        ? 'Result sent'
                        : 'Send to student',
                  ),
                ),
            ],
          ),
        ],
        if (legacySubmitted) ...[
          const SizedBox(height: AppSpacing.sm),
          Button(
            onPressed: widget.controller.busy
                ? null
                : () => widget.controller.reviewLegacy(
                    attempt: current,
                    verdict: AssignmentReviewVerdict.approved,
                    feedback: _feedback.text,
                  ),
            child: const Text('Approve legacy review'),
          ),
        ],
      ],
    );
  }
}

String _formatDue(DateTime dueAt) {
  final local = dueAt.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
