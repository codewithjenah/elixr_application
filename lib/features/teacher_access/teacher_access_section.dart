import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_stat_card.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import 'teacher_access_controller.dart';
import 'trainee_class_card.dart';

const double _accessWideBreakpoint = 1080;
const double _accessCompactBreakpoint = 760;

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
                  _JoinTeacherCard(controller: controller, compact: compact),
                  const SizedBox(height: AppSpacing.lg),
                  _PendingJoinsCard(controller: controller),
                  const SizedBox(height: AppSpacing.lg),
                  if (controller.approvedGroupMemberships.isEmpty) ...[
                    const _EmptyClassesCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ] else ...[
                    _ClassesHeading(
                      count: controller.approvedGroupMemberships.length,
                    ),
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
    return ElixPanelCard(
      showAccentBar: true,
      accent: AppColors.primary,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  FluentIcons.add_friend,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join a class',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 18,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.joinStep == JoinTeacherStep.enterCode
                          ? 'Type the class code your teacher gave you.'
                          : 'Send a join request? Your teacher needs to accept '
                                'you before you can see this class.',
                      style: AppTheme.bodySecondary.copyWith(
                        color: context.elixTextSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (controller.joinStep == JoinTeacherStep.enterCode)
            _JoinCodeEntry(
              controller: controller,
              textController: _textController,
              compact: widget.compact,
            )
          else
            _JoinConfirmActions(controller: controller),
        ],
      ),
    );
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
    return _AccessSectionPanel(
      title: 'Waiting to join',
      icon: FluentIcons.inbox,
      count: controller.pendingJoinCount,
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
      count: 0,
      child: _EmptyHint(
        message: 'You are not in a class yet. Join with a class code above.',
      ),
    );
  }
}

class _ClassesHeading extends StatelessWidget {
  const _ClassesHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ElixSectionHeader(
      heading: 'Your classes',
      actions: [ElixPill(text: '$count', color: AppColors.accent)],
    );
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
                  onOpen: () => openClass?.call(membership.groupId),
                  menuItems: openClass == null
                      ? null
                      : (_) => [
                          MenuFlyoutItem(
                            text: const Text('Open class'),
                            onPressed: () => openClass(membership.groupId),
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
    this.count,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final int? count;

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
                if (count != null)
                  ElixPill(text: '$count', color: AppColors.accent),
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

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
