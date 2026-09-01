import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/group_assignment.dart';

/// Distinct solid headers so class cards stay easy to tell apart, in the
/// same family as Google Classroom course tiles.
const classHeaderColors = <Color>[
  Color(0xFFE5397A),
  Color(0xFF5C6B73),
  Color(0xFF7C4DFF),
  Color(0xFF37474F),
  Color(0xFF1E88E5),
  Color(0xFF2E7D32),
];

int _stableIdHash(String groupId) {
  var hash = 0;
  for (final code in groupId.codeUnits) {
    hash = (hash + code) & 0x7fffffff;
  }
  return hash;
}

/// Solid header color for a class card or detail hero.
Color traineeClassHeaderColor(String groupId) {
  return classHeaderColors[_stableIdHash(groupId) % classHeaderColors.length];
}

/// Stable brand accent for a class card or detail hero.
TraineeClassAccent traineeClassAccent(String groupId) {
  final header = traineeClassHeaderColor(groupId);
  return TraineeClassAccent(
    start: header,
    end: Color.lerp(header, const Color(0xFF000000), 0.22)!,
  );
}

@immutable
class TraineeClassAccent {
  const TraineeClassAccent({required this.start, required this.end});

  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, Color.lerp(start, end, 0.42)!, end],
  );
}

/// One upcoming assignment line on a class card.
@immutable
class ClassCardWorkItem {
  const ClassCardWorkItem({required this.dueLabel, required this.title});

  final String dueLabel;
  final String title;
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String classCardDueLabel(DateTime? dueAt, {DateTime? now}) {
  if (dueAt == null) return 'Assigned';
  final local = dueAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final dueDay = DateTime(local.year, local.month, local.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final diff = dueDay.difference(todayDay).inDays;
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff > 1 && diff < 7) {
    return 'Due ${_weekdayNames[local.weekday - 1]}';
  }
  return 'Due ${formatElixrDate(local)}';
}

List<ClassCardWorkItem> classCardWorkItemsFromAssignments(
  Iterable<GroupAssignment> assignments, {
  DateTime? now,
  int limit = 2,
}) {
  final active = [
    for (final assignment in assignments)
      if (assignment.isActive) assignment,
  ];
  active.sort((a, b) {
    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue != null && bDue != null) return aDue.compareTo(bDue);
    if (aDue != null) return -1;
    if (bDue != null) return 1;
    final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aAt.compareTo(bAt);
  });
  return [
    for (final assignment in active.take(limit))
      ClassCardWorkItem(
        dueLabel: classCardDueLabel(assignment.dueAt, now: now),
        title: assignment.displayTitle,
      ),
  ];
}

/// Classroom-style class card. Opens the class detail page.
class TraineeClassCard extends StatelessWidget {
  const TraineeClassCard({
    super.key,
    required this.groupId,
    required this.className,
    required this.teacherName,
    required this.onOpen,
    this.sectionLabel,
    this.workItems = const [],
    this.ownerPhotoUrl,
    this.ownerInitials,
    this.cardKey,
    this.menuItems,
    this.onOpenPeople,
    this.onOpenClasswork,
  });

  final String groupId;
  final String className;
  final String teacherName;
  final VoidCallback onOpen;
  final String? sectionLabel;
  final List<ClassCardWorkItem> workItems;
  final String? ownerPhotoUrl;
  final String? ownerInitials;
  final Key? cardKey;
  final List<MenuFlyoutItem> Function(BuildContext context)? menuItems;
  final VoidCallback? onOpenPeople;
  final VoidCallback? onOpenClasswork;

