import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/teacher_theme.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import 'teacher_auth_controller.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final email = auth.currentUser?.email ?? '';

    return TeacherAuthScaffold(
      title: 'Verify your email',
      subtitle: email.isEmpty
          ? 'Confirm this Teacher account from the message we sent you.'
          : 'We sent a verification message to $email',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.errorMessage != null) ...[
            TeacherMessageBanner(message: auth.errorMessage!),
            const SizedBox(height: 16),
          ],
          if (auth.infoMessage != null) ...[
            TeacherMessageBanner(message: auth.infoMessage!, isError: false),
            const SizedBox(height: 16),
          ],
          FilledButton(
            key: const Key('verify_check_button'),
            onPressed: auth.isBusy ? null : auth.checkEmailVerification,
            child: auth.isBusy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("I've verified my email"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('verify_resend_button'),
            onPressed: auth.isBusy ? null : auth.resendVerificationEmail,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: TeacherColors.primarySoft,
              side: const BorderSide(color: TeacherColors.border),
            ),
            child: const Text('Resend verification email'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('verify_sign_out'),
            onPressed: auth.isBusy ? null : auth.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
