import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_time_format.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import 'teacher_access_controller.dart';
import 'trainee_class_card.dart';

const double _accessWideBreakpoint = 1080;
const double _accessCompactBreakpoint = 760;
const double _accessControlsBreakpoint = 900;
const double _overviewStackBreakpoint = 560;
const int _classroomSearchThreshold = 4;
const double _workspaceMinHeight = 176;

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
        icon: FluentIcons.contact,
        title: 'Sign in required',
        message: 'Sign in to view your classes.',
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const ElixStatusPanel(
            isLoading: true,
            icon: FluentIcons.people,
            title: 'Loading classrooms',
            message: 'Loading your classrooms.',
          );
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
                  _AccessMetricsRow(controller: controller, width: width),
                  const SizedBox(height: AppSpacing.md),
                  if (controller.errorMessage != null) ...[
                    ElixStatusPanel(
                      message: controller.errorMessage!,
                      isError: true,
                      icon: FluentIcons.error_badge,
                      title: 'Could not load classrooms',
                      actionLabel: 'Retry',
                      onAction: controller.start,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _AccessControls(
                    controller: controller,
                    compact: compact,
                    sideBySide: width >= _accessControlsBreakpoint,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (controller.activeApprovedGroupMemberships.isEmpty)
                    const _EmptyClassesCard()
                  else
                    _YourClassroomsSection(
                      controller: controller,
                      compact: compact,
                      onOpenClass: widget.onOpenClass,
                    ),
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

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: join),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: pending),
        ],
      ),
    );
  }
}

class _AccessMetricsRow extends StatelessWidget {
  const _AccessMetricsRow({required this.controller, required this.width});

  final TeacherAccessController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final waiting = _OverviewTile(
      icon: FluentIcons.inbox,
      accent: AppColors.accent,
      value: '${controller.pendingJoinCount}',
      title: 'Waiting',
      description: 'Join requests awaiting teacher approval.',
    );
    final classrooms = _OverviewTile(
      icon: FluentIcons.completed,
      accent: AppColors.primary,
      value: '${controller.activeApprovedGroupMemberships.length}',
      title: 'My classrooms',
      description: "Classes you're currently a member of.",
    );

    if (width < _overviewStackBreakpoint) {
      return Column(
        children: [
          waiting,
          const SizedBox(height: AppSpacing.sm),
          classrooms,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: waiting),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: classrooms),
        ],
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.accent,
    required this.value,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    return Semantics(
      label: '$value $title. $description',
      child: ElixPanelCard(
        variant: ElixPanelVariant.elevated,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : accent.withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: highContrast
                      ? context.elixBorder
                      : accent.withValues(alpha: 0.32),
                  width: highContrast ? 2 : 1,
                ),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sectionTitle(
                      context,
                      color: context.elixTextPrimary,
                    ).copyWith(fontSize: 28, height: 1.05),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label(color: context.elixTextPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      variant: ElixPanelVariant.elevated,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _workspaceMinHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: highContrast
                        ? context.elixCardSurface
                        : accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: highContrast
                          ? context.elixBorder
                          : accent.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 17),
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
                          fontSize: 16,
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
                          height: 1.3,
                        ),
                      ),
                    ],
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

class _JoinTeacherCard extends StatefulWidget {
  const _JoinTeacherCard({required this.controller, required this.compact});

  final TeacherAccessController controller;
  final bool compact;

  @override
  State<_JoinTeacherCard> createState() => _JoinTeacherCardState();
}

class _JoinTeacherCardState extends State<_JoinTeacherCard> {
  late final TextEditingController _textController;
  late final FocusNode _codeFocus;

  TeacherAccessController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: controller.codeInput);
    _codeFocus = FocusNode();
    _codeFocus.addListener(() {
      if (mounted) setState(() {});
    });
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
    _codeFocus.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _WorkspaceCard(
      key: const Key('teacher_access_join_card'),
      title: 'Join a class',
      subtitle: 'Enter the code shared by your teacher.',
      icon: FluentIcons.add_friend,
      accent: AppColors.primary,
      child: _JoinCardBody(
        controller: controller,
        textController: _textController,
        codeFocus: _codeFocus,
        compact: widget.compact,
        focused: _codeFocus.hasFocus,
      ),
    );
  }
}