  static const double _headerHeight = 96;
  static const double _avatarRadius = 32;
  static const double _cardHeight = 272;
  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final header = traineeClassHeaderColor(groupId);
    final initials = (ownerInitials == null || ownerInitials!.trim().isEmpty)
        ? userInitials(teacherName)
        : ownerInitials!;
    return ElixHoverSurface(
      borderRadius: _radius,
      onTap: onOpen,
      child: Container(
        key: cardKey ?? Key('teacher_access_group_$groupId'),
        height: _cardHeight,
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : context.elixBorder.withValues(alpha: isDark ? 0.45 : 0.7),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _headerHeight,
                    child: _ClassCardHeader(
                      groupId: groupId,
                      color: header,
                      title: className,
                      sectionLabel: sectionLabel,
                      teacherName: teacherName,
                      highContrast: highContrast,
                      menuItems: menuItems,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 88, 8),
                      child: workItems.isEmpty
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < workItems.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 12),
                                  _ClassCardWorkLine(item: workItems[i]),
                                ],
                              ],
                            ),
                    ),
                  ),
                  Divider(
                    style: DividerThemeData(
                      decoration: BoxDecoration(
                        color: highContrast
                            ? context.elixBorder
                            : context.elixBorder.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Tooltip(
                            message: 'People',
                            child: IconButton(
                              key: Key('class_card_people_$groupId'),
                              icon: Icon(
                                FluentIcons.people,
                                size: 16,
                                color: context.elixTextSecondary,
                              ),
                              onPressed: onOpenPeople ?? onOpen,
                            ),
                          ),
                          Tooltip(
                            message: 'Classwork',
                            child: IconButton(
                              key: Key('class_card_folder_$groupId'),
                              icon: Icon(
                                FluentIcons.folder,
                                size: 16,
                                color: context.elixTextSecondary,
                              ),
                              onPressed: onOpenClasswork ?? onOpen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: _headerHeight - _avatarRadius,
                right: 16,
                child: IgnorePointer(
                  child: Container(
                    width: _avatarRadius * 2,
                    height: _avatarRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.elixCardSurface,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: ClipOval(
                      child: ProfileAvatarWidget(
                        key: Key(
                          'teacher_access_group_teacher_avatar_$groupId',
                        ),
                        radius: _avatarRadius - 3,
                        showBorder: false,
                        initials: initials,
                        networkImageUrl: ownerPhotoUrl,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassCardHeader extends StatelessWidget {
  const _ClassCardHeader({
    required this.groupId,
    required this.color,
    required this.title,
    required this.teacherName,
    required this.highContrast,
    this.sectionLabel,
    this.menuItems,
  });

  final String groupId;
  final Color color;
  final String title;
  final String teacherName;
  final bool highContrast;
  final String? sectionLabel;
  final List<MenuFlyoutItem> Function(BuildContext context)? menuItems;

  @override
  Widget build(BuildContext context) {
    final section = sectionLabel?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: color),
        if (!highContrast) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x26FFFFFF), Color(0x14000000)],
              ),
            ),
          ),
          Positioned(
            right: -18,
            bottom: -28,
            child: IgnorePointer(
              child: Icon(
                FluentIcons.education,
                size: 108,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 40, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.headingMedium.copyWith(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              if (section != null && section.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                teacherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (menuItems != null)
          Positioned(
            top: 4,
            right: 2,
            child: _ClassCardOverflowButton(
              groupId: groupId,
              menuItems: menuItems!,
            ),
          ),
      ],
    );
  }
}

class _ClassCardOverflowButton extends StatefulWidget {
  const _ClassCardOverflowButton({
    required this.groupId,
    required this.menuItems,
  });

  final String groupId;
  final List<MenuFlyoutItem> Function(BuildContext context) menuItems;

  @override
  State<_ClassCardOverflowButton> createState() =>
      _ClassCardOverflowButtonState();
}

class _ClassCardOverflowButtonState extends State<_ClassCardOverflowButton> {
  final _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  void _showMenu() {
    _flyout.showFlyout<void>(
      placementMode: FlyoutPlacementMode.bottomRight,
      builder: (context) => MenuFlyout(
        constraints: const BoxConstraints(minWidth: 160),
        items: widget.menuItems(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyout,
      child: IconButton(
        key: Key('class_card_more_${widget.groupId}'),
        icon: const Icon(
          FluentIcons.more_vertical,
          size: 14,
          color: Colors.white,
        ),
        onPressed: _showMenu,
      ),
    );
  }
}

class _ClassCardWorkLine extends StatelessWidget {
  const _ClassCardWorkLine({required this.item});

  final ClassCardWorkItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.dueLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: context.elixTextSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body.copyWith(
            fontSize: 13,
            height: 1.25,
            color: context.elixTextPrimary,
          ),
        ),
      ],
    );
  }
}

/// Pink-to-purple class hero used by the class detail page.
class TraineeClassHero extends StatelessWidget {
  const TraineeClassHero({
    super.key,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.compact = false,
    this.subtitleIcon = FluentIcons.contact,
  });

  final TraineeClassAccent accent;
  final String title;
  final String subtitle;
  final bool compact;
  final IconData subtitleIcon;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final titleStyle =
        (compact ? AppTheme.headingMedium : AppTheme.headingLarge).copyWith(
          color: Colors.white,
          fontSize: compact ? 20 : 28,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.3,
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: highContrast ? accent.start : null,
            gradient: highContrast ? null : accent.gradient,
          ),
        ),
        if (!highContrast) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x26FFFFFF), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            right: compact ? -20 : -24,
            bottom: compact ? -36 : -48,
            child: IgnorePointer(
              child: Icon(
                FluentIcons.education,
                size: compact ? 120 : 168,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              SizedBox(height: compact ? 6 : 8),
              Row(
                children: [
                  Icon(
                    subtitleIcon,
                    size: compact ? 12 : 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: compact ? 12 : 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Framed class hero used by trainee and teacher class detail pages.
class TraineeClassHeroBanner extends StatelessWidget {
  const TraineeClassHeroBanner({
    super.key,
    required this.groupId,
    required this.title,
    required this.subtitle,
    this.height = 176,
    this.subtitleIcon = FluentIcons.contact,
  });

  final String groupId;
  final String title;
  final String subtitle;
  final double height;
  final IconData subtitleIcon;

  @override
  Widget build(BuildContext context) {
    final accent = traineeClassAccent(groupId);
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : Color.alphaBlend(
                  accent.start.withValues(alpha: isDark ? 0.28 : 0.18),
                  context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
                ),
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accent.start.withValues(alpha: isDark ? 0.18 : 0.12),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TraineeClassHero(
          accent: accent,
          title: title,
          subtitle: subtitle,
          subtitleIcon: subtitleIcon,
        ),
      ),
    );
  }
}
