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
                  accent: AppColors.accent,
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
                  accent: AppColors.primary,
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
          mainAxisExtent: 268,
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
    required this.accent,
  });

  final Key sectionKey;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return KeyedSubtree(
      key: sectionKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
              boxShadow: highContrast
                  ? const []
                  : [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 8,
                      ),
                    ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.headingMedium.copyWith(
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedMovementCard extends StatefulWidget {
  const _AssignedMovementCard({
    required this.item,
    required this.showGroupName,
  });

  final AssignedMovementItem item;
  final bool showGroupName;

  @override
  State<_AssignedMovementCard> createState() => _AssignedMovementCardState();
}

class _AssignedMovementCardState extends State<_AssignedMovementCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final assignment = widget.item.assignment;
    final canStart = assignment.isActive && !assignment.isRetiredTemplate;
    final accent = assignment.isOfficial ? AppColors.accent : AppColors.primary;
    final accentEnd = assignment.isOfficial
        ? AppColors.primary
        : AppColors.accent;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final originIcon = assignment.isOfficial
        ? FluentIcons.education
        : FluentIcons.edit;
    final detail = assignedMovementDetailLine(
      assignment,
      widget.item.attempt,
      widget.item.latestSubmission,
    );
    final panelSurface = isDark
        ? AppColors.panelSurface
        : context.elixCardSurface;
    final tintedSurface = Color.alphaBlend(
      accent.withValues(alpha: isDark ? (_hovered ? 0.11 : 0.07) : 0.04),
      panelSurface,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        key: Key('assigned_movement_card_${assignment.id}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: highContrast ? context.elixCardSurface : null,
          gradient: highContrast
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [panelSurface, tintedSurface, const Color(0xFF15121D)]
                      : [panelSurface, tintedSurface, panelSurface],
                  stops: const [0, 0.46, 1],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : Color.alphaBlend(
                    accent.withValues(
                      alpha: _hovered
                          ? (isDark ? 0.48 : 0.34)
                          : (isDark ? 0.24 : 0.16),
                    ),
                    context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
                  ),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accent.withValues(
                      alpha: _hovered
                          ? (isDark ? 0.22 : 0.14)
                          : (isDark ? 0.12 : 0.08),
                    ),
                    blurRadius: 24,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (!highContrast)
              Positioned(
                right: -18,
                top: 28,
                child: IgnorePointer(
                  child: Icon(
                    originIcon,
                    size: 118,
                    color: accent.withValues(alpha: isDark ? 0.08 : 0.06),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: highContrast ? accent : null,
                    gradient: highContrast
                        ? null
                        : LinearGradient(colors: [accent, accentEnd]),
                  ),
                ),
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
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: highContrast
                                              ? context.elixCardSurface
                                              : null,
                                          gradient: highContrast
                                              ? null
                                              : LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    accent.withValues(
                                                      alpha: isDark
                                                          ? 0.32
                                                          : 0.20,
                                                    ),
                                                    accentEnd.withValues(
                                                      alpha: isDark
                                                          ? 0.14
                                                          : 0.10,
                                                    ),
                                                  ],
                                                ),
                                          border: Border.all(
                                            color: accent.withValues(
                                              alpha: highContrast ? 1 : 0.42,
                                            ),
                                            width: highContrast ? 2 : 1,
                                          ),
                                          boxShadow: highContrast
                                              ? const []
                                              : [
                                                  BoxShadow(
                                                    color: accent.withValues(
                                                      alpha: 0.22,
                                                    ),
                                                    blurRadius: 12,
                                                    spreadRadius: -2,
                                                  ),
                                                ],
                                        ),
                                        child: Icon(
                                          originIcon,
                                          size: 17,
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
                                      fontWeight: FontWeight.w700,
                                      color: context.elixTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.showGroupName
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
                                        text: assignedMovementDueLabel(
                                          assignment,
                                        ),
                                        color: assignment.isOverdue
                                            ? AppColors.error
                                            : context.elixTextSecondary,
                                        compact: true,
                                      ),
                                      ElixPill(
                                        text: assignedMovementStatusLabel(
                                          assignment,
                                          widget.item.attempt,
                                          widget.item.latestSubmission,
                                        ),
                                        color: assignedMovementStatusColor(
                                          assignment,
                                          widget.item.attempt,
                                          widget.item.latestSubmission,
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
                              widget.item.attempt,
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
                                widget.item.attempt,
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