class _JoinCardBody extends StatelessWidget {
  const _JoinCardBody({
    required this.controller,
    required this.textController,
    required this.codeFocus,
    required this.compact,
    required this.focused,
  });

  final TeacherAccessController controller;
  final TextEditingController textController;
  final FocusNode codeFocus;
  final bool compact;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return controller.joinStep == JoinTeacherStep.enterCode
        ? _JoinCodeEntry(
            controller: controller,
            textController: textController,
            codeFocus: codeFocus,
            compact: compact,
            focused: focused,
          )
        : _JoinConfirmActions(controller: controller);
  }
}

class _JoinCodeEntry extends StatelessWidget {
  const _JoinCodeEntry({
    required this.controller,
    required this.textController,
    required this.codeFocus,
    required this.compact,
    required this.focused,
  });

  /// Keeps Continue at Fluent TextBox min height (32) beside the code field.
  static const _continuePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 5.5,
  );

  final TeacherAccessController controller;
  final TextEditingController textController;
  final FocusNode codeFocus;
  final bool compact;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final field = _ClassCodeField(
      controller: textController,
      focusNode: codeFocus,
      focused: focused,
      enabled: !controller.busy,
      onChanged: controller.setCodeInput,
      onSubmitted: controller.busy ? null : controller.resolveCode,
    );
    final action = SizedBox(
      key: const Key('teacher_access_resolve_code'),
      height: 32,
      child: ElixPrimaryButton(
        label: 'Continue',
        expanded: compact,
        padding: _continuePadding,
        isLoading: controller.busy,
        onPressed: controller.busy ? null : controller.resolveCode,
      ),
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
          _JoinErrorText(message: controller.joinError!),
        ],
      ],
    );
  }
}

class _ClassCodeField extends StatelessWidget {
  const _ClassCodeField({
    required this.controller,
    required this.focusNode,
    required this.focused,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool focused;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Semantics(
      textField: true,
      label: 'Class code',
      child: TextBox(
        key: const Key('teacher_access_roster_code'),
        focusNode: focusNode,
        placeholder: 'XXXX-XXXX-XXXX',
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted?.call(),
        prefix: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(
            FluentIcons.permissions,
            size: 14,
            color: focused ? colors.brandPrimary : context.elixTextSecondary,
          ),
        ),
        style: AppTheme.body.copyWith(
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: context.elixTextPrimary,
        ),
      ),
    );
  }
}

class _JoinErrorText extends StatelessWidget {
  const _JoinErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.error_badge,
          size: 14,
          color: context.elixColors.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            key: const Key('teacher_access_join_error'),
            style: AppTheme.caption.copyWith(
              color: context.elixColors.error,
              height: 1.35,
            ),
          ),
        ),
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
        const SizedBox(height: 4),
        Text(
          'Send a request so your teacher can add you to this class.',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _JoinSharingSummary(),
        if (controller.joinError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _JoinErrorText(message: controller.joinError!),
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
            _AccessOutlineButton(
              label: 'Use a different code',
              onPressed: controller.busy ? null : controller.resetJoin,
            ),
          ],
        ),
      ],
    );
  }
}

class _JoinSharingSummary extends StatelessWidget {
  const _JoinSharingSummary();

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;

