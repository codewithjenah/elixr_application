import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _paragraphs = <String>[
    'Data Collected: email, name, profile photo, webcam video processed '
        'locally on your device for pose/hand landmark detection, session '
        'performance data.',
    'Video Storage: raw camera video is never uploaded to or stored on '
        'our servers. It is processed locally on your device during practice '
        'sessions only.',
    'Profile photos are stored in Cloud Storage for display across the app.',
    'Data Retention: profile and training data are kept while your account '
        'is active. If you delete your account via Settings > Security, we '
        'permanently remove all associated data.',
    'Your Rights: Under the Philippine Data Privacy Act (RA 10173), you '
        'have the right to access, correct, or erase your personal data. '
        'Use Settings > Security > Delete Account to exercise your right to '
        'erasure.',
  ];

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
