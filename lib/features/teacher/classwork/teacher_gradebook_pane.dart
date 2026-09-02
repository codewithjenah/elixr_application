import 'package:elixr_core/models/group_membership.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/assignment_review_state.dart';
import '../../../data/models/group_assignment.dart';
import 'teacher_classwork_controller.dart';
import 'teacher_gradebook.dart';

enum TeacherGradebookScope { all, active, archived }

class TeacherGradebookPane extends StatefulWidget {
  const TeacherGradebookPane({
    super.key,
    required this.controller,
    required this.profilePictureUrlFor,
    required this.onOpenStudent,
    required this.onOpenAssignment,
    required this.onOpenCell,
  });

  final TeacherClassworkController controller;
  final String? Function(String traineeId) profilePictureUrlFor;
  final ValueChanged<GroupMembership> onOpenStudent;
  final ValueChanged<GroupAssignment> onOpenAssignment;
  final void Function(GroupAssignment assignment, String traineeId) onOpenCell;

  @override
  State<TeacherGradebookPane> createState() => _TeacherGradebookPaneState();
}

class _TeacherGradebookPaneState extends State<TeacherGradebookPane> {
  final _searchController = TextEditingController();
  TeacherGradebookScope _scope = TeacherGradebookScope.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.loading) return const Center(child: ProgressRing());
    if (controller.unauthorized) {
      return const ElixStatusPanel(
        message: 'Grades are not available.',
        isError: true,
      );
    }
    final assignments = [
      for (final item in controller.assignments)
        if (_scope == TeacherGradebookScope.all ||
            (_scope == TeacherGradebookScope.active
                ? item.isActive
                : !item.isActive))
          item,
    ];
    final query = _searchController.text.trim().toLowerCase();
    final students = [
      for (final member in controller.approvedMemberships)
        if (query.isEmpty ||
            member.traineeDisplayName.toLowerCase().contains(query))
          member,
    ];
    final toReview = assignments.fold<int>(
      0,
      (total, assignment) =>
          total +
          controller
              .rosterEntriesFor(assignment.id)
              .where(
                (entry) => entry.reviewState == AssignmentReviewState.toReview,
              )
              .length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grades',
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${controller.approvedMemberships.length} students · ${assignments.length} assignments · $toReview to review',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SizedBox(
              width: 280,
              child: TextBox(
                key: const Key('teacher_gradebook_student_search'),
                controller: _searchController,
                placeholder: 'Search students',
                onChanged: (_) => setState(() {}),
              ),
            ),
            ComboBox<TeacherGradebookScope>(
              value: _scope,
              onChanged: (value) => setState(() => _scope = value ?? _scope),
              items: const [
                ComboBoxItem(
                  value: TeacherGradebookScope.all,
                  child: Text('All classwork'),
                ),
                ComboBoxItem(
                  value: TeacherGradebookScope.active,
                  child: Text('Active'),
                ),
                ComboBoxItem(
                  value: TeacherGradebookScope.archived,
                  child: Text('Archived'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.approvedMemberships.isEmpty)
          const ElixStatusPanel(message: 'No students in this class yet.')
        else if (assignments.isEmpty)
          const ElixStatusPanel(message: 'No classwork to grade yet.')
        else if (students.isEmpty)
          const ElixStatusPanel(message: 'No students match this search.')
        else
          ElixPanelCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _GradeMatrix(
                students: students,
                assignments: assignments,
                controller: controller,
                now: controller.gradebookReferenceNow,
                profilePictureUrlFor: widget.profilePictureUrlFor,
                onOpenStudent: widget.onOpenStudent,
                onOpenAssignment: widget.onOpenAssignment,
                onOpenCell: widget.onOpenCell,
              ),
            ),
          ),
      ],
    );
  }
}

class _GradeMatrix extends StatelessWidget {
  const _GradeMatrix({
    required this.students,
    required this.assignments,
    required this.controller,
    required this.now,
    required this.profilePictureUrlFor,
    required this.onOpenStudent,
    required this.onOpenAssignment,
    required this.onOpenCell,
  });