    return Container(
      key: const Key('teacher_access_join_sharing_summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highContrast ? colors.surfaceRaised : colors.surfaceTinted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highContrast ? colors.borderStrong : colors.borderSubtle,
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.shield, size: 18, color: colors.brandPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'What your Teacher can see',
                    style: AppTheme.headingMedium.copyWith(
                      fontSize: 15,
                      color: context.elixTextPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _JoinSharingRow(
            icon: FluentIcons.chart,
            title: 'Learning progress',
            description:
                'Sending this request does not share progress yet. After your '
                'Teacher approves you, they can view your classroom learning '
                'progress.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _JoinSharingRow(
            icon: FluentIcons.photo2,
            title: 'Saved movement images',
            description:
                'These use a separate privacy setting. After approval, your '
                'Teacher can view available saved movement images only while '
                'Save confirmed movement images is on.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label:
                'Access duration. Classroom access ends when you leave the class '
                'or your approved membership is removed.',
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(FluentIcons.lock, size: 14, color: colors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Classroom access ends when you leave the class or your '
                      'approved membership is removed.',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinSharingRow extends StatelessWidget {
  const _JoinSharingRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Semantics(
      label: '$title. $description',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 15, color: colors.brandSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$title. ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: description),
                  ],
                ),
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
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
        rows.add(const SizedBox(height: AppSpacing.sm));
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
          trailing: _AccessOutlineButton(
            key: Key('teacher_access_cancel_group_${membership.id}'),
            label: 'Cancel',
            onPressed: controller.busy
                ? null
                : () => controller.cancelPendingGroup(membership),
          ),
        ),
      );
    }
    return _WorkspaceCard(
      key: const Key('teacher_access_pending_card'),
      title: 'Waiting to join',
      subtitle: groups.isEmpty
          ? "Your teacher hasn't approved any requests yet."
          : '${groups.length} ${groups.length == 1 ? 'request' : 'requests'} awaiting approval',
      icon: FluentIcons.inbox,
      accent: AppColors.accent,
      child: rows.isEmpty ? const _WaitingEmptyState() : Column(children: rows),
    );
  }
}

class _WaitingEmptyState extends StatelessWidget {
  const _WaitingEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('teacher_access_pending_empty'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixColors.surfaceInteractive.withValues(
                alpha: context.isDarkTheme ? 0.45 : 0.7,
              ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.elixBorder.withValues(
            alpha: context.isHighContrast ? 1 : 0.55,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.completed,
            size: 22,
            color: context.elixColors.brandSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            'No join requests waiting.',
            textAlign: TextAlign.center,
            style: AppTheme.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "You're all caught up!",
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyClassesCard extends StatelessWidget {
  const _EmptyClassesCard();

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      variant: ElixPanelVariant.elevated,
      showAccentBar: true,
      accent: AppColors.primary,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(
                alpha: context.isDarkTheme ? 0.14 : 0.10,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              FluentIcons.education,
              size: 18,
              color: AppColors.primarySoft,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your classrooms',
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 16,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "You're not in a class yet.",
                  style: AppTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use Join a class above with the code from your teacher.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    height: 1.4,
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

class _YourClassroomsSection extends StatefulWidget {
  const _YourClassroomsSection({
    required this.controller,
    required this.compact,
    this.onOpenClass,
  });

  final TeacherAccessController controller;
  final bool compact;
  final ValueChanged<String>? onOpenClass;

  @override
  State<_YourClassroomsSection> createState() => _YourClassroomsSectionState();
}

class _YourClassroomsSectionState extends State<_YourClassroomsSection> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GroupMembership> get _visibleMemberships {
    final memberships = widget.controller.activeApprovedGroupMemberships;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return memberships;
    return [
      for (final membership in memberships)
        if (_matches(membership, query)) membership,
    ];
  }

  bool _matches(GroupMembership membership, String query) {
    final group = widget.controller.groupNamesById[membership.groupId];
    final haystack = [
      group?.name ?? 'Class',
      widget.controller.teacherDisplayNameFor(membership),
      group?.section,
      group?.schedule,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final memberships = widget.controller.activeApprovedGroupMemberships;
    final showSearch = memberships.length >= _classroomSearchThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClassesHeading(
          search: showSearch
              ? SizedBox(
                  width: widget.compact ? double.infinity : 240,
                  child: _ClassSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                )
              : null,
          compact: widget.compact,
        ),
        const SizedBox(height: AppSpacing.md),
        _ApprovedClassesGrid(
          controller: widget.controller,
          memberships: _visibleMemberships,
          query: _query,
          onOpenClass: widget.onOpenClass,
        ),
      ],
    );
  }
}

class _ClassesHeading extends StatelessWidget {
  const _ClassesHeading({this.search, required this.compact});

  final Widget? search;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final heading = ElixSectionHeader(
      heading: 'Your classrooms',
      subtitle: 'Select a class to view assignments and classmates.',
    );
    if (search == null) return heading;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: AppSpacing.sm),
          search!,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: heading),
        const SizedBox(width: AppSpacing.md),
        search!,
      ],
    );
  }
}

