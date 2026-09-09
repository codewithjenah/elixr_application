import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/movement_image.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/assessment_score_display.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import 'assigned_movements_controller.dart';

const double _classworkWideBreakpoint = 1080;
const double _classworkCompactBreakpoint = 720;
const double _classworkCardRadius = 14;
const double _assignmentOriginSize = 36;
const double _assignmentTeacherAvatarOuter = 28;
const double _assignmentActionHeight = 40;
const double _assignmentDueRowHeight = 20;
const int _assignmentTitleLines = 2;
const int _assignmentDetailLines = 2;
const double _assignmentDetailLineHeight = 1.35;

double _assignmentTextSlotHeight({
  required BuildContext context,
  required TextStyle style,
  required int lines,
}) {
  final fontSize = style.fontSize ?? 12;
  final heightFactor = style.height ?? 1.0;
  return MediaQuery.textScalerOf(context).scale(fontSize) *
      heightFactor *
      lines;
}

/// Learner-facing label for assignments with a null or empty stored topic.
const String classworkUncategorizedTopicLabel = 'General';

int _classworkColumnCount(double width) {
  if (width >= _classworkWideBreakpoint) return 3;
  if (width >= _classworkCompactBreakpoint) return 2;
  return 1;
}

String _teacherCreatedSectionSubtitle(List<AssignedMovementItem> items) {
  final hasTemplate = items.any((item) => item.assignment.isTemplateScored);
  final hasReview = items.any((item) => !item.assignment.isTemplateScored);
  if (hasTemplate && !hasReview) {
    return 'ELIXR automatically checks these activities. No recording clip is required.';
  }
  if (hasTemplate && hasReview) {
    return 'Teacher Review recordings and Automatic ELIXR Assessment activities.';
  }
  return 'Record a clip for your teacher to review. Preview it after you submit.';
}

/// Shared assignment cards for Assigned Movements and the class detail page.
class AssignedMovementList extends StatelessWidget {
  const AssignedMovementList({
    super.key,
    required this.items,
    this.showGroupName = true,
    this.padding = EdgeInsets.zero,
  });

  final List<AssignedMovementItem> items;
  final bool showGroupName;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: AssignedMovementContent(
              items: items,
              showGroupName: showGroupName,
            ),
          ),
        ),
      ],
    );
  }
}

/// Assignment sections without their own scroll view.
///
/// Use this when the surrounding page owns vertical scrolling so headers and
/// classwork move together instead of competing for the available viewport.
class AssignedMovementContent extends StatelessWidget {
  const AssignedMovementContent({
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
        final columns = _classworkColumnCount(width);
        final cardWidth = (width - (AppSpacing.md * (columns - 1))) / columns;

        Widget cardGrid(List<AssignedMovementItem> sectionItems) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final item in sectionItems)
                  SizedBox(
                    width: cardWidth,
                    child: _AssignedMovementCard(
                      item: item,
                      showGroupName: showGroupName,
                    ),
                  ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (official.isNotEmpty) ...[
              _OriginSectionHeader(
                sectionKey: const Key('assigned_movements_official_section'),
                icon: FluentIcons.education,
                title: 'Official ELIXR',
                subtitle:
                    'Live guided practice. ELIXR scores your form. No submission clip.',
                accent: AppColors.accent,
                assignmentCount: official.length,
              ),
              cardGrid(official),
              if (teacherCreated.isNotEmpty)
                const SizedBox(height: AppSpacing.xl),
            ],
            if (teacherCreated.isNotEmpty) ...[
              _OriginSectionHeader(
                sectionKey: const Key('assigned_movements_teacher_section'),
                icon: FluentIcons.assign,
                title: 'Teacher-created',
                subtitle: _teacherCreatedSectionSubtitle(teacherCreated),
                accent: AppColors.primary,
                assignmentCount: teacherCreated.length,
              ),
              cardGrid(teacherCreated),
            ],
          ],
        );
      },
    );
  }
}