  final List<GroupMembership> students;
  final List<GroupAssignment> assignments;
  final TeacherClassworkController controller;
  final DateTime now;
  final String? Function(String) profilePictureUrlFor;
  final ValueChanged<GroupMembership> onOpenStudent;
  final ValueChanged<GroupAssignment> onOpenAssignment;
  final void Function(GroupAssignment, String) onOpenCell;
  static const _studentWidth = 220.0;
  static const _assignmentWidth = 154.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerCell(context, 'Student', _studentWidth),
            for (final assignment in assignments)
              SizedBox(
                width: _assignmentWidth,
                child: Tooltip(
                  message: assignment.displayTitle,
                  child: ElixHoverSurface(
                    semanticLabel: 'Open ${assignment.displayTitle} classwork',
                    onTap: () => onOpenAssignment(assignment),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            assignment.isOfficial
                                ? 'Official ELIXR'
                                : 'Teacher-created',
                            style: AppTheme.bodySecondary.copyWith(
                              fontSize: 11,
                              color: context.elixTextSecondary,
                            ),
                          ),
                          if (!assignment.isActive)
                            Text(
                              'Archived',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.elixColors.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (final student in students)
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _studentWidth,
                child: ElixHoverSurface(
                  semanticLabel:
                      'Open ${student.traineeDisplayName} student detail',
                  onTap: () => onOpenStudent(student),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      children: [
                        ProfileAvatarWidget(
                          initials: _initials(student.traineeDisplayName),
                          networkImageUrl: profilePictureUrlFor(
                            student.traineeId,
                          ),
                          radius: 15,
                          showBorder: false,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            student.traineeDisplayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              for (final assignment in assignments)
                _GradeCell(
                  width: _assignmentWidth,
                  student: student,
                  assignment: assignment,
                  controller: controller,
                  now: now,
                  onOpen: () => onOpenCell(assignment, student.traineeId),
                ),
            ],
          ),
      ],
    );
  }

  Widget _headerCell(BuildContext context, String label, double width) =>
      SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.elixBorder)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );

  String _initials(String name) => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();
}

class _GradeCell extends StatelessWidget {
  const _GradeCell({
    required this.width,
    required this.student,
    required this.assignment,
    required this.controller,
    required this.now,
    required this.onOpen,
  });
  final double width;
  final GroupMembership student;
  final GroupAssignment assignment;
  final TeacherClassworkController controller;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cell = TeacherGradebookSemantics.cellFor(
      membership: student,
      assignment: assignment,
      attempt: controller.latestVisibleAttemptFor(
        assignmentId: assignment.id,
        traineeId: student.traineeId,
      ),
      attemptUnavailable: controller.hasAttemptLoadError(assignment.id),
      now: now,
    );
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cell.label,
            style: TextStyle(
              fontWeight: cell.state == TeacherGradebookCellState.scored
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: _color(context, cell.state),
            ),
          ),
          if (cell.detail != null && cell.detail!.isNotEmpty)
            Text(
              cell.detail!,
              style: AppTheme.bodySecondary.copyWith(
                fontSize: 11,
                color: context.elixTextSecondary,
              ),
            ),
        ],
      ),
    );
    return SizedBox(
      width: width,
      child: Semantics(
        label:
            '${student.traineeDisplayName}, ${assignment.displayTitle}, ${cell.semanticValue}',
        child: cell.isActionable
            ? ElixHoverSurface(
                semanticLabel:
                    '${student.traineeDisplayName}, ${assignment.displayTitle}, ${cell.semanticValue}',
                onTap: onOpen,
                child: content,
              )
            : content,
      ),
    );
  }

  Color _color(BuildContext context, TeacherGradebookCellState state) =>
      switch (state) {
        TeacherGradebookCellState.toReview => AppColors.accent,
        TeacherGradebookCellState.overdue => context.elixColors.error,
        TeacherGradebookCellState.missing => context.elixColors.warning,
        TeacherGradebookCellState.notAssigned => context.elixTextSecondary,
        TeacherGradebookCellState.unavailable => context.elixColors.error,
        _ => context.elixTextPrimary,
      };
}