class _ApprovedClassesGrid extends StatelessWidget {
  const _ApprovedClassesGrid({
    required this.controller,
    required this.memberships,
    required this.query,
    this.onOpenClass,
  });

  final TeacherAccessController controller;
  final List<GroupMembership> memberships;
  final String query;
  final ValueChanged<String>? onOpenClass;

  @override
  Widget build(BuildContext context) {
    final openClass = onOpenClass;
    if (memberships.isEmpty) {
      return ElixStatusPanel(
        key: const Key('teacher_access_status_empty'),
        icon: FluentIcons.search,
        title: query.trim().isEmpty
            ? 'No active classrooms.'
            : 'No matching classes',
        message: query.trim().isEmpty
            ? 'No active classrooms.'
            : 'No classrooms match that search.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= _accessWideBreakpoint
            ? 3
            : width >= _accessCompactBreakpoint
            ? 2
            : 1;
        final gap = AppSpacing.md;
        final cardWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final membership in memberships)
              Builder(
                builder: (context) {
                  final teacherName = controller.teacherDisplayNameFor(
                    membership,
                  );
                  final assignments = controller.assignmentsFor(
                    membership.groupId,
                  );
                  return SizedBox(
                    width: cardWidth,
                    child: TraineeClassCard(
                      groupId: membership.groupId,
                      className:
                          controller.groupNamesById[membership.groupId]?.name ??
                          'Class',
                      teacherName: teacherName,
                      sectionLabel: () {
                        final group =
                            controller.groupNamesById[membership.groupId];
                        final classMetadata = [group?.section, group?.schedule]
                            .whereType<String>()
                            .where((value) => value.isNotEmpty)
                            .join(' · ');
                        return classMetadata.isEmpty ? 'Active' : classMetadata;
                      }(),
                      assignmentCount: assignments
                          .where((assignment) => assignment.isActive)
                          .length,
                      workItems: classCardWorkItemsFromAssignments(assignments),
                      ownerInitials: userInitials(teacherName),
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
                  );
                },
              ),
          ],
        );
      },
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
      padding: const EdgeInsets.all(12),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
  return formatElixrDateTime(value);
}

Future<void> _confirmLeaveClass(
  BuildContext context,
  TeacherAccessController controller,
  GroupMembership membership,
) async {
  final className =
      controller.groupNamesById[membership.groupId]?.name ?? 'this class';
  const message =
      'You will no longer see this class or its assignments. You can ask '
      'to join again later with a current class code.';
  final useShad =
      !context.isHighContrast && shad.ShadTheme.maybeOf(context) != null;
  final accepted = useShad
      ? await ElixDialog.show<bool>(
          context,
          title: 'Leave $className?',
          icon: FluentIcons.people,
          content: Text(
            message,
            style: AppTheme.body.copyWith(
              fontSize: 14,
              color: context.elixTextSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            Button(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Cancel'),
            ),
            ElixPrimaryButton(
              key: const Key('teacher_access_confirm_leave'),
              label: 'Leave class',
              expanded: false,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
            ),
          ],
          uniformActionSize: const Size(128, 56),
        )
      : await showDialog<bool>(
          context: context,
          builder: (context) => ContentDialog(
            title: Text('Leave $className?'),
            content: const Text(message),
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

class _ClassSearchField extends StatelessWidget {
  const _ClassSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Icon(
        FluentIcons.search,
        size: 14,
        color: context.elixTextSecondary,
      ),
    );
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return TextBox(
        key: const Key('teacher_access_class_search'),
        controller: controller,
        placeholder: 'Search classes',
        prefix: icon,
        onChanged: onChanged,
      );
    }
    return shad.ShadInput(
      key: const Key('teacher_access_class_search'),
      controller: controller,
      placeholder: const Text('Search classes'),
      leading: icon,
      onChanged: onChanged,
    );
  }
}

class _AccessOutlineButton extends StatelessWidget {
  const _AccessOutlineButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return Button(onPressed: onPressed, child: Text(label));
    }
    return shad.ShadButton.outline(
      onPressed: onPressed,
      enabled: onPressed != null,
      child: Text(label),
    );
  }
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
