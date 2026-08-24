import 'dart:async';

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
import 'auth_validators.dart';

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
  bool _emailTouched = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String _submittedEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    _cooldownTimer?.cancel();
    _auth?.endPasswordResetWatch();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    setState(() => _emailTouched = true);
    if (validateAuthEmail(email) != null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      _auth = auth;
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() {
          _emailSent = true;
          _submittedEmail = email;
        });
        _startCooldown();
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldownSeconds--);
      if (_cooldownSeconds <= 0) timer.cancel();
    });
  }

  void _editEmail() {
    _cooldownTimer?.cancel();
    setState(() {
      _emailSent = false;
      _emailTouched = false;
      _cooldownSeconds = 0;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resetConfirmed = context.select<AuthService, bool>(
      (auth) => auth.hasConfirmedPasswordResetLink,
    );

    return AuthScaffold(
      noScrollForm: true,
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
    final emailError = _emailTouched
        ? validateAuthEmail(_emailController.text)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTextField(
          controller: _emailController,
          placeholder: 'Email address',
          icon: FluentIcons.mail_solid,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_emailTouched) setState(() {});
          },
          onFocusChanged: (focused) {
            if (!focused) setState(() => _emailTouched = true);
          },
          status: emailError == null
              ? AuthFieldStatus.neutral
              : AuthFieldStatus.error,
          validationText: emailError,
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
        InfoBar(
          title: const Text('Check your email'),
          content: Text(
            'If an account exists for $_submittedEmail, a reset link is on its way.',
          ),
          severity: InfoBarSeverity.success,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '1. Open the secure link in the email.\n'
          '2. Choose your new password on Firebase’s page.\n'
          '3. Return here to sign in.\n\n'
          'Check your spam or junk folder if it does not arrive.',
          style: AppTheme.body.copyWith(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Button(
                key: const Key('forgot_edit_email'),
                onPressed: _isLoading ? null : _editEmail,
                child: const Text('Edit email'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Button(
                key: const Key('forgot_resend'),
                onPressed: _isLoading || _cooldownSeconds > 0 ? null : _submit,
                child: Text(
                  _cooldownSeconds > 0
                      ? 'Resend in ${_cooldownSeconds}s'
                      : 'Resend email',
                ),
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
