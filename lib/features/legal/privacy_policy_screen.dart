import 'package:elixr_core/legal/legal_documents.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Privacy Policy',
      subtitle: 'How ELIXR handles your personal data',
      formTitle: 'Privacy Policy',
      formSubtitle: 'Philippine Data Privacy Act (RA 10173)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (
            var i = 0;
            i < ElixrLegalDocuments.privacyPolicyParagraphs.length;
            i++
          ) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Text(
              ElixrLegalDocuments.privacyPolicyParagraphs[i],
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
