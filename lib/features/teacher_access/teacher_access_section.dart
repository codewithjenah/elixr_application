import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_stat_card.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import 'teacher_access_controller.dart';
import 'trainee_class_card.dart';

const double _accessWideBreakpoint = 1080;
const double _accessCompactBreakpoint = 760;
const double _accessControlsBreakpoint = 1180;

/// Reusable Teacher Access body hosted by the trainee shell destination.
class TeacherAccessSection extends StatefulWidget {
  const TeacherAccessSection({
    super.key,
    this.controller,
    this.isActive = false,
    this.onOpenClass,
  });

  final TeacherAccessController? controller;
  final bool isActive;
  final ValueChanged<String>? onOpenClass;

  @override
  State<TeacherAccessSection> createState() => TeacherAccessSectionState();
}

class TeacherAccessSectionState extends State<TeacherAccessSection> {
  TeacherAccessController? _owned;
  TeacherAccessController? _active;
  bool _started = false;

  TeacherAccessController? get _controller => widget.controller ?? _active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureController();
    if (widget.isActive) _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant TeacherAccessSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureController();
    if (widget.isActive) _startIfNeeded();
  }

  void _ensureController() {
    if (widget.controller != null) {
      _active = widget.controller;
      return;
    }
    if (!widget.isActive) return;
    if (_owned != null) {
      _active = _owned;
      return;
    }
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (userId == null) return;
    final groupRepository = context.read<GroupRepository>();
    final joinCodeResolver = context.read<JoinCodeResolver>();
    _owned = TeacherAccessController(
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: userId,
      traineeDisplayName: user!.fullName,
      assignmentRepository: _maybeRead<ClassroomAssignmentRepository>(context),
      publicProfileRepository: _maybeRead<PublicProfileRepository>(context),
    );
    _owned!.addListener(_onControllerTick);
    _active = _owned;
  }

  void _startIfNeeded() {
    if (_started) return;
    final controller = _controller;
    if (controller == null) return;
    _started = true;
    controller.start();
  }

  void _onControllerTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _owned?.removeListener(_onControllerTick);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive && !_started) {
      return const SizedBox.shrink();
    }

    final controller = _controller;
    if (controller == null) {
      return const ElixStatusPanel(
        message: 'Sign in to manage Teacher Access.',
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const Center(child: ProgressRing());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final compact = width < _accessCompactBreakpoint;

            return SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AccessIntro(),
                  const SizedBox(height: AppSpacing.lg),
                  _AccessMetricsRow(controller: controller),
                  const SizedBox(height: AppSpacing.lg),
                  if (controller.errorMessage != null) ...[
                    ElixStatusPanel(
                      message: controller.errorMessage!,
                      isError: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _AccessControls(
                    controller: controller,
                    compact: compact,
                    sideBySide: width >= _accessControlsBreakpoint,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (controller.approvedGroupMemberships.isEmpty) ...[
                    const _EmptyClassesCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ] else ...[
                    const _ClassesHeading(),
                    const SizedBox(height: AppSpacing.md),
                    _ApprovedClassesGrid(
                      controller: controller,
                      compact: compact,
                      onOpenClass: widget.onOpenClass,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AccessControls extends StatelessWidget {
  const _AccessControls({
    required this.controller,
    required this.compact,
    required this.sideBySide,
  });

  final TeacherAccessController controller;
  final bool compact;
  final bool sideBySide;

  @override
  Widget build(BuildContext context) {
    final join = _JoinTeacherCard(controller: controller, compact: compact);
    final pending = _PendingJoinsCard(controller: controller);

    if (!sideBySide) {
      return Column(
        children: [
          join,
          const SizedBox(height: AppSpacing.md),
          pending,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: join),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: pending),
      ],
    );
  }
}

class _AccessIntro extends StatelessWidget {
  const _AccessIntro();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Text(
        'Ask to join a class with the code from your teacher. After they '
        'accept you, open a class card to see classmates and assignments. '
        'Each class stays separate.',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
    );
  }
}

class _AccessMetricsRow extends StatelessWidget {
  const _AccessMetricsRow({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ElixStatCard(
              label: 'Waiting',
              value: '${controller.pendingJoinCount}',
              icon: FluentIcons.inbox,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ElixStatCard(
              label: 'My classes',
              value: '${controller.approvedGroupMemberships.length}',
              icon: FluentIcons.completed,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinTeacherCard extends StatefulWidget {
  const _JoinTeacherCard({required this.controller, required this.compact});

  final TeacherAccessController controller;
  final bool compact;

  @override
  State<_JoinTeacherCard> createState() => _JoinTeacherCardState();
}

class _JoinTeacherCardState extends State<_JoinTeacherCard> {
  late final TextEditingController _textController;

  TeacherAccessController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: controller.codeInput);
  }

  @override
  void didUpdateWidget(covariant _JoinTeacherCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_textController.text != controller.codeInput &&
        controller.codeInput.isNotEmpty) {
      _textController.value = TextEditingValue(
        text: controller.codeInput,
        selection: TextSelection.collapsed(offset: controller.codeInput.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AccessAccordionCard(
      key: const Key('teacher_access_join_card'),
      toggleKey: const Key('teacher_access_join_toggle'),
      title: 'Join a class',
      subtitle: 'Enter the code shared by your teacher',
      icon: FluentIcons.add_friend,
      accent: AppColors.primary,
      child: _JoinCardBody(
        controller: controller,
        textController: _textController,
        compact: widget.compact,
      ),
    );
  }
}

class _AccessAccordionCard extends StatefulWidget {
  const _AccessAccordionCard({
    super.key,
    required this.toggleKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final Key toggleKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  State<_AccessAccordionCard> createState() => _AccessAccordionCardState();
}

class _AccessAccordionCardState extends State<_AccessAccordionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  bool _expanded = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) FocusScope.of(context).unfocus();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = _expanded ? 1 : 0;
    } else if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ElixPanelCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: '${_expanded ? 'Collapse' : 'Expand'} ${widget.title}',
            child: FocusableActionDetector(
              onShowFocusHighlight: (focused) {
                setState(() => _focused = focused);
              },
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _toggle();
                    return null;
                  },
                ),
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  key: widget.toggleKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : ElixMotion.standard,
                    constraints: const BoxConstraints(minHeight: 76),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: highContrast
                          ? context.elixCardSurface
                          : widget.accent.withValues(
                              alpha: _expanded ? 0.075 : (_hovered ? 0.04 : 0),
                            ),
                      borderRadius: BorderRadius.vertical(
                        top: const Radius.circular(15),
                        bottom: Radius.circular(_expanded ? 0 : 15),
                      ),
                      border: _focused
                          ? Border.all(
                              color: context.elixColors.focusRing,
                              width: highContrast
                                  ? ElixFocus.ringWidthHighContrast
                                  : ElixFocus.ringWidth,
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 38,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.accent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: AppTheme.headingMedium.copyWith(
                                  fontSize: 16,
                                  color: context.elixTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.caption.copyWith(
                                  color: context.elixTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeInOutCubic,
                          child: Icon(
                            FluentIcons.chevron_down,
                            size: 14,
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ClipRect(
            child: SizeTransition(
              sizeFactor: _expandAnimation,
              alignment: Alignment.topCenter,
              child: ExcludeSemantics(
                excluding: !_expanded,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: context.elixBorder.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinCardBody extends StatelessWidget {
  const _JoinCardBody({
    required this.controller,
    required this.textController,
    required this.compact,
  });

  final TeacherAccessController controller;
  final TextEditingController textController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return controller.joinStep == JoinTeacherStep.enterCode
        ? _JoinCodeEntry(
            controller: controller,
            textController: textController,
            compact: compact,
          )
        : _JoinConfirmActions(controller: controller);
  }
}

class _JoinCodeEntry extends StatelessWidget {
  const _JoinCodeEntry({
    required this.controller,
    required this.textController,
    required this.compact,
  });

  /// Keeps Continue at Fluent TextBox min height (32) beside the code field.
  static const _continuePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 5.5,
  );

  final TeacherAccessController controller;
  final TextEditingController textController;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final field = TextBox(
      key: const Key('teacher_access_roster_code'),
      placeholder: 'XXXX-XXXX-XXXX',
      controller: textController,
      onChanged: controller.setCodeInput,
    );
    final action = ElixPrimaryButton(
      key: const Key('teacher_access_resolve_code'),
      label: 'Continue',
      expanded: compact,
      padding: _continuePadding,
      isLoading: controller.busy,
      onPressed: controller.busy ? null : controller.resolveCode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          field,
          const SizedBox(height: AppSpacing.md),
          action,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: field),
              const SizedBox(width: AppSpacing.md),
              action,
            ],
          ),
        if (controller.joinError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            controller.joinError!,
            key: const Key('teacher_access_join_error'),
            style: const TextStyle(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _JoinConfirmActions extends StatelessWidget {
  const _JoinConfirmActions({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            if (controller.resolvedGroupName != null)
              controller.resolvedGroupName!,
            controller.resolvedGroupInvite?.teacherDisplayName ?? 'Teacher',
          ].join(' · '),
          key: const Key('teacher_access_confirm_teacher'),
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        if (controller.joinError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            controller.joinError!,
            key: const Key('teacher_access_join_error'),
            style: const TextStyle(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ElixPrimaryButton(
              key: const Key('teacher_access_confirm_join'),
              label: 'Send request',
              expanded: false,
              isLoading: controller.busy,
              onPressed: controller.busy ? null : controller.confirmJoin,
            ),
            Button(
              onPressed: controller.busy ? null : controller.resetJoin,
              child: const Text('Use a different code'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PendingJoinsCard extends StatelessWidget {
  const _PendingJoinsCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    final groups = controller.pendingGroupMemberships;
    final rows = <Widget>[];

    void addRow(Widget row) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppSpacing.md));
      }
      rows.add(row);
    }

    for (final membership in groups) {
      addRow(
        _AccessListRow(
          title: controller.groupNamesById[membership.groupId]?.name ?? 'Class',
          subtitle:
              'Waiting for ${membership.teacherDisplayName} to accept you · '
              '${_formatTime(membership.createdAt)}',
          trailing: Button(
            key: Key('teacher_access_cancel_group_${membership.id}'),
            onPressed: controller.busy
                ? null
                : () => controller.cancelPendingGroup(membership),
            child: const Text('Cancel'),
          ),
        ),
      );
    }
    return _AccessAccordionCard(
      key: const Key('teacher_access_pending_card'),
      toggleKey: const Key('teacher_access_pending_toggle'),
      title: 'Waiting to join',
      subtitle: groups.isEmpty
          ? 'No requests awaiting teacher approval'
          : '${groups.length} ${groups.length == 1 ? 'request' : 'requests'} awaiting approval',
      icon: FluentIcons.inbox,
      accent: AppColors.accent,
      child: rows.isEmpty
          ? const _EmptyHint(
              key: Key('teacher_access_pending_empty'),
              message: 'No join requests waiting.',
            )
          : Column(children: rows),
    );
  }
}

class _EmptyClassesCard extends StatelessWidget {
  const _EmptyClassesCard();

  @override
  Widget build(BuildContext context) {
    return const _AccessSectionPanel(
      title: 'Your classes',
      icon: FluentIcons.completed,
      child: _EmptyHint(
        message: 'You are not in a class yet. Join with a class code above.',
      ),
    );
  }
}

class _ClassesHeading extends StatelessWidget {
  const _ClassesHeading();

  @override
  Widget build(BuildContext context) {
    return const ElixSectionHeader(heading: 'Your classes');
  }
}

class _ApprovedClassesGrid extends StatelessWidget {
  const _ApprovedClassesGrid({
    required this.controller,
    required this.compact,
    this.onOpenClass,
  });

  final TeacherAccessController controller;
  final bool compact;
  final ValueChanged<String>? onOpenClass;

  @override
  Widget build(BuildContext context) {
    final openClass = onOpenClass;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = compact
            ? 1
            : width >= _accessWideBreakpoint
            ? 3
            : 2;
        final gap = AppSpacing.md;
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final membership in controller.approvedGroupMemberships)
              SizedBox(
                width: cardWidth,
                child: TraineeClassCard(
                  groupId: membership.groupId,
                  className:
                      controller.groupNamesById[membership.groupId]?.name ??
                      'Class',
                  teacherName: membership.teacherDisplayName,
                  sectionLabel:
                      controller.groupNamesById[membership.groupId]?.isActive ==
                          false
                      ? 'Archived'
                      : null,
                  workItems: classCardWorkItemsFromAssignments(
                    controller.assignmentsFor(membership.groupId),
                  ),
                  ownerInitials: userInitials(membership.teacherDisplayName),
                  ownerPhotoUrl: controller.teacherProfilePictureUrlFor(
                    membership.teacherId,
                  ),
                  onOpen: () => openClass?.call(membership.groupId),
                  menuItems: openClass == null
                      ? null
                      : (_) => [
                          MenuFlyoutItem(
                            text: const Text('Open class'),
                            onPressed: () => openClass(membership.groupId),
                          ),
                          MenuFlyoutItem(
                            key: Key(
                              'teacher_access_leave_group_${membership.id}',
                            ),
                            text: const Text('Leave class'),
                            onPressed: controller.busy
                                ? null
                                : () => _confirmLeaveClass(
                                    context,
                                    controller,
                                    membership,
                                  ),
                          ),
                        ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AccessSectionPanel extends StatelessWidget {
  const _AccessSectionPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 148),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primarySoft),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.headingMedium.copyWith(
                      fontSize: 16,
                      color: context.elixTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTheme.bodySecondary.copyWith(
        color: context.elixTextSecondary,
        height: 1.4,
      ),
    );
  }
}

class _AccessListRow extends StatelessWidget {
  const _AccessListRow({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              height: 1.4,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ],
      ),
    );
  }
}

String _formatTime(DateTime? value) {
  if (value == null) return 'recently';
  return DateFormat.yMMMd().add_jm().format(value.toLocal());
}

Future<void> _confirmLeaveClass(
  BuildContext context,
  TeacherAccessController controller,
  GroupMembership membership,
) async {
  final className =
      controller.groupNamesById[membership.groupId]?.name ?? 'this class';
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: Text('Leave $className?'),
      content: const Text(
        'You will no longer see this class or its assignments. You can ask '
        'to join again later with a current class code.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          key: const Key('teacher_access_confirm_leave'),
          child: const Text('Leave class'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.leaveApprovedGroup(membership);
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
