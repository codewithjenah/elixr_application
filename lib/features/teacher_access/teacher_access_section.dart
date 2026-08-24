import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import '../../services/join_code_resolver.dart';
import '../../data/repositories/session_evidence_repository.dart';
import '../settings/widgets/settings_components.dart';
import 'teacher_access_controller.dart';

/// Dedicated Teacher Access destination hosted in Settings.
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
      return const SettingsStatusBanner(
        message: 'Sign in to manage Teacher Access.',
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const Center(child: ProgressRing());
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Join a group with a class invite code, or use a legacy Teacher '
                'roster code. The Teacher must approve your request. Progress and '
                'saved movement images remain private until you enable each '
                'permission separately on a linked Teacher.',
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (controller.errorMessage != null) ...[
                SettingsStatusBanner(message: controller.errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],
              _JoinTeacherCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _PendingGroupRequestsCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _PendingRequestsCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _GroupMembershipsCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _LinkedTeachersCard(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _JoinTeacherCard extends StatefulWidget {
  const _JoinTeacherCard({required this.controller});

  final TeacherAccessController controller;

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
    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Join a group',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controller.joinStep == JoinTeacherStep.enterCode) ...[
            Text(
              'Enter a group invite code or a legacy Teacher roster code.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(height: AppSpacing.md),
            TextBox(
              key: const Key('teacher_access_roster_code'),
              placeholder: 'XXXX-XXXX-XXXX',
              controller: _textController,
              onChanged: controller.setCodeInput,
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
            ElixPrimaryButton(
              key: const Key('teacher_access_resolve_code'),
              label: 'Continue',
              expanded: false,
              isLoading: controller.busy,
              onPressed: controller.busy ? null : controller.resolveCode,
            ),
          ] else ...[
            Text(
              controller.resolvedKind == JoinCodeKind.groupInvite
                  ? controller.resolvedGroupInvite?.teacherDisplayName ??
                        'Teacher'
                  : controller.resolvedTeacherInvite?.teacherDisplayName ??
                        'Teacher',
              key: const Key('teacher_access_confirm_teacher'),
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              controller.resolvedKind == JoinCodeKind.groupInvite
                  ? 'Send a group join request? Classroom membership does not share '
                        'progress or saved images.'
                  : 'Send a legacy Teacher roster request? Nothing is shared until '
                        'the Teacher approves, and progress and images remain off by default.',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
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
        ],
      ),
    );
  }
}

class _PendingGroupRequestsCard extends StatelessWidget {
  const _PendingGroupRequestsCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending Group Requests',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controller.pendingGroupMemberships.isEmpty)
            Text(
              'No pending group requests.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else
            for (final membership in controller.pendingGroupMemberships) ...[
              _GroupMembershipRow(
                membership: membership,
                groupName:
                    controller.groupNamesById[membership.groupId]?.name ??
                    'Group',
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
    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group Memberships',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controller.approvedGroupMemberships.isEmpty)
            Text(
              'No approved group memberships yet.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else
            for (final membership in controller.approvedGroupMemberships) ...[
              _GroupMembershipRow(
                membership: membership,
                groupName:
                    controller.groupNamesById[membership.groupId]?.name ??
                    'Group',
                subtitleOverride: 'Classroom membership approved',
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
    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending Join Requests',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controller.pending.isEmpty)
            Text(
              'No pending requests.',
              key: const Key('teacher_access_pending_empty'),
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else
            for (final link in controller.pending) ...[
              _RequestRow(
                link: link,
                subtitleOverride: 'Waiting for Teacher approval',
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
    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Linked Teachers',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (controller.approved.isEmpty)
            Text(
              'No linked Teachers yet.',
              key: const Key('teacher_access_linked_empty'),
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else
            for (final link in controller.approved) ...[
              _RequestRow(
                link: link,
                subtitleOverride:
                    'Relationship: Linked\nProgress sharing: '
                    '${link.hasEffectiveProgressAccess ? 'On' : 'Off'}\n'
                    'Saved movement images: '
                    '${link.hasEffectiveEvidenceAccess ? 'On' : 'Off'}',
                trailing: Wrap(
                  spacing: AppSpacing.sm,
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
              if (link != controller.approved.last)
                const SizedBox(height: AppSpacing.md),
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

class _GroupMembershipRow extends StatelessWidget {
  const _GroupMembershipRow({
    required this.membership,
    required this.groupName,
    this.trailing,
    this.subtitleOverride,
  });

  final GroupMembership membership;
  final String groupName;
  final Widget? trailing;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          groupName,
          style: AppTheme.body.copyWith(color: context.elixTextPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          subtitleOverride ??
              '${membership.teacherDisplayName} · ${_formatTime(membership.createdAt)}',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        if (trailing != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerLeft, child: trailing),
        ],
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.link,
    required this.trailing,
    this.subtitleOverride,
  });

  final TeacherStudentLink link;
  final Widget trailing;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          link.teacherDisplayName,
          style: AppTheme.body.copyWith(color: context.elixTextPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          subtitleOverride ?? 'Requested ${_formatTime(link.createdAt)}',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(alignment: Alignment.centerLeft, child: trailing),
      ],
    );
  }
}

String _formatTime(DateTime? value) {
  if (value == null) return 'recently';
  return DateFormat.yMMMd().add_jm().format(value.toLocal());
}
