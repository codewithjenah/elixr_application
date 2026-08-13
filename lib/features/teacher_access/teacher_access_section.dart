import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
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
    _owned = TeacherAccessController(
      repository: repository,
      traineeId: userId,
      traineeDisplayName: user!.fullName,
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
        if (controller.loading && controller.invite == null) {
          return const Center(child: ProgressRing());
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share a coach code so a Teacher can request to link with you. '
                'Approving a request does not share your practice sessions or '
                'scores in this version.',
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
              _CoachCodeCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _PendingRequestsCard(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _LinkedTeachersCard(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _CoachCodeCard extends StatelessWidget {
  const _CoachCodeCard({required this.controller});

  final TeacherAccessController controller;

  @override
  Widget build(BuildContext context) {
    final invite = controller.invite;
    final expired = invite?.isExpired ?? false;

    return SettingsGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach Code',
            style: AppTheme.headingMedium.copyWith(
              fontSize: 16,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (invite == null) ...[
            Text(
              'No active coach code. Generate one to let a Teacher find you.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ElixPrimaryButton(
              key: const Key('teacher_access_generate'),
              label: 'Generate coach code',
              expanded: false,
              isLoading: controller.busy,
              onPressed: controller.busy ? null : controller.generateOrRotate,
            ),
          ] else ...[
            SelectableText(
              invite.displayCode,
              key: const Key('teacher_access_code'),
              style: AppTheme.headingMedium.copyWith(
                letterSpacing: 1.4,
                color: expired ? AppColors.warning : context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              expired
                  ? 'Expired ${_formatTime(invite.expiresAt)}. Generate a replacement.'
                  : 'Expires ${_formatTime(invite.expiresAt)}.',
              style: AppTheme.caption.copyWith(
                color: expired ? AppColors.warning : context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                Button(
                  key: const Key('teacher_access_copy'),
                  onPressed: () => _copy(context, invite),
                  child: const Text('Copy'),
                ),
                if (expired)
                  ElixPrimaryButton(
                    key: const Key('teacher_access_generate'),
                    label: 'Generate replacement',
                    expanded: false,
                    isLoading: controller.busy,
                    onPressed: controller.busy
                        ? null
                        : controller.generateOrRotate,
                  )
                else ...[
                  Button(
                    key: const Key('teacher_access_rotate'),
                    onPressed: controller.busy
                        ? null
                        : controller.generateOrRotate,
                    child: const Text('Rotate'),
                  ),
                  Button(
                    key: const Key('teacher_access_revoke_code'),
                    onPressed: controller.busy ? null : controller.revokeInvite,
                    child: const Text('Revoke'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, TeacherInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.displayCode));
    if (!context.mounted) return;
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Coach code copied'),
        severity: InfoBarSeverity.success,
        onClose: close,
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
            'Pending Teacher Requests',
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
                trailing: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    ElixPrimaryButton(
                      key: Key('teacher_access_approve_${link.id}'),
                      label: 'Approve',
                      expanded: false,
                      dense: true,
                      onPressed: controller.busy
                          ? null
                          : () => controller.approve(link),
                    ),
                    Button(
                      key: Key('teacher_access_reject_${link.id}'),
                      onPressed: controller.busy
                          ? null
                          : () => controller.reject(link),
                      child: const Text('Reject'),
                    ),
                  ],
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
                subtitleOverride: 'Approved',
                trailing: Button(
                  key: Key('teacher_access_revoke_${link.id}'),
                  onPressed: controller.busy
                      ? null
                      : () => controller.revokeTeacher(link),
                  child: const Text('Revoke'),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                link.teacherDisplayName,
                style: AppTheme.body.copyWith(color: context.elixTextPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                subtitleOverride ?? 'Requested ${_formatTime(link.createdAt)}',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

String _formatTime(DateTime? value) {
  if (value == null) return 'recently';
  return DateFormat.yMMMd().add_jm().format(value.toLocal());
}
