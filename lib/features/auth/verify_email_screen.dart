import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';
import 'auth_validators.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _isBusy = false;
  AuthService? _auth;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    if (!identical(_auth, auth)) {
      _auth?.endEmailVerificationWatch();
      _auth?.removeListener(_handleAuthChanged);
      _auth = auth;
      auth.addListener(_handleAuthChanged);
      auth.beginEmailVerificationWatch();
    }
  }

  void _handleAuthChanged() {
    final auth = _auth;
    if (!mounted || auth == null || _navigated) return;
    if (auth.isAuthenticated &&
        !auth.needsEmailVerification &&
        !auth.hasPendingEmailChange) {
      _navigated = true;
      final destination = auth.currentUser?.isTeacher == true
          ? AppRoutePaths.teacherDashboard
          : AppRoutePaths.dashboard;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(destination);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = _auth;
    if (auth != null && state == AppLifecycleState.resumed) {
      unawaited(auth.refreshEmailVerificationOnForeground());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.endEmailVerificationWatch();
    _auth?.removeListener(_handleAuthChanged);
    super.dispose();
  }

  Future<void> _checkVerification() async {
    setState(() => _isBusy = true);
    context.read<AuthService>().clearTeacherAuthMessages();
    try {
      final auth = context.read<AuthService>();
      final verified = await auth.checkEmailVerification();
      if (verified && mounted) {
        final destination = auth.currentUser?.isTeacher == true
            ? AppRoutePaths.teacherDashboard
            : AppRoutePaths.dashboard;
        context.go(destination);
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isBusy = true);
    try {
      await context.read<AuthService>().resendVerificationEmail();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _changeEmail({bool resendPending = false}) async {
    final emailController = TextEditingController(
      text: resendPending ? (_auth?.pendingEmail ?? '') : '',
    );
    final passwordController = TextEditingController();
    String? dialogError;
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => ContentDialog(
          title: Text(
            resendPending ? 'Resend corrected-email link' : 'Change email',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!resendPending)
                  AuthTextField(
                    key: const Key('verify_change_email_field'),
                    controller: emailController,
                    label: 'Correct email address',
                    placeholder: 'name@example.com',
                    icon: FluentIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !loading,
                  ),
                if (!resendPending) const SizedBox(height: AppSpacing.sm),
                AuthTextField(
                  key: const Key('verify_change_password_field'),
                  controller: passwordController,
                  label: 'Current password',
                  placeholder: 'Current password',
                  icon: FluentIcons.lock,
                  obscureText: true,
                  enabled: !loading,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AuthErrorBanner(message: dialogError!),
                ],
              ],
            ),
          ),
          actions: [
            Button(
              onPressed: loading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('verify_change_submit'),
              onPressed: loading
                  ? null
                  : () async {
                      final emailError = resendPending
                          ? null
                          : validateAuthEmail(emailController.text);
                      if (emailError != null ||
                          passwordController.text.isEmpty) {
                        setDialogState(() {
                          dialogError =
                              emailError ?? 'Current password is required.';
                        });
                        return;
                      }
                      setDialogState(() => loading = true);
                      try {
                        final auth = context.read<AuthService>();
                        final sent = resendPending
                            ? await auth.resendPendingEmailChange(
                                currentPassword: passwordController.text,
                              )
                            : await auth.requestEmailChange(
                                newEmail: emailController.text.trim(),
                                currentPassword: passwordController.text,
                              );
                        if (!sent) {
                          throw Exception('No email change was requested.');
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        setDialogState(() {
                          loading = false;
                          dialogError = error.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: Text(resendPending ? 'Resend link' : 'Send verification'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _signOut() async {
    await context.read<AuthService>().logout();
    if (mounted) context.go(AppRoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final email = auth.currentUser?.email ?? '';
    final destinationEmail = auth.pendingEmail ?? email;
    final resendSeconds = auth.verificationResendSecondsRemaining;
    final pending = auth.hasPendingEmailChange;

    return AuthScaffold(
      noScrollForm: true,
      title: 'Verify your email',
      subtitle: email.isEmpty
          ? 'Confirm this account from the message we sent you.'
          : 'We sent a verification message to $email',
      formTitle: 'Email verification',
      formSubtitle: 'Verify your email before accessing ELIXR.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.teacherAuthErrorMessage != null) ...[
            AuthErrorBanner(message: auth.teacherAuthErrorMessage!),
            const SizedBox(height: AppSpacing.md),
          ],
          if (auth.teacherAuthInfoMessage != null) ...[
            InfoBar(
              title: Text(auth.teacherAuthInfoMessage!),
              severity: InfoBarSeverity.success,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _VerificationStatus(
            checking: _isBusy || auth.isCheckingPendingEmailChange,
            pendingEmailChange: pending,
            email: destinationEmail,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '1. Open the verification email sent to $destinationEmail.\n'
            '2. Select the verification link.\n'
            '3. Return here; ELIXR checks automatically.\n\n'
            'Check spam or junk if the message does not arrive.',
          ),
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            key: const Key('verify_check_button'),
            label: 'Check verification',
            isLoading: _isBusy,
            onPressed: _checkVerification,
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            key: const Key('verify_resend_button'),
            onPressed: _isBusy || !auth.canResendVerification
                ? null
                : pending
                ? () => _changeEmail(resendPending: true)
                : _resend,
            child: Text(
              resendSeconds > 0
                  ? 'Resend available in ${resendSeconds}s'
                  : 'Resend verification email',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            key: const Key('verify_change_email'),
            onPressed: _isBusy || pending ? null : _changeEmail,
            child: const Text('Change email address'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            key: const Key('verify_sign_out'),
            onPressed: _isBusy ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _VerificationStatus extends StatelessWidget {
  const _VerificationStatus({
    required this.checking,
    required this.pendingEmailChange,
    required this.email,
  });
  final bool checking;
  final bool pendingEmailChange;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: checking
              ? const SizedBox(width: 18, height: 18, child: ProgressRing())
              : const Icon(FluentIcons.mail, size: 18),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            checking
                ? 'Checking verification status…'
                : pendingEmailChange
                ? 'Waiting for $email to be verified. Your account and profile stay unchanged until it completes.'
                : 'Waiting for verification. Automatic detection is active.',
          ),
        ),
      ],
    );
  }
}
