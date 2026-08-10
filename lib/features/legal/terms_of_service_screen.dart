import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_scaffold.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const _paragraphs = <String>[
    'By using ELIXR, you agree to follow these terms. ELIXR is provided '
        'as-is for educational and training purposes.',
    'Your account is for your personal use only. Do not share credentials '
        'or abuse the service.',
    'Leaderboard scores reflect reported performance; we reserve the '
        'right to reset records if fraud is detected.',
    'ELIXR is not liable for interrupted service, data loss (beyond our '
        'control), or third-party systems.',
    'We reserve the right to update these terms. Changes will be posted '
        'here.',
  ];

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Terms of Service',
      subtitle: 'Rules for using ELIXR',
      formTitle: 'Terms of Service',
      formSubtitle: 'Please read before creating an account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Text(
              _paragraphs[i],
              style: AppTheme.body.copyWith(
                color: context.elixTextSecondary,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: AuthFooterLink(
              prompt: 'Done reading?',
              action: 'Go back',
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/register');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
