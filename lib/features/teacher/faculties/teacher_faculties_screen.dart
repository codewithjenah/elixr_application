import 'package:elixr_core/models/chat_user.dart';
import 'package:elixr_core/repositories/faculty_directory_repository.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/auth_service.dart';
import 'teacher_faculties_controller.dart';

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
      return const ElixScaffoldPage(
        header: PageHeader(title: Text('Faculties')),
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          header: PageHeader(
            title: const Text('Faculties'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.add_friend),
                  label: const Text('Invite a faculty member'),
                  onPressed: controller.busy
                      ? null
                      : () => _inviteFaculty(context, controller),
                ),
              ],
            ),
          ),
          content: controller.loading
              ? const Center(child: ProgressRing())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.errorMessage != null) ...[
                      _StatusCard(
                        key: const Key('teacher_faculties_error'),
                        message: controller.errorMessage!,
                        isError: true,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _FacultyList(controller: controller),
                    if (controller.pendingCodes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _PendingCodes(controller: controller),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

Future<void> _inviteFaculty(
  BuildContext context,
  TeacherFacultiesController controller,
) async {
  final minted = await controller.inviteFaculty();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      if (minted == null) {
        return ContentDialog(
          title: const Text('Could not create access code'),
          content: Text(controller.errorMessage ?? 'Try again in a moment.'),
          actions: [
            Button(
              child: const Text('Close'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        );
      }
      final display = minted.displayCode;
      return ContentDialog(
        title: const Text('Faculty access code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this one-time code. It cannot be used again after a Teacher account is created.',
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(display, style: AppTheme.headingMedium),
          ],
        ),
        actions: [
          Button(
            child: const Text('Copy'),
            onPressed: () => Clipboard.setData(ClipboardData(text: display)),
          ),
          FilledButton(
            child: const Text('Done'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      );
    },
  );
}

class _FacultyList extends StatelessWidget {
  const _FacultyList({required this.controller});

  final TeacherFacultiesController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.errorMessage != null && controller.teachers.isEmpty) {
      return const SizedBox.shrink();
    }
    if (controller.teachers.isEmpty) {
      return const _StatusCard(
        key: Key('teacher_faculties_empty'),
        message: 'No other faculty members yet.',
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: controller.teachers.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final teacher = controller.teachers[index];
          return ListTile(
            key: Key('teacher_faculty_tile_${teacher.id}'),
            leading: _FacultyAvatar(user: teacher),
            title: Text(teacher.displayName),
            subtitle: Text(
              'Teacher',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PendingCodes extends StatelessWidget {
  const _PendingCodes({required this.controller});

  final TeacherFacultiesController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending access codes',
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: controller.pendingCodes.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final code = controller.pendingCodes[index];
              return ListTile(
                key: Key('pending_code_${code.normalizedCode}'),
                title: SelectableText(code.displayCode),
                subtitle: Text(
                  'Unused one-time Teacher access code',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Button(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: code.displayCode),
                      ),
                      child: const Text('Copy'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Button(
                      onPressed: controller.busy
                          ? null
                          : () => controller.revokePendingCode(code),
                      child: const Text('Revoke'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FacultyAvatar extends StatelessWidget {
  const _FacultyAvatar({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context) {
    final initials = userInitials(user.displayName);
    final avatar = user.avatarUrl;
    return ClipOval(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        color: AppColors.accent.withValues(alpha: 0.2),
        child: avatar != null
            ? Image.network(
                avatar,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(
                  initials,
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              )
            : Text(
                initials,
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({super.key, required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          style: AppTheme.body.copyWith(
            color: isError ? AppColors.error : context.elixTextSecondary,
          ),
        ),
      ),
    );
  }
}
