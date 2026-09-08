import 'package:elixr_core/models/chat_user.dart';
import 'package:elixr_core/models/teacher_access_code.dart';
import 'package:elixr_core/repositories/faculty_directory_repository.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/elix_toast.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../services/auth_service.dart';
import '../../profile/profile_route_args.dart';
import 'teacher_faculties_controller.dart';

const double _facultiesMaxContentWidth = 1180;
const double _facultiesSplitBreakpoint = 960;

class TeacherFacultiesScreen extends StatefulWidget {
  const TeacherFacultiesScreen({super.key});

  @override
  State<TeacherFacultiesScreen> createState() => _TeacherFacultiesScreenState();
}

class _TeacherFacultiesScreenState extends State<TeacherFacultiesScreen> {
  TeacherFacultiesController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id;
    if (user == null || userId == null) return;
    _controller = TeacherFacultiesController(
      directory: context.read<FacultyDirectoryRepository>(),
      accessCodes: context.read<TeacherAccessCodeRepository>(),
      teacherId: userId,
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: _pageHeader,
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: _pageHeader,
          content: controller.loading
              ? const Center(
                  child: ElixStatusPanel(
                    isLoading: true,
                    message: 'Loading Teacher Access…',
                  ),
                )
              : _FacultiesWorkspace(controller: controller),
        );
      },
    );
  }

  static const _pageHeader = ElixEditorialPageHeader(
    heading: 'Teacher Access',
    eyebrow: 'TEACHER WORKSPACE',
    subtitle: 'Invite and manage other Teachers who need access.',
  );
}

class _FacultiesWorkspace extends StatelessWidget {
  const _FacultiesWorkspace({required this.controller});

  final TeacherFacultiesController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _facultiesMaxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.errorMessage != null) ...[
              ElixStatusPanel(
                key: const Key('teacher_faculties_error'),
                message: controller.errorMessage!,
                isError: true,
                actionLabel:
                    controller.errorMessage == 'Could not load faculties.'
                    ? 'Retry'
                    : null,
                onAction: controller.errorMessage == 'Could not load faculties.'
                    ? () {
                        controller.start();
                      }
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _AccessOverview(controller: controller),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final split = constraints.maxWidth >= _facultiesSplitBreakpoint;
                final teachers = _FacultyList(controller: controller);
                final pending = _PendingCodes(controller: controller);
                if (!split) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      teachers,
                      const SizedBox(height: AppSpacing.lg),
                      pending,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: teachers),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 9, child: pending),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessOverview extends StatelessWidget {
  const _AccessOverview({required this.controller});

  final TeacherFacultiesController controller;

  @override
  Widget build(BuildContext context) {
    final teacherCount = controller.teachers.length;
    final pendingCount = controller.pendingCodes.length;
    return ElixPanelCard(
      accent: context.elixColors.brandPrimary,
      showAccentBar: true,
      variant: ElixPanelVariant.elevated,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Faculty workspace',
                style: AppTheme.cardTitle(color: context.elixTextPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Share a one-time code to grant Teacher access. Codes cannot be reused after an account is created.',
                style: AppTheme.supporting(color: context.elixTextSecondary),
              ),
            ],
          );
          final metrics = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _AccessMetricChip(
                key: const Key('teacher_faculties_teacher_count'),
                icon: FluentIcons.people,
                value: '$teacherCount',
                label: teacherCount == 1
                    ? 'Teacher with access'
                    : 'Teachers with access',
                tone: context.elixColors.brandSecondary,
              ),
              _AccessMetricChip(
                key: const Key('teacher_faculties_pending_count'),
                icon: FluentIcons.permissions,
                value: '$pendingCount',
                label: pendingCount == 1 ? 'Pending invite' : 'Pending invites',
                tone: pendingCount > 0
                    ? context.elixColors.warning
                    : context.elixColors.brandPrimary,
              ),
            ],
          );
          final invite = ElixPrimaryButton(
            label: 'Invite another Teacher',
            icon: FluentIcons.add_friend,
            expanded: compact,
            dense: true,
            isLoading: controller.busy,
            onPressed: controller.busy
                ? null
                : () => _inviteFaculty(context, controller),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: AppSpacing.md),
                metrics,
                const SizedBox(height: AppSpacing.md),
                invite,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: AppSpacing.md),
                    metrics,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              invite,
            ],
          );
        },
      ),
    );
  }
}

