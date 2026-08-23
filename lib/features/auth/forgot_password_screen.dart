import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _error;
  AuthService? _auth;

  @override
  void dispose() {
    _emailController.dispose();
    _auth?.endPasswordResetWatch();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Email cannot be empty.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      _auth = auth;
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _emailSent = true);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resetConfirmed = context.select<AuthService, bool>(
      (auth) => auth.hasConfirmedPasswordResetLink,
    );

    return AuthScaffold(
      title: 'Reset password',
      subtitle: 'We will email you a secure link to choose a new password',
      formTitle: 'Forgot password',
      formSubtitle: resetConfirmed
          ? 'You can sign in now'
          : _emailSent
          ? 'Check your inbox to continue'
          : 'Enter the email for your account',
      child: resetConfirmed
          ? _buildConfirmedContent()
          : _emailSent
          ? _buildSuccessContent()
          : _buildFormContent(),
    );
  }

  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTextField(
          controller: _emailController,
          placeholder: 'Email address',
          icon: FluentIcons.mail_solid,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        ElixPrimaryButton(
          label: 'Send reset link',
          isLoading: _isLoading,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: AuthFooterLink(
            prompt: 'Remember your password?',
            action: 'Sign in',
            onTap: () => context.go('/login'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(width: 18, height: 18, child: ProgressRing()),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                TeacherAuthMessages.passwordResetWaiting,
                style: AppTheme.body.copyWith(fontSize: 15, height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: AuthFooterLink(
            prompt: 'Ready to continue?',
            action: 'Sign in',
            onTap: () => context.go('/login'),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TeacherAuthMessages.passwordResetCompleted,
          style: AppTheme.body.copyWith(fontSize: 15, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        ElixPrimaryButton(
          label: 'Sign in',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
