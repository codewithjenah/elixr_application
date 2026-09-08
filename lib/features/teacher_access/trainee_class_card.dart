import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/group_assignment.dart';

/// Distinct classroom accents so class cards stay easy to tell apart
/// while remaining in ELIXR's pink/purple environment.
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

LinearGradient _classCardHeroGradient(Color header, {required bool isDark}) {
  final lifted = Color.lerp(
    header,
    const Color(0xFFFFFFFF),
    isDark ? 0.18 : 0.08,
  )!;
  final deep = Color.lerp(
    header,
    isDark ? const Color(0xFF140816) : const Color(0xFF2C1238),
    isDark ? 0.42 : 0.26,
  )!;
  final elixrBlend = Color.lerp(
    header,
    AppColors.accent,
    isDark ? 0.32 : 0.20,
  )!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lifted, header, elixrBlend, deep],
    stops: const [0.0, 0.36, 0.68, 1.0],
  );
}

bool _isClassroomStatusLabel(String? label) {
  final value = label?.trim();
  return value == 'Active' || value == 'Archived';
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

/// Classroom workspace card. Opens the class detail page.
class TraineeClassCard extends StatefulWidget {
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

  static const double _headerHeight = 108;
  static const double _avatarSize = 52;
  static const double _cardHeight = 272;
  static const double _radius = 16;
  static const double _identityHeight = 40;
  static const double _footerHeight = 44;
  static const int _workSlotCount = 2;

  @override
  State<TraineeClassCard> createState() => _TraineeClassCardState();
}

class _TraineeClassCardState extends State<TraineeClassCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final glowScale = context.elixWorkspaceVisuals.persistentGlowScale;
    final header = traineeClassHeaderColor(widget.groupId);
    final initials =
        (widget.ownerInitials == null || widget.ownerInitials!.trim().isEmpty)
        ? userInitials(widget.teacherName)
        : widget.ownerInitials!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lift = highContrast || reduceMotion
        ? 0.0
        : (_pressed ? 0.0 : (_hovered ? -2.0 : 0.0));

    final borderColor = highContrast
        ? (_focused ? colors.focusRing : colors.borderStrong)
        : _focused
        ? colors.focusRing
        : Color.alphaBlend(
            header.withValues(
              alpha: _hovered ? (isDark ? 0.50 : 0.34) : (isDark ? 0.26 : 0.16),
            ),
            colors.borderSubtle,
          );
    final borderWidth = _focused
        ? (highContrast ? ElixFocus.ringWidthHighContrast : ElixFocus.ringWidth)
        : (highContrast ? 2.0 : 1.0);

    final shadows = highContrast
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: colors.shadow.withValues(
                alpha: isDark
                    ? (_hovered ? 0.48 : 0.34)
                    : (_hovered ? 0.14 : 0.08),
              ),
              blurRadius: _hovered ? 18 : 12,
              offset: Offset(0, _pressed ? 2 : (_hovered ? 7 : 4)),
            ),
            BoxShadow(
              color: header.withValues(
                alpha:
                    (isDark ? 0.18 : 0.10) *
                    glowScale *
                    (_hovered ? 1.25 : 0.8) *
                    (_pressed ? 0.55 : 1),
              ),
              blurRadius: _hovered ? 20 : 14,
              spreadRadius: -8,
              offset: Offset(0, _hovered ? 9 : 7),
            ),
          ];

    return Semantics(
      button: true,
      label: widget.className,
      onTap: widget.onOpen,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) {
          if (_hovered != hovered) setState(() => _hovered = hovered);
        },
        onShowFocusHighlight: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onOpen();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.standard),
            curve: ElixMotion.standardCurve,
            transform: Matrix4.translationValues(0, lift, 0),
            transformAlignment: Alignment.center,
            child: Container(
              key:
                  widget.cardKey ??
                  Key('teacher_access_group_${widget.groupId}'),
              height: TraineeClassCard._cardHeight,
              decoration: BoxDecoration(
                color: context.elixCardSurface,
                borderRadius: BorderRadius.circular(TraineeClassCard._radius),
                boxShadow: shadows,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TraineeClassCard._radius),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TraineeClassCard._radius),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: TraineeClassCard._headerHeight,
                          child: _ClassCardHero(
                            groupId: widget.groupId,
                            color: header,
                            title: widget.className,
                            sectionLabel: widget.sectionLabel,
                            highContrast: highContrast,
                            isDark: isDark,
                            menuItems: widget.menuItems,
                          ),
                        ),
                        SizedBox(
                          height: TraineeClassCard._identityHeight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              8,
                              80,
                              4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  FluentIcons.contact,
                                  size: 12,
                                  color: context.elixTextSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.teacherName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.caption.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                      color: context.elixTextPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              4,
                            ),
                            child: widget.workItems.isEmpty
                                ? const Align(
                                    alignment: Alignment.topLeft,
                                    child: _ClassCardEmptyWork(),
                                  )
                                : Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < TraineeClassCard._workSlotCount;
                                        i++
                                      )
                                        Expanded(
                                          child: i < widget.workItems.length
                                              ? _ClassCardWorkLine(
                                                  item: widget.workItems[i],
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                        SizedBox(
                          height: TraineeClassCard._footerHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: highContrast
                                      ? colors.borderStrong
                                      : colors.borderSubtle.withValues(
                                          alpha: isDark ? 0.7 : 0.9,
                                        ),
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _ClassCardActionButton(
                                    buttonKey: Key(
                                      'class_card_people_${widget.groupId}',
                                    ),
                                    tooltip: 'People',
                                    icon: FluentIcons.people,
                                    onPressed:
                                        widget.onOpenPeople ?? widget.onOpen,
                                  ),
                                  const SizedBox(width: 2),
                                  _ClassCardActionButton(
                                    buttonKey: Key(
                                      'class_card_folder_${widget.groupId}',
                                    ),
                                    tooltip: 'Classwork',
                                    icon: FluentIcons.folder,
                                    onPressed:
                                        widget.onOpenClasswork ?? widget.onOpen,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top:
                          TraineeClassCard._headerHeight -
                          (TraineeClassCard._avatarSize / 2),
                      right: AppSpacing.md,
                      child: IgnorePointer(
                        child: _ClassCardTeacherPortrait(
                          groupId: widget.groupId,
                          accent: header,
                          initials: initials,
                          photoUrl: widget.ownerPhotoUrl,
                          highContrast: highContrast,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassCardHero extends StatelessWidget {
  const _ClassCardHero({
    required this.groupId,
    required this.color,
    required this.title,
    required this.highContrast,
    required this.isDark,
    this.sectionLabel,
    this.menuItems,
  });

  final String groupId;
  final Color color;
  final String title;
  final String? sectionLabel;
  final bool highContrast;
  final bool isDark;
  final List<MenuFlyoutItem> Function(BuildContext context)? menuItems;

  @override
  Widget build(BuildContext context) {
    final section = sectionLabel?.trim();
    final hasSection = section != null && section.isNotEmpty;
    final statusLabel = _isClassroomStatusLabel(section) ? section : null;
    final metadataLabel = statusLabel == null && hasSection ? section : null;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        _ClassCardHeroBackdrop(
          color: color,
          highContrast: highContrast,
          isDark: isDark,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            12,
            menuItems != null ? 48 : AppSpacing.md,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headingMedium.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 22,
                child: statusLabel != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _ClassCardStatusPill(
                          label: statusLabel,
                          archived: statusLabel == 'Archived',
                          highContrast: highContrast,
                        ),
                      )
                    : metadataLabel != null
                    ? Text(
                        metadataLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (menuItems != null)
          Positioned(
            top: 8,
            right: 8,
            child: _ClassCardOverflowButton(
              groupId: groupId,
              menuItems: menuItems!,
            ),
          ),
      ],
    );
  }
}

class _ClassCardHeroBackdrop extends StatelessWidget {
  const _ClassCardHeroBackdrop({
    required this.color,
    required this.highContrast,
    required this.isDark,
  });

  final Color color;
  final bool highContrast;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            gradient: highContrast
                ? null
                : _classCardHeroGradient(color, isDark: isDark),
          ),
        ),
        if (!highContrast) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.72, -0.92),
                radius: 1.15,
                colors: [Color(0x38FFFFFF), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(
            right: -34,
            top: -42,
            child: IgnorePointer(
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: -36,
            child: IgnorePointer(
              child: Icon(
                FluentIcons.education,
                size: 108,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 18,
            right: 18,
            height: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.48),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClassCardStatusPill extends StatelessWidget {
  const _ClassCardStatusPill({
    required this.label,
    required this.archived,
    required this.highContrast,
  });

  final String label;
  final bool archived;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : Colors.white.withValues(alpha: archived ? 0.12 : 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : Colors.white.withValues(alpha: archived ? 0.28 : 0.38),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: 0.2,
          color: highContrast ? context.elixTextPrimary : Colors.white,
        ),
      ),
    );
  }
}

class _ClassCardTeacherPortrait extends StatelessWidget {
  const _ClassCardTeacherPortrait({
    required this.groupId,
    required this.accent,
    required this.initials,
    required this.highContrast,
    required this.isDark,
    this.photoUrl,
  });

  final String groupId;
  final Color accent;
  final String initials;
  final String? photoUrl;
  final bool highContrast;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const size = TraineeClassCard._avatarSize;
    const rim = 2.0;
    const separator = 3.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.elixCardSurface,
        border: Border.all(
          color: highContrast ? context.elixBorder : context.elixCardSurface,
          width: separator,
        ),
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.38 : 0.22),
                  blurRadius: 12,
                  spreadRadius: -1,
                ),
              ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: highContrast
                ? context.elixBorder
                : Colors.white.withValues(alpha: isDark ? 0.92 : 1),
            width: rim,
          ),
        ),
        child: ClipOval(
          child: ProfileAvatarWidget(
            key: Key('teacher_access_group_teacher_avatar_$groupId'),
            radius: (size / 2) - separator - rim,
            showBorder: false,
            initials: initials,
            networkImageUrl: photoUrl,
          ),
        ),
      ),
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
  bool _hovered = false;
  bool _focused = false;

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
    final highContrast = context.isHighContrast;
    final focusedWidth = highContrast
        ? ElixFocus.ringWidthHighContrast
        : ElixFocus.ringWidth;
    return FlyoutTarget(
      controller: _flyout,
      child: Tooltip(
        message: 'More options',
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (hovered) {
            if (_hovered != hovered) setState(() => _hovered = hovered);
          },
          onShowFocusHighlight: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _showMenu();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showMenu,
            child: AnimatedContainer(
              key: Key('class_card_more_${widget.groupId}'),
              duration: ElixMotion.duration(context, ElixMotion.micro),
              curve: ElixMotion.microCurve,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : Colors.black.withValues(alpha: _hovered ? 0.48 : 0.30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused
                      ? context.elixColors.focusRing
                      : (highContrast
                            ? context.elixBorder
                            : Colors.white.withValues(
                                alpha: _hovered ? 0.42 : 0.26,
                              )),
                  width: _focused ? focusedWidth : 1,
                ),
              ),
              child: const Center(
                child: Icon(
                  FluentIcons.more_vertical,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassCardWorkLine extends StatelessWidget {
  const _ClassCardWorkLine({required this.item});

  final ClassCardWorkItem item;

  @override
  Widget build(BuildContext context) {
    final dueToday = item.dueLabel == 'Due today';
    final dueColor = dueToday
        ? context.elixColors.warning
        : context.elixTextSecondary;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.isHighContrast
                ? context.elixCardSurface
                : dueToday
                ? context.elixColors.warning.withValues(alpha: 0.14)
                : context.elixColors.brandSecondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.isHighContrast
                  ? context.elixBorder
                  : (dueToday
                        ? context.elixColors.warning.withValues(alpha: 0.34)
                        : context.elixBorder.withValues(alpha: 0.55)),
            ),
          ),
          child: Icon(
            FluentIcons.assign,
            size: 13,
            color: dueToday
                ? context.elixColors.warning
                : context.elixTextSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body.copyWith(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: context.elixTextPrimary,
                ),
              ),
              Text(
                item.dueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: dueColor,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClassCardEmptyWork extends StatelessWidget {
  const _ClassCardEmptyWork();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.isHighContrast
                ? context.elixCardSurface
                : context.elixColors.surfaceInteractive.withValues(
                    alpha: context.isDarkTheme ? 0.7 : 1,
                  ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.elixBorder.withValues(
                alpha: context.isHighContrast ? 1 : 0.55,
              ),
            ),
          ),
          child: Icon(
            FluentIcons.folder,
            size: 13,
            color: context.elixColors.textMuted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'No upcoming classwork',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClassCardActionButton extends StatefulWidget {
  const _ClassCardActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_ClassCardActionButton> createState() => _ClassCardActionButtonState();
}

class _ClassCardActionButtonState extends State<_ClassCardActionButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final focusedWidth = highContrast
        ? ElixFocus.ringWidthHighContrast
        : ElixFocus.ringWidth;
    return Tooltip(
      message: widget.tooltip,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (hovered) {
          if (_hovered != hovered) setState(() => _hovered = hovered);
        },
        onShowFocusHighlight: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            key: widget.buttonKey,
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: highContrast
                  ? context.elixCardSurface
                  : (_hovered
                        ? colors.interactiveHover
                        : colors.surfaceInteractive.withValues(
                            alpha: context.isDarkTheme ? 0.55 : 0.85,
                          )),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused
                    ? colors.focusRing
                    : (highContrast
                          ? colors.borderStrong
                          : colors.borderSubtle.withValues(
                              alpha: _hovered ? 0.95 : 0.5,
                            )),
                width: _focused ? focusedWidth : 1,
              ),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 15,
                color: context.elixTextSecondary,
              ),
            ),
          ),
        ),
      ),
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