/// Classwork presentation grouped by the optional teacher-selected topic.
///
/// Null or empty stored topics stay grouped together and are shown as
/// [classworkUncategorizedTopicLabel]. The stored topic value is unchanged.
class ClassroomTopicContent extends StatelessWidget {
  const ClassroomTopicContent({
    super.key,
    required this.items,
    this.showGroupName = false,
  });

  final List<AssignedMovementItem> items;
  final bool showGroupName;

  @override
  Widget build(BuildContext context) {
    final groups = <String?, List<AssignedMovementItem>>{};
    for (final item in items) {
      final topic = item.assignment.topic?.trim();
      groups
          .putIfAbsent(topic == null || topic.isEmpty ? null : topic, () => [])
          .add(item);
    }
    final names = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < names.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xl),
          _TopicSectionHeader(
            label: names[index] ?? classworkUncategorizedTopicLabel,
            assignmentCount: groups[names[index]]!.length,
          ),
          const SizedBox(height: AppSpacing.md),
          AssignedMovementContent(
            items: groups[names[index]]!,
            showGroupName: showGroupName,
          ),
        ],
      ],
    );
  }
}

class _TopicSectionHeader extends StatelessWidget {
  const _TopicSectionHeader({
    required this.label,
    required this.assignmentCount,
  });

  final String label;
  final int assignmentCount;

