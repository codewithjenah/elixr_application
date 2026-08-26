import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import '../../data/repositories/session_evidence_repository.dart';
import 'teacher_access_controller.dart';

const double _accessWideBreakpoint = 1080;
const double _accessCompactBreakpoint = 760;

/// Reusable Teacher Access body hosted by the trainee shell destination.
class TeacherAccessSection extends StatefulWidget {
  const TeacherAccessSection({
    super.key,
    this.repository,
    this.controller,
    this.isActive = false,
  });

  final TeacherRelationshipRepository? repository;
  final TeacherAccessController? controller;
  final bool isActive;

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
    final repository =
        widget.repository ?? context.read<TeacherRelationshipRepository>();
    final groupRepository = context.read<GroupRepository>();
    final joinCodeResolver = context.read<JoinCodeResolver>();
    _owned = TeacherAccessController(
      relationshipRepository: repository,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: userId,
      traineeDisplayName: user!.fullName,
      privateImageSavingEnabled: user.sessionEvidenceEnabled == true,
      reconcileEvidenceAvailability: (traineeId) => SessionEvidenceRepository()
          .reconcilePublicEvidenceAvailability(traineeId),
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
            final wide = width >= _accessWideBreakpoint;
            final compact = width < _accessCompactBreakpoint;

            return SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AccessIntro(),
                  const SizedBox(height: AppSpacing.lg),
                  _AccessMetricsRow(controller: controller, compact: compact),
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
                  _AccessPair(
                    wide: wide,
                    left: _PendingGroupRequestsCard(controller: controller),
                    right: _PendingRequestsCard(controller: controller),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _AccessPair(
                    wide: wide,
                    left: _GroupMembershipsCard(controller: controller),
                    right: _LinkedTeachersCard(controller: controller),
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

class _AccessIntro extends StatelessWidget {
  const _AccessIntro();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Text(
        'Join a group with a class invite code, or use a legacy Teacher '
        'roster code. The Teacher must approve your request. Approved '
        'classroom memberships automatically share sanitized progress and '
        'available saved movement images while they remain approved. '
        'Legacy-only linked Teachers keep the explicit sharing controls.',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
    );
  }
}

class _AccessMetricsRow extends StatelessWidget {
  const _AccessMetricsRow({required this.controller, required this.compact});

  final TeacherAccessController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _MetricTile(
        label: 'Pending groups',
        value: '${controller.pendingGroupMemberships.length}',
        icon: FluentIcons.people,
      ),
      _MetricTile(
        label: 'Pending joins',
        value: '${controller.pending.length}',
        icon: FluentIcons.inbox,
      ),
      _MetricTile(
        label: 'Approved classrooms',
        value: '${controller.approvedGroupMemberships.length}',
        icon: FluentIcons.completed,
      ),
      _MetricTile(
        label: 'Legacy links',
        value: '${controller.legacyOnlyApproved.length}',
        icon: FluentIcons.contact,
      ),
    ];

    Widget row(Widget a, Widget b) {
      return Row(
        children: [
          Expanded(child: a),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: b),
        ],
      );
    }

    if (compact) {
      return Column(
        children: [
          row(tiles[0], tiles[1]),
          const SizedBox(height: AppSpacing.md),
          row(tiles[2], tiles[3]),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.headingLarge.copyWith(
                    color: context.elixTextPrimary,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _AccessPair extends StatelessWidget {
  const _AccessPair({
    required this.wide,
    required this.left,
    required this.right,
  });

  final bool wide;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        children: [
          left,
          const SizedBox(height: AppSpacing.lg),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: right),
      ],
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
                      'Join a group',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 18,
                        color: context.elixTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.joinStep == JoinTeacherStep.enterCode
                          ? 'Enter a group invite code or a legacy Teacher roster code.'
                          : controller.resolvedKind == JoinCodeKind.groupInvite
                          ? 'Send a group join request? Once approved, sanitized progress '
                                'and available saved images are shared automatically while '
                                'membership remains approved.'
                          : 'Send a legacy Teacher roster request? Nothing is shared until '
                                'the Teacher approves, and progress and images remain off by default.',
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
          controller.resolvedKind == JoinCodeKind.groupInvite
              ? controller.resolvedGroupInvite?.teacherDisplayName ?? 'Teacher'
              : controller.resolvedTeacherInvite?.teacherDisplayName ??
                    'Teacher',
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

class _PendingGroupRequestsCard extends StatelessWidget {
  const _PendingGroupRequestsCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return _AccessSectionPanel(
      title: 'Pending Group Requests',
      icon: FluentIcons.people,
      count: controller.pendingGroupMemberships.length,
      child: controller.pendingGroupMemberships.isEmpty
          ? const _EmptyHint(message: 'No pending group requests.')
          : Column(
              children: [
                for (final membership
                    in controller.pendingGroupMemberships) ...[
                  _AccessListRow(
                    title:
                        controller.groupNamesById[membership.groupId]?.name ??
                        'Group',
                    subtitle:
                        '${membership.teacherDisplayName} · ${_formatTime(membership.createdAt)}',
                    trailing: Button(
                      onPressed: controller.busy
                          ? null
                          : () => controller.cancelPendingGroup(membership),
                      child: const Text('Cancel'),
                    ),
                  ),
                  if (membership != controller.pendingGroupMemberships.last)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _GroupMembershipsCard extends StatelessWidget {
  const _GroupMembershipsCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return _AccessSectionPanel(
      title: 'Approved Classroom Memberships',
      icon: FluentIcons.completed,
      count: controller.approvedGroupMemberships.length,
      child: controller.approvedGroupMemberships.isEmpty
          ? const _EmptyHint(message: 'No approved group memberships yet.')
          : Column(
              children: [
                for (final membership
                    in controller.approvedGroupMemberships) ...[
                  _AccessListRow(
                    title:
                        controller.groupNamesById[membership.groupId]?.name ??
                        'Group',
                    subtitle:
                        'Approved · Progress and available saved movement images '
                        'are shared automatically while membership remains approved.',
                  ),
                  if (membership != controller.approvedGroupMemberships.last)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _PendingRequestsCard extends StatelessWidget {
  const _PendingRequestsCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return _AccessSectionPanel(
      title: 'Pending Join Requests',
      icon: FluentIcons.inbox,
      count: controller.pending.length,
      child: controller.pending.isEmpty
          ? const _EmptyHint(
              key: Key('teacher_access_pending_empty'),
              message: 'No pending requests.',
            )
          : Column(
              children: [
                for (final link in controller.pending) ...[
                  _AccessListRow(
                    title: link.teacherDisplayName,
                    subtitle: 'Waiting for Teacher approval',
                    trailing: Button(
                      key: Key('teacher_access_cancel_${link.id}'),
                      onPressed: controller.busy
                          ? null
                          : () => controller.cancelPending(link),
                      child: const Text('Cancel'),
                    ),
                  ),
                  if (link != controller.pending.last)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _LinkedTeachersCard extends StatelessWidget {
  const _LinkedTeachersCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    final linked = controller.legacyOnlyApproved;
    return _AccessSectionPanel(
      title: 'Legacy-only Linked Teachers',
      icon: FluentIcons.contact,
      count: linked.length,
      child: linked.isEmpty
          ? const _EmptyHint(
              key: Key('teacher_access_linked_empty'),
              message: 'No linked Teachers yet.',
            )
          : Column(
              children: [
                for (final link in linked) ...[
                  _AccessListRow(
                    title: link.teacherDisplayName,
                    subtitle:
                        'Relationship: Linked\nProgress sharing: '
                        '${link.hasEffectiveProgressAccess ? 'On' : 'Off'}\n'
                        'Saved movement images: '
                        '${link.hasEffectiveEvidenceAccess ? 'On' : 'Off'}',
                    trailing: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.end,
                      children: [
                        if (link.hasEffectiveProgressAccess)
                          Button(
                            key: Key('teacher_access_stop_sharing_${link.id}'),
                            onPressed: controller.busy
                                ? null
                                : () => _confirmStopSharing(
                                    context,
                                    controller,
                                    link,
                                  ),
                            child: const Text('Stop sharing'),
                          )
                        else
                          Button(
                            key: Key('teacher_access_share_${link.id}'),
                            onPressed: controller.busy
                                ? null
                                : () => _confirmShareProgress(
                                    context,
                                    controller,
                                    link,
                                  ),
                            child: const Text('Share progress'),
                          ),
                        if (link.hasEffectiveProgressAccess &&
                            controller.privateImageSavingEnabled)
                          Button(
                            key: Key('teacher_access_evidence_${link.id}'),
                            onPressed: controller.busy
                                ? null
                                : link.hasEffectiveEvidenceAccess
                                ? () => controller.stopSharingEvidence(link)
                                : () => _confirmShareEvidence(
                                    context,
                                    controller,
                                    link,
                                  ),
                            child: Text(
                              link.hasEffectiveEvidenceAccess
                                  ? 'Stop sharing images'
                                  : 'Share saved images',
                            ),
                          ),
                        Button(
                          key: Key('teacher_access_revoke_${link.id}'),
                          onPressed: controller.busy
                              ? null
                              : () => _confirmRevokeTeacher(
                                  context,
                                  controller,
                                  link,
                                ),
                          child: const Text('Revoke Teacher'),
                        ),
                      ],
                    ),
                  ),
                  if (link != linked.last)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
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

Future<void> _confirmShareProgress(
  BuildContext context,
  TeacherAccessController controller,
  TeacherStudentLink link,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Share progress with this Teacher?'),
      content: const Text(
        'This shares total practice time, completed movement names, and sanitized '
        'practice/assessment history: movement, difficulty, date and duration, '
        'prop type, legacy score or V2 rubric scores, and performance level.\n\n'
        'It does not share passwords or credentials, private settings, raw webcam '
        'or video, feedback internals, achievements, visitor records, permission '
        'to edit sessions or scores, or unrestricted account data.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Share progress'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.shareProgress(link);
}

Future<void> _confirmStopSharing(
  BuildContext context,
  TeacherAccessController controller,
  TeacherStudentLink link,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Stop sharing progress?'),
      content: const Text(
        'This Teacher will immediately lose access to your sanitized progress. '
        'Your Teacher relationship will remain linked, messaging remains available, '
        'and you can share progress again later.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Stop sharing'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.stopSharingProgress(link);
}

Future<void> _confirmShareEvidence(
  BuildContext context,
  TeacherAccessController controller,
  TeacherStudentLink link,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Share saved movement images?'),
      content: const Text(
        'Retained historical and future annotated still images will become '
        'readable by this Teacher until you revoke this permission. Progress '
        'sharing must remain on. No video or arbitrary Storage path is shared.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Share saved images'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.shareEvidence(link);
}

Future<void> _confirmRevokeTeacher(
  BuildContext context,
  TeacherAccessController controller,
  TeacherStudentLink link,
) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Revoke this Teacher?'),
      content: const Text(
        'This ends the Teacher relationship and removes any progress consent. '
        'Direct messages remain available separately unless either user blocks the other. '
        'If you approve a future request from this Teacher, progress sharing will be off by default.',
      ),
      actions: [
        Button(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context, false),
        ),
        FilledButton(
          child: const Text('Revoke Teacher'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (accepted == true) await controller.revokeTeacher(link);
}

String _formatTime(DateTime? value) {
  if (value == null) return 'recently';
  return DateFormat.yMMMd().add_jm().format(value.toLocal());
}
