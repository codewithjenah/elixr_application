import 'package:fluent_ui/fluent_ui.dart';
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