class _AccessMetricChip extends StatelessWidget {
  const _AccessMetricChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Container(
      constraints: const BoxConstraints(minWidth: 168),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : tone.withValues(alpha: 0.28),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: AppTheme.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _FacultyList extends StatelessWidget {
  const _FacultyList({required this.controller});

  final TeacherFacultiesController controller;

  bool get _directoryFailed =>
      controller.errorMessage == 'Could not load faculties.' &&
      controller.teachers.isEmpty;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ElixSectionHeader(
            heading: 'Teachers',
            subtitle: 'People who already have Teacher access.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (_directoryFailed)
            Text(
              'This list could not be loaded.',
              style: AppTheme.supporting(color: context.elixTextSecondary),
            )
          else if (controller.teachers.isEmpty)
            const _PanelPlaceholder(
              key: Key('teacher_faculties_empty'),
              icon: FluentIcons.add_friend,
              title: 'No other Teachers yet',
              message: 'No other Teachers have access yet.',
            )
          else
            Column(
              children: [
                for (
                  var index = 0;
                  index < controller.teachers.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.sm),
                  _FacultyRow(teacher: controller.teachers[index]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _FacultyRow extends StatelessWidget {
  const _FacultyRow({required this.teacher});

  final ChatUser teacher;

  @override
  Widget build(BuildContext context) {
    return ElixHoverSurface(
      key: Key('teacher_faculty_tile_${teacher.id}'),
      borderRadius: 16,
      semanticLabel: '${teacher.displayName}, Teacher',
      onTap: () => context.push(
        AppRoutePaths.teacherProfile(teacher.id),
        extra: ProfileRouteArgs(
          displayName: teacher.displayName,
          profilePictureUrl: teacher.avatarUrl,
          role: teacher.role,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ProfileAvatarWidget(
              radius: 22,
              showBorder: false,
              networkImageUrl: teacher.avatarUrl,
              initials: userInitials(teacher.displayName),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacher.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body.copyWith(
                      color: context.elixTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Teacher',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElixPill(
              text: 'Faculty',
              color: context.elixColors.brandSecondary,
              compact: true,
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              FluentIcons.chevron_right,
              size: 12,
              color: context.elixTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCodes extends StatelessWidget {
  const _PendingCodes({required this.controller});

  final TeacherFacultiesController controller;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      accent: context.elixColors.brandPrimary,
      showAccentBar: controller.pendingCodes.isNotEmpty,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ElixSectionHeader(
            heading: 'Pending access codes',
            subtitle: 'One-time invites waiting to be used.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (controller.codesErrorMessage != null)
            _PanelPlaceholder(
              key: const Key('teacher_faculties_pending_error'),
              icon: FluentIcons.status_circle_error_x,
              title: 'Pending codes unavailable',
              message: controller.codesErrorMessage!,
              isError: true,
            )
          else if (controller.pendingCodes.isEmpty)
            const _PanelPlaceholder(
              key: Key('teacher_faculties_pending_empty'),
              icon: FluentIcons.permissions,
              title: 'No pending invites',
              message:
                  'Unused one-time codes will appear here after you invite another Teacher.',
            )
          else
            Column(
              children: [
                for (
                  var index = 0;
                  index < controller.pendingCodes.length;
                  index++
                )
                  Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : AppSpacing.md,
                    ),
                    child: _PendingCodeRow(
                      code: controller.pendingCodes[index],
                      busy: controller.busy,
                      onRevoke: () => _revokeCode(
                        context,
                        controller,
                        controller.pendingCodes[index],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final tone = isError
        ? context.elixColors.error
        : context.elixColors.brandPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 22),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: AppTheme.supporting(
              color: isError
                  ? context.elixColors.error
                  : context.elixTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCodeRow extends StatelessWidget {
  const _PendingCodeRow({
    required this.code,
    required this.busy,
    required this.onRevoke,
  });

  final TeacherAccessCode code;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final createdAt = code.createdAt;
    return Container(
      key: Key('pending_code_${code.normalizedCode}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixColors.surfaceInteractive,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : context.elixColors.brandPrimary.withValues(alpha: 0.22),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccessCodeTicket(displayCode: code.displayCode),
          const SizedBox(height: AppSpacing.sm),
          Text(
            createdAt == null
                ? 'Unused one-time Teacher access code'
                : 'Unused one-time Teacher access code · ${formatElixrDate(createdAt)}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Button(
                onPressed: () => _copyAccessCode(context, code.displayCode),
                child: const Text('Copy'),
              ),
              Button(
                onPressed: busy ? null : onRevoke,
                child: const Text('Revoke'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessCodeTicket extends StatelessWidget {
  const _AccessCodeTicket({required this.displayCode});

  final String displayCode;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final tone = context.elixColors.brandPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : tone.withValues(alpha: 0.28),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: SelectableText(
        displayCode,
        style: AppTheme.headingMedium.copyWith(
          color: context.elixTextPrimary,
          fontFamily: ElixTypography.wordmarkFamily,
          fontFamilyFallback: ElixTypography.wordmarkFallbacks,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _copyAccessCode(BuildContext context, String display) async {
  await Clipboard.setData(ClipboardData(text: display));
  if (!context.mounted) return;
  ElixToast.showSuccess(context, message: 'Access code copied.');
}

Future<void> _revokeCode(
  BuildContext context,
  TeacherFacultiesController controller,
  TeacherAccessCode code,
) async {
  await controller.revokePendingCode(code);
  if (!context.mounted) return;
  if (controller.errorMessage == null) {
    ElixToast.showSuccess(context, message: 'Access code revoked.');
  }
}

Future<void> _inviteFaculty(
  BuildContext context,
  TeacherFacultiesController controller,
) async {
  final minted = await controller.inviteFaculty();
  if (!context.mounted) return;

  if (minted == null) {
    await ElixDialog.show<void>(
      context,
      title: 'Could not create access code',
      icon: FluentIcons.status_circle_error_x,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      content: Text(
        controller.errorMessage ?? 'Try again in a moment.',
        style: AppTheme.body.copyWith(color: context.elixTextSecondary),
      ),
      actions: [
        Button(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
    return;
  }

  final display = minted.displayCode;
  await ElixDialog.show<void>(
    context,
    title: 'Teacher access code',
    subtitle: 'Share this one-time invite',
    icon: FluentIcons.permissions,
    maxWidth: 460,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Share this one-time code. It cannot be used again after a Teacher account is created.',
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        _AccessCodeTicket(displayCode: display),
      ],
    ),
    actions: [
      Button(
        child: const Text('Copy'),
        onPressed: () => _copyAccessCode(context, display),
      ),
      ElixPrimaryButton(
        label: 'Done',
        expanded: false,
        dense: true,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}
