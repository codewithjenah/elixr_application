import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../core/widgets/profile_avatar.dart';
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
                      _AssignmentMovementIcon(assignment: assignment),
                      const SizedBox(width: AppSpacing.md),
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

class _AssignmentMovementIcon extends StatelessWidget {
  const _AssignmentMovementIcon({required this.assignment});

  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final movementName = assignment.officialMovementName ??
        assignment.displayTitle;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: context.elixColors.brandPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: MovementImage(movementName: movementName, size: 52),
    );
  }
}

class TeacherAssignmentWorkPane extends StatelessWidget {
  const TeacherAssignmentWorkPane({
    super.key,
    required this.controller,
    this.profilePictureUrlFor,
    this.onOpenTrainee,
    this.onEditAssignment,
  });

  final TeacherClassworkController controller;
  final String? Function(String traineeId)? profilePictureUrlFor;
  final ValueChanged<String>? onOpenTrainee;
  final ValueChanged<GroupAssignment>? onEditAssignment;

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
    final traineeId = controller.selectedTraineeId;
    if (traineeId != null) {
      return _SelectedStudentReviewWorkspace(
        controller: controller,
        assignment: assignment,
        traineeId: traineeId,
        profilePictureUrl: profilePictureUrlFor?.call(traineeId),
      );
    }
    return Column(
      key: const Key('teacher_classwork_assignment_roster_workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AssignmentHeader(
          controller: controller,
          assignment: assignment,
          onEdit: onEditAssignment == null
              ? null
              : () => onEditAssignment!(assignment),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _Roster(
            controller: controller,
            assignment: assignment,
            profilePictureUrlFor: profilePictureUrlFor,
            onOpenTrainee: onOpenTrainee,
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
  const _AssignmentHeader({
    required this.controller,
    required this.assignment,
    this.onEdit,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final counts = controller.rosterCountsFor(assignment.id);
    final maximum = assignment.maxScore ?? 100;
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              Text(assignment.displayTitle, style: AppTheme.headingMedium),
              if (onEdit != null)
                Button(
                  key: const Key('teacher_classwork_edit_assignment'),
                  onPressed: controller.busy ? null : onEdit,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.settings, size: 14),
                      SizedBox(width: AppSpacing.sm),
                      Text('Edit assignment'),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${assignment.origin.displayLabel} · '
            '${assignment.isActive ? 'Active' : 'Archived'}'
            '${assignment.dueAt == null ? '' : ' · Due ${_formatDue(assignment.dueAt!)}'}'
            '${assignment.isTeacherCreated ? ' · Maximum $maximum${assignment.gradingLocked ? ' (locked)' : ''}' : ''}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _AssignmentMetric(value: counts.turnedIn, label: 'Turned in'),
              _AssignmentMetric(
                value: counts.awaitingCheck,
                label: 'Ready to check',
              ),
              _AssignmentMetric(value: counts.checked, label: 'Checked'),
              _AssignmentMetric(
                value: counts.notTurnedIn,
                label: 'Not turned in',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignmentMetric extends StatelessWidget {
  const _AssignmentMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$value',
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Roster extends StatelessWidget {
  const _Roster({
    required this.controller,
    required this.assignment,
    this.profilePictureUrlFor,
    this.onOpenTrainee,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final String? Function(String traineeId)? profilePictureUrlFor;
  final ValueChanged<String>? onOpenTrainee;

  @override
  Widget build(BuildContext context) {
    final members = controller.approvedMemberships;
    if (members.isEmpty) {
      return const ElixStatusPanel(
        title: 'No students yet',
        message: 'Share the class code, then approve students who join.',
      );
    }
    return Column(
      key: const Key('teacher_classwork_roster'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Students', style: AppTheme.headingMedium),
        const SizedBox(height: 4),
        Text(
          'Select a student to review their latest submitted work.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView.separated(
            key: const Key('teacher_classwork_roster_list'),
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
              final submittedAt = attempt?.submittedAt;
              return Semantics(
                button: true,
                label:
                    '${member.traineeDisplayName}, profile picture, $status',
                child: HoverButton(
                  key: Key('teacher_classwork_student_${member.traineeId}'),
                  cursor: SystemMouseCursors.click,
                  onPressed: () {
                    final onOpen = onOpenTrainee;
                    if (onOpen != null) {
                      onOpen(member.traineeId);
                    } else {
                      controller.selectTrainee(member.traineeId);
                    }
                  },
                  builder: (context, states) {
                    final hovered = states.contains(WidgetState.hovered);
                    final focused = states.contains(WidgetState.focused);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: hovered
                            ? context.elixColors.interactiveHover
                            : context.elixPanelSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: focused
                              ? context.elixColors.focusRing
                              : context.elixColors.borderSubtle,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: ProfileAvatarWidget(
                              key: Key(
                                'teacher_classwork_avatar_${member.traineeId}',
                              ),
                              networkImageUrl: profilePictureUrlFor?.call(
                                member.traineeId,
                              ),
                              initials: userInitials(
                                member.traineeDisplayName,
                              ),
                              radius: 22,
                              showBorder: false,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.traineeDisplayName,
                                  style: AppTheme.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  submittedAt == null
                                      ? status
                                      : '$status · Submitted ${formatSubmissionTimestamp(submittedAt)}',
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
                          Text(
                            turnedIn ? 'Review' : 'View',
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(FluentIcons.chevron_right, size: 12),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectedStudentReviewWorkspace extends StatelessWidget {
  const _SelectedStudentReviewWorkspace({
    required this.controller,
    required this.assignment,
    required this.traineeId,
    required this.profilePictureUrl,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final String traineeId;
  final String? profilePictureUrl;

  @override
  Widget build(BuildContext context) {
    final name = controller.traineeName(traineeId);
    final attempt = controller.latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: traineeId,
    );
    final status = attempt == null || !isAssignmentAttemptTurnedIn(attempt)
        ? 'Not turned in'
        : assignedMovementStatusLabel(
            assignment,
            attempt,
            attempt.isTeacherReviewSubmission ? attempt : null,
          );
    return Column(
      key: const Key('teacher_classwork_submission_workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              image: true,
              label: 'Profile picture for $name',
              child: ExcludeSemantics(
                child: ProfileAvatarWidget(
                  key: const Key('teacher_classwork_selected_avatar'),
                  networkImageUrl: profilePictureUrl,
                  initials: userInitials(name),
                  radius: 26,
                  showBorder: false,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTheme.headingMedium),
                  const SizedBox(height: 3),
                  Text(
                    '${assignment.displayTitle} · ${assignment.groupName}',
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
            ElixPill(
              text: status,
              color: attempt == null
                  ? context.elixTextSecondary
                  : assignedMovementStatusColor(
                      assignment,
                      attempt,
                      attempt.isTeacherReviewSubmission ? attempt : null,
                    ),
              compact: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: TeacherSubmissionReviewDetail(
            controller: controller,
            assignment: assignment,
            traineeId: traineeId,
            desktopReview: true,
          ),
        ),
      ],
    );
  }
}

class TeacherSubmissionReviewDetail extends StatefulWidget {
  const TeacherSubmissionReviewDetail({
    super.key,
    required this.controller,
    required this.assignment,
    required this.traineeId,
    this.desktopReview = false,
  });

  final TeacherClassworkController controller;
  final GroupAssignment assignment;
  final String traineeId;
  final bool desktopReview;

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
    final reviewControls = _buildReviewControls(
      current: current,
      canGrade: canGrade,
      maximum: maximum,
      validGrade: validGrade,
      parsedGrade: parsedGrade,
      legacySubmitted: legacySubmitted,
    );
    final submissionDetail = SubmissionDetailBody(
      key: ValueKey('${current.id}:${current.reviewRevision}'),
      assignment: widget.assignment,
      attempt: current,
      viewerRole: SubmissionDetailViewerRole.teacher,
      submissionRepository: widget.controller.submissionRepository,
      openLocalPlayback: widget.controller.openLocalPlayback,
      releaseLocalPlayback: widget.controller.releaseLocalPlayback,
      presentation: widget.desktopReview
          ? SubmissionDetailPresentation.teacherDesktopReview
          : SubmissionDetailPresentation.standard,
      reviewPanel: widget.desktopReview ? reviewControls : null,
    );
    if (widget.desktopReview) {
      return SizedBox.expand(
        key: const Key('teacher_classwork_submission_detail'),
        child: submissionDetail,
      );
    }
    return Column(
      key: const Key('teacher_classwork_submission_detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [submissionDetail, reviewControls],
    );
  }

  Widget _buildReviewControls({
    required AssignmentAttempt current,
    required bool canGrade,
    required int maximum,
    required bool validGrade,
    required int? parsedGrade,
    required bool legacySubmitted,
  }) {
    return Column(
      key: const Key('teacher_classwork_review_controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canGrade) ...[
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 160,
              child: InfoLabel(
                label: 'Grade (0–$maximum)',
                child: TextBox(
                  key: const Key('teacher_classwork_grade'),
                  controller: _grade,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  placeholder: 'Required',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Feedback',
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextBox(
            key: const Key('teacher_classwork_feedback'),
            controller: _feedback,
            maxLength: 1000,
            minLines: widget.desktopReview ? 5 : 3,
            maxLines: widget.desktopReview ? 8 : 4,
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
                        gradeScore: parsedGrade!,
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
