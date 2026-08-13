import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/teacher_routes.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import 'teacher_auth_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await context.read<TeacherAuthController>().sendPasswordResetEmail(
      email: _emailController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final sent = auth.infoMessage == TeacherAuthMessages.resetEmailSent;

    return TeacherAuthScaffold(
      title: 'Forgot password',
      subtitle: sent
          ? 'If that email is registered, a reset link is on the way'
          : 'Enter the email for your Teacher account',
      showBack: true,
      child: sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TeacherMessageBanner(
                  message: TeacherAuthMessages.resetEmailSent,
                  isError: false,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go(TeacherRoutes.login),
                  child: const Text('Back to Sign In'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!auth.isBusy) _submit();
                  },
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                if (auth.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  TeacherMessageBanner(message: auth.errorMessage!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('forgot_password_submit'),
                  onPressed: auth.isBusy ? null : _submit,
                  child: auth.isBusy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset link'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go(TeacherRoutes.login),
                  child: const Text('Back to Sign In'),
                ),
              ],
            ),
    );
  }
}
