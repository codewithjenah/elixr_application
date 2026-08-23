import 'package:elixr_core/models/teacher_access_code.dart';
import 'package:elixr_core/repositories/teacher_access_code_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/shell/teacher_shell.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';

class TeacherSettingsScreen extends StatelessWidget {
  const TeacherSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

    return ElixScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: user == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsSection(
                  title: 'Account',
                  children: [
                    _ReadOnlyField(label: 'Name', value: user.fullName),
                    const SizedBox(height: AppSpacing.sm),
                    _ReadOnlyField(label: 'Email', value: user.email),
                    const SizedBox(height: AppSpacing.sm),
                    _ReadOnlyField(label: 'Role', value: user.role),
                  ],
                ),
                if (user.isTeacher) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SettingsSection(
                    title: 'Co-teachers',
                    children: [
                      const Text(
                        'Create a one-time access code and share it with a colleague. '
                        'They enter it when registering a Teacher account.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Button(
                        onPressed: () => _inviteCoTeacher(context),
                        child: const Text('Invite a co-teacher'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _SettingsSection(
                  title: 'Legal',
                  children: [
                    Button(
                      onPressed: () =>
                          context.push(AppRoutePaths.privacyPolicy),
                      child: const Text('Privacy Policy'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Button(
                      onPressed: () =>
                          context.push(AppRoutePaths.termsOfService),
                      child: const Text('Terms of Service'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                ElixPrimaryButton(
                  label: 'Log out',
                  onPressed: () async {
                    await auth.logout();
                    if (context.mounted) context.go(AppRoutePaths.login);
                  },
                ),
              ],
            ),
    );
  }
}

Future<void> _inviteCoTeacher(BuildContext context) async {
  final user = context.read<AuthService>().currentUser;
  if (user == null || !user.isTeacher || user.id == null) return;

  TeacherAccessCode? minted;
  Object? error;
  try {
    minted = await context.read<TeacherAccessCodeRepository>().mint(
      createdBy: user.id!,
    );
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      if (error != null || minted == null) {
        return ContentDialog(
          title: const Text('Could not create access code'),
          content: Text(
            error?.toString().replaceFirst('Exception: ', '') ??
                'Try again in a moment.',
          ),
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
        title: const Text('Co-teacher access code'),
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.body.copyWith(color: context.elixTextPrimary),
        ),
      ],
    );
  }
}