  @override
  Widget build(BuildContext context) {
    final countLabel =
        '$assignmentCount ${assignmentCount == 1 ? 'assignment' : 'assignments'}';
    return Row(
      children: [
        Icon(FluentIcons.folder, size: 16, color: context.elixTextSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          countLabel,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _OriginSectionHeader extends StatelessWidget {
  const _OriginSectionHeader({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.assignmentCount,
  });

  final Key sectionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final int assignmentCount;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final countLabel =
        '$assignmentCount ${assignmentCount == 1 ? 'assignment' : 'assignments'}';
    return KeyedSubtree(
      key: sectionKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: highContrast
              ? context.elixCardSurface
              : Color.alphaBlend(
                  accent.withValues(alpha: isDark ? 0.12 : 0.07),
                  context.elixCardSurface,
                ),
          borderRadius: BorderRadius.circular(_classworkCardRadius),
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : accent.withValues(alpha: isDark ? 0.32 : 0.22),
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : accent.withValues(alpha: isDark ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accent.withValues(alpha: highContrast ? 1 : 0.4),
                  width: highContrast ? 2 : 1,
                ),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headingMedium.copyWith(
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                countLabel,
                style: AppTheme.caption.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
  bool _focused = false;

  void _openDetails() {
    context.push(AppRoutePaths.assignmentDetail(widget.item.assignment.id));
  }

  void _startPractice() {
    context.go(AppRoutePaths.assignedPractice(widget.item.assignment.id));
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.item.assignment;
    final attempt = widget.item.attempt;
    final submission = widget.item.latestSubmission;
    final canStart = canStartAssignedMovement(
      assignment,
      attempt,
      submission,
      activityAttempts: widget.item.activityAttempts,
    );
    final accent = assignment.isOfficial ? AppColors.accent : AppColors.primary;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final movementName =
        assignment.officialMovementName ?? assignment.displayTitle;
    final detail = assignedMovementDetailLine(assignment, attempt, submission);
    final statusLabel = assignedMovementStatusLabel(
      assignment,
      attempt,
      submission,
    );
    final statusColor = assignedMovementStatusColor(
      assignment,
      attempt,
      submission,
    );
    final dueLabel = assignedMovementDueLabel(assignment);
    final dueColor = assignment.isOverdue
        ? AppColors.error
        : context.elixTextSecondary;
    final hasDemoVideo =
        assignment.activityAssessment?.demonstrationVideo != null;
    final titleStyle = AppTheme.cardTitle(color: context.elixTextPrimary);
    final detailStyle = AppTheme.caption.copyWith(
      color: context.elixTextSecondary,
      height: _assignmentDetailLineHeight,
    );
    final titleSlotHeight = _assignmentTextSlotHeight(
      context: context,
      style: titleStyle,
      lines: _assignmentTitleLines,
    );
    final detailSlotHeight = _assignmentTextSlotHeight(
      context: context,
      style: detailStyle,
      lines: _assignmentDetailLines,
    );
    final colors = context.elixColors;
    final surface = isDark ? AppColors.panelSurface : context.elixCardSurface;
    final tintedSurface = Color.alphaBlend(
      accent.withValues(
        alpha: isDark
            ? (_hovered || _focused ? 0.10 : 0.05)
            : (_hovered || _focused ? 0.06 : 0.03),
      ),
      surface,
    );
    final glowScale = context.elixWorkspaceVisuals.persistentGlowScale;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        key: Key('assigned_movement_card_${assignment.id}'),
        duration: ElixMotion.duration(context, ElixMotion.standard),
        curve: ElixMotion.standardCurve,
        decoration: BoxDecoration(
          color: highContrast ? context.elixCardSurface : tintedSurface,
          borderRadius: BorderRadius.circular(_classworkCardRadius),
          border: Border.all(
            color: highContrast
                ? (_focused ? colors.focusRing : context.elixBorder)
                : Color.alphaBlend(
                    accent.withValues(
                      alpha: _focused
                          ? 0.55
                          : _hovered
                          ? (isDark ? 0.42 : 0.30)
                          : (isDark ? 0.20 : 0.14),
                    ),
                    context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
                  ),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                    blurRadius: _hovered ? 16 : 10,
                    offset: Offset(0, _hovered ? 8 : 4),
                  ),
                  BoxShadow(
                    color: accent.withValues(
                      alpha:
                          (_hovered ? 0.14 : 0.06) *
                          glowScale *
                          (isDark ? 1 : 0.8),
                    ),
                    blurRadius: 18,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onFocusChange: (focused) => setState(() => _focused = focused),
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    _openDetails();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Semantics(
                  button: true,
                  label: 'Open ${assignment.displayTitle} details',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openDetails,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: _assignmentOriginSize,
                            child: Row(
                              children: [
                                Container(
                                  width: _assignmentOriginSize,
                                  height: _assignmentOriginSize,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: highContrast
                                        ? context.elixCardSurface
                                        : accent.withValues(
                                            alpha: isDark ? 0.22 : 0.12,
                                          ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: accent.withValues(
                                        alpha: highContrast ? 1 : 0.38,
                                      ),
                                      width: highContrast ? 2 : 1,
                                    ),
                                  ),
                                  child: MovementImage(
                                    movementName: movementName,
                                    size: _assignmentOriginSize,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElixPill(
                                  text: assignment.origin.displayLabel,
                                  color: accent,
                                  compact: true,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _IconLabel(
                                    icon: assignedMovementStatusIcon(
                                      assignment,
                                      attempt,
                                      submission,
                                    ),
                                    text: statusLabel,
                                    color: statusColor,
                                    expand: true,
                                    alignEnd: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: titleSlotHeight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                assignment.displayTitle,
                                maxLines: _assignmentTitleLines,
                                overflow: TextOverflow.ellipsis,
                                style: titleStyle,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: _assignmentTeacherAvatarOuter,
                            child: Row(
                              children: [
                                ExcludeSemantics(
                                  child: _TeacherIdentityAvatar(
                                    assignmentId: assignment.id,
                                    displayName: assignment.teacherDisplayName,
                                    photoUrl:
                                        widget.item.teacherProfilePictureUrl,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.showGroupName
                                        ? '${assignment.teacherDisplayName} · ${assignment.groupName}'
                                        : assignment.teacherDisplayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(
                                      color: context.elixTextSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: detailSlotHeight,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: detail == null
                                  ? const SizedBox.shrink()
                                  : Text(
                                      detail,
                                      maxLines: _assignmentDetailLines,
                                      overflow: TextOverflow.ellipsis,
                                      style: detailStyle,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: _assignmentDueRowHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _IconLabel(
                                    icon: assignedMovementDueIcon(assignment),
                                    text: dueLabel,
                                    color: dueColor,
                                    expand: true,
                                  ),
                                ),
                                if (hasDemoVideo) ...[
                                  const SizedBox(width: 12),
                                  const Tooltip(
                                    message: 'Demonstration video',
                                    child: _ResourceIndicator(
                                      icon: FluentIcons.video,
                                      label: 'Video',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: Key('assigned_movement_action_${assignment.id}'),
                height: _assignmentActionHeight,
                child: canStart
                    ? ElixPrimaryButton(
                        label: assignedMovementPracticeButtonLabel(
                          attempt,
                          assignment: assignment,
                        ),
                        expanded: true,
                        dense: true,
                        icon: FluentIcons.play,
                        onPressed: _startPractice,
                      )
                    : _SecondaryAssignmentAction(
                        label: 'View details',
                        icon: FluentIcons.view,
                        onPressed: _openDetails,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryAssignmentAction extends StatelessWidget {
  const _SecondaryAssignmentAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Button(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.interactivePressed;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colors.interactiveHover;
            }
            return highContrast
                ? colors.surfaceBase
                : colors.surfaceInteractive;
          }),
          foregroundColor: WidgetStateProperty.all(colors.textPrimary),
          shape: WidgetStateProperty.resolveWith((states) {
            return RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: states.contains(WidgetState.focused)
                    ? colors.focusRing
                    : (highContrast
                          ? colors.borderStrong
                          : colors.borderSubtle),
                width: states.contains(WidgetState.focused)
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : (highContrast ? 2 : 1),
              ),
            );
          }),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: colors.textPrimary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.label(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherIdentityAvatar extends StatelessWidget {
  const _TeacherIdentityAvatar({
    required this.assignmentId,
    required this.displayName,
    this.photoUrl,
  });

  final String assignmentId;
  final String displayName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    const outer = _assignmentTeacherAvatarOuter;
    final rim = highContrast ? 2.0 : 1.0;
    final inner = outer - (rim * 2);
    return Container(
      width: outer,
      height: outer,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : Color.alphaBlend(
                  AppColors.accent.withValues(alpha: isDark ? 0.38 : 0.24),
                  context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
                ),
          width: rim,
        ),
      ),
      child: SizedBox(
        width: inner,
        height: inner,
        child: ProfileAvatarWidget(
          key: Key('assigned_movement_teacher_avatar_$assignmentId'),
          radius: inner / 2,
          showBorder: false,
          initials: userInitials(displayName),
          networkImageUrl: photoUrl,
        ),
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({
    required this.icon,
    required this.text,
    required this.color,
    this.expand = false,
    this.alignEnd = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool expand;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: AppTheme.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        if (expand) Flexible(child: label) else label,
      ],
    );
  }
}

class _ResourceIndicator extends StatelessWidget {
  const _ResourceIndicator({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.elixTextSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

IconData assignedMovementDueIcon(GroupAssignment assignment) {
  if (assignment.isOverdue) return FluentIcons.warning;
  return FluentIcons.calendar;
}

IconData assignedMovementStatusIcon(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  final label = assignedMovementStatusLabel(assignment, attempt, submission);
  return switch (label) {
    'Not started' || 'Not submitted' => FluentIcons.play,
    'Draft' || 'In progress' => FluentIcons.clock,
    'Ready to turn in' => FluentIcons.completed,
    'Awaiting check' || 'Awaiting review' || 'Submitted' => FluentIcons.clock,
    'Checked' || 'Approved' => FluentIcons.completed_solid,
    'Needs retry' => FluentIcons.warning,
    'Withdrawing' => FluentIcons.sync,
    'Historical' => FluentIcons.history,
    _ => FluentIcons.info,
  };
}

String assignedMovementPracticeButtonLabel(
  AssignmentAttempt? attempt, {
  GroupAssignment? assignment,
}) {
  if (assignment?.activityAssessment != null) {
    return attempt == null ? 'Start attempt' : 'Try again';
  }
  if (attempt == null) return 'Start practice';
  return 'Continue practice';
}

String assignedMovementActionLabel(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
) {
  if (assignment.isTemplateScored) {
    return attempt == null ? 'Start practice' : 'Try again';
  }
  if (assignment.isTeacherCreated &&
      (attempt == null ||
          attempt.status == AssignmentAttemptStatus.draft ||
          attempt.status == AssignmentAttemptStatus.inProgress) &&
      !isTeacherAssignmentSubmissionOpen(assignment: assignment)) {
    return 'Overdue';
  }
  if (attempt == null) return 'Start practice';
  if (assignment.isTeacherCreated &&
      attempt.isCanonicalTeacherReviewSubmission) {
    return switch (attempt.status) {
      AssignmentAttemptStatus.draft || AssignmentAttemptStatus.inProgress =>
        attempt.hasAttachedDraftClip ? 'Ready to turn in' : 'Continue practice',
      AssignmentAttemptStatus.submitted => 'Awaiting check',
      AssignmentAttemptStatus.unsubmitting => 'Withdrawing',
      AssignmentAttemptStatus.checked => 'Checked',
      AssignmentAttemptStatus.approved ||
      AssignmentAttemptStatus.needsRetry => 'Historical review',
    };
  }
  if (attempt.status == AssignmentAttemptStatus.needsRetry) {
    return 'Historical needs retry';
  }
  if (attempt.status == AssignmentAttemptStatus.inProgress ||
      attempt.status == AssignmentAttemptStatus.draft) {
    return 'Continue practice';
  }
  if (attempt.status == AssignmentAttemptStatus.submitted) {
    return 'Awaiting check';
  }
  if (attempt.status == AssignmentAttemptStatus.checked) return 'Checked';
  if (attempt.status == AssignmentAttemptStatus.unsubmitting) {
    return 'Withdrawing';
  }
  return 'Historical review';
}

bool canStartAssignedMovement(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission, {
  Iterable<AssignmentAttempt> activityAttempts = const [],
}) {
  if (!assignment.isActive) return false;
  if (assignment.isTemplateScored) {
    return isTeacherAssignmentSubmissionOpen(assignment: assignment);
  }
  if (!assignment.isTeacherCreated) return true;
  if (!isTeacherAssignmentSubmissionOpen(assignment: assignment)) return false;
  if (assignment.activityAssessment != null) {
    if (assignment.gradingLocked) return false;
    final attempts = _teacherActivityAttempts(
      activityAttempts: activityAttempts,
      attempt: attempt,
      submission: submission,
    );
    final workflow = _latestTeacherActivityWorkflowAttempt(attempts);
    if (workflow?.status == AssignmentAttemptStatus.checked) return false;
    if (attempts.any(
      (candidate) =>
          candidate.hasAttachedDraftClip || candidate.isDraftClipRemovalPending,
    )) {
      return false;
    }
    final maximumAttempts = assignment.attemptPolicy.maximumAttempts;
    final consumedAttempts = attempts
        .where((candidate) => candidate.recordingStartedAt != null)
        .length;
    return maximumAttempts == null || consumedAttempts < maximumAttempts;
  }
  final current = submission ?? attempt;
  if (current?.hasAttachedDraftClip == true ||
      current?.isDraftClipRemovalPending == true) {
    return false;
  }
  return current == null ||
      current.status == AssignmentAttemptStatus.draft ||
      current.status == AssignmentAttemptStatus.inProgress;
}

List<AssignmentAttempt> _teacherActivityAttempts({
  required Iterable<AssignmentAttempt> activityAttempts,
  required AssignmentAttempt? attempt,
  required AssignmentAttempt? submission,
}) {
  final byId = <String, AssignmentAttempt>{
    for (final candidate in activityAttempts)
      if (candidate.activityAssessmentSnapshot != null) candidate.id: candidate,
  };
  for (final candidate in [attempt, submission]) {
    if (candidate?.activityAssessmentSnapshot != null) {
      byId[candidate!.id] = candidate;
    }
  }
  return byId.values.toList(growable: false);
}

AssignmentAttempt? _latestTeacherActivityWorkflowAttempt(
  Iterable<AssignmentAttempt> attempts,
) {
  AssignmentAttempt? latest;
  for (final candidate in attempts) {
    if (candidate.isAbandonedTeacherReviewDraft) continue;
    if (latest == null ||
        (candidate.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
          latest.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        )) {
      latest = candidate;
    }
  }
  return latest;
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
  return 'Due ${formatElixrDate(local)}';
}

String assignedMovementStatusLabel(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isTemplateScored) {
    if (attempt == null) return 'Not started';
    return attempt.rubricTotal == null ? 'Submitted' : 'Scored';
  }
  if (assignment.isTeacherCreated) {
    final current = submission ?? attempt;
    if (current == null ||
        current.attemptKind == AssignmentAttemptKind.teacherReviewDraft) {
      return 'Not submitted';
    }
    return switch (current.status) {
      AssignmentAttemptStatus.draft || AssignmentAttemptStatus.inProgress =>
        current.hasAttachedDraftClip ? 'Ready to turn in' : 'Not submitted',
      AssignmentAttemptStatus.submitted =>
        current.isCanonicalTeacherReviewSubmission
            ? 'Awaiting check'
            : 'Awaiting review',
      AssignmentAttemptStatus.unsubmitting => 'Withdrawing',
      AssignmentAttemptStatus.checked => 'Checked',
      AssignmentAttemptStatus.approved => 'Approved',
      AssignmentAttemptStatus.needsRetry => 'Needs retry',
    };
  }
  return switch (attempt?.status) {
    null => 'Not started',
    AssignmentAttemptStatus.draft => 'Draft',
    AssignmentAttemptStatus.inProgress => 'In progress',
    AssignmentAttemptStatus.submitted => 'Submitted',
    AssignmentAttemptStatus.unsubmitting => 'Withdrawing',
    AssignmentAttemptStatus.checked => 'Checked',
    AssignmentAttemptStatus.approved => 'Approved',
    AssignmentAttemptStatus.needsRetry => 'Needs retry',
  };
}

Color assignedMovementStatusColor(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isTemplateScored) return AppColors.accent;
  final label = assignedMovementStatusLabel(assignment, attempt, submission);
  return switch (label) {
    'Approved' || 'Checked' => AppColors.success,
    'Awaiting review' || 'Awaiting check' || 'Submitted' => AppColors.accent,
    'Needs retry' => AppColors.error,
    'Withdrawing' => AppColors.warning,
    'In progress' || 'Draft' => AppColors.primary,
    _ => AppColors.accentSoft,
  };
}

String assignedMovementStatusLine(
  GroupAssignment assignment,
  AssignmentAttempt? attempt,
  AssignmentAttempt? submission,
) {
  if (assignment.isTemplateScored) {
    final total = attempt?.rubricTotal;
    return total == null
        ? 'Automatic ELIXR Assessment · Wrist Stall'
        : 'Automatic ELIXR Assessment · ${AssessmentScoreDisplay.officialWithPerformance(total)}';
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
  if (assignment.isTemplateScored) {
    return assignedMovementStatusLine(assignment, attempt, submission);
  }
  if (assignment.isTeacherCreated) {
    final current = submission ?? attempt;
    final feedback = current?.reviewFeedback?.trim();
    if (current?.isChecked == true &&
        current?.gradeScore != null &&
        current?.gradeMaxScore != null) {
      final score =
          'Teacher Grade ${AssessmentScoreDisplay.teacherActivity(earned: current!.gradeScore!, maximum: current.gradeMaxScore!)}';
      if (feedback != null && feedback.isNotEmpty) {
        return '$score · $feedback';
      }
      return score;
    }
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
