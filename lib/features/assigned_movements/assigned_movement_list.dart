import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import 'assigned_movements_controller.dart';

const double _classworkWideBreakpoint = 1080;
const double _classworkCompactBreakpoint = 720;

/// Shared assignment cards for Assigned Movements and the class detail page.
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
    final official = [
      for (final item in items)
        if (item.assignment.isOfficial) item,
    ];
    final teacherCreated = [
      for (final item in items)
        if (!item.assignment.isOfficial) item,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= _classworkWideBreakpoint
            ? 3
            : width >= _classworkCompactBreakpoint
            ? 2
            : 1;
        return CustomScrollView(
          slivers: [
            if (official.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _OriginSectionHeader(
                  sectionKey: Key('assigned_movements_official_section'),
                  title: 'Official ELIXR',
                  subtitle:
                      'Live guided practice. ELIXR scores your form. No submission clip.',
                ),
              ),
              _cardGridSliver(official, columns),
              if (teacherCreated.isNotEmpty)
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xl),
                ),
            ],
            if (teacherCreated.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _OriginSectionHeader(
                  sectionKey: Key('assigned_movements_teacher_section'),
                  title: 'Teacher-created',
                  subtitle:
                      'Record a clip for your teacher to review. Preview it after you submit.',
                ),
              ),
              _cardGridSliver(teacherCreated, columns),
            ],
          ],
        );
      },
    );
  }

  Widget _cardGridSliver(List<AssignedMovementItem> sectionItems, int columns) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 248,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return _AssignedMovementCard(
            item: sectionItems[index],
            showGroupName: showGroupName,
          );
        }, childCount: sectionItems.length),
      ),
    );
  }
}

class _OriginSectionHeader extends StatelessWidget {
  const _OriginSectionHeader({
    required this.sectionKey,
    required this.title,
    required this.subtitle,
  });

  final Key sectionKey;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: sectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.headingMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _AssignedMovementCard extends StatelessWidget {
  const _AssignedMovementCard({
    required this.item,
    required this.showGroupName,
  });

  final AssignedMovementItem item;
  final bool showGroupName;

  @override
  Widget build(BuildContext context) {
    final assignment = item.assignment;
    final canStart = assignment.isActive && !assignment.isRetiredTemplate;
    final accent = assignment.isOfficial ? AppColors.accent : AppColors.primary;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final detail = assignedMovementDetailLine(
      assignment,
      item.attempt,
      item.latestSubmission,
    );

    return Container(
      key: Key('assigned_movement_card_${assignment.id}'),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : context.elixBorder.withValues(alpha: isDark ? 0.5 : 0.85),
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 6, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.push(
                            AppRoutePaths.assignmentDetail(assignment.id),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      assignment.isOfficial
                                          ? FluentIcons.education
                                          : FluentIcons.edit,
                                      size: 16,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElixPill(
                                    text: assignment.origin.displayLabel,
                                    color: accent,
                                    compact: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                assignment.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.headingMedium.copyWith(
                                  fontSize: 18,
                                  height: 1.2,
                                  color: context.elixTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                showGroupName
                                    ? '${assignment.teacherDisplayName} · ${assignment.groupName}'
                                    : assignment.teacherDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.caption.copyWith(
                                  color: context.elixTextSecondary,
                                ),
                              ),
                              if (detail != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.caption.copyWith(
                                    color: context.elixTextSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ElixPill(
                                    text: assignedMovementDueLabel(assignment),
                                    color: assignment.isOverdue
                                        ? AppColors.error
                                        : context.elixTextSecondary,
                                    compact: true,
                                  ),
                                  ElixPill(
                                    text: assignedMovementStatusLabel(
                                      assignment,
                                      item.attempt,
                                      item.latestSubmission,
                                    ),
                                    color: assignedMovementStatusColor(
                                      assignment,
                                      item.attempt,
                                      item.latestSubmission,
                                    ),
                                    compact: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (canStart)
                      ElixPrimaryButton(
                        label: assignedMovementActionLabel(
                          assignment,
                          item.attempt,
                        ),
                        expanded: true,
                        dense: true,
                        icon: FluentIcons.play,
                        onPressed: () => context.go(
                          AppRoutePaths.assignedPractice(assignment.id),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElixPill(
                          text: assignedMovementActionLabel(
                            assignment,
                            item.attempt,
                          ),
                          color: context.elixTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

String assignedMovementDueLabel(GroupAssignment assignment) {
  if (!assignment.isActive) return 'Archived';
  final due = assignment.dueAt;
  if (due == null) return 'No due date';
  if (assignment.isOverdue) return 'Overdue';
  final local = due.toLocal();
  final today = DateTime.now().toLocal();
  final dueDay = DateTime(local.year, local.month, local.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final diff = dueDay.difference(todayDay).inDays;
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (diff > 1 && diff < 7) return 'Due ${weekdays[local.weekday - 1]}';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Due ${months[local.month - 1]} ${local.day}';
}

String assignedMovementStatusLabel(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isRetiredTemplate) return 'Historical';
  if (assignment.isTeacherCreated) {
    final current = submission ?? attempt;
    if (current == null ||
        current.attemptKind == AssignmentAttemptKind.teacherReviewDraft) {
      return 'Not submitted';
    }
    return switch (current.status) {
      AssignmentAttemptStatus.draft ||
      AssignmentAttemptStatus.inProgress => 'Not submitted',
      AssignmentAttemptStatus.submitted => 'Awaiting review',
      AssignmentAttemptStatus.approved => 'Approved',
      AssignmentAttemptStatus.needsRetry => 'Needs retry',
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

Color assignedMovementStatusColor(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isRetiredTemplate) return AppColors.warning;
  final label = assignedMovementStatusLabel(assignment, attempt, submission);
  return switch (label) {
    'Approved' => AppColors.success,
    'Awaiting review' || 'Submitted' => AppColors.accent,
    'Needs retry' => AppColors.error,
    'In progress' || 'Draft' => AppColors.primary,
    _ => AppColors.accentSoft,
  };
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
  final dueText = assignedMovementDueLabel(assignment);
  final attemptText = assignedMovementStatusLabel(
    assignment,
    attempt,
    submission,
  );
  if (!assignment.isActive) return 'Archived · $attemptText';
  return '$dueText · $attemptText';
}

String? assignedMovementDetailLine(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isRetiredTemplate) {
    return assignedMovementStatusLine(assignment, attempt, submission);
  }
  if (assignment.isTeacherCreated) {
    final current = submission ?? attempt;
    final feedback = current?.reviewFeedback?.trim();
    if (current?.status == AssignmentAttemptStatus.needsRetry &&
        feedback != null &&
        feedback.isNotEmpty) {
      return feedback;
    }
    if (current != null &&
        current.isTeacherReviewSubmission &&
        current.videoExpired) {
      return 'Video expired';
    }
  }
  return null;
}
