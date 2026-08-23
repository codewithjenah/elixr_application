import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _isBusy = false;
  AuthService? _auth;

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
      _auth = auth;
      auth.beginEmailVerificationWatch();
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

  Future<void> _signOut() async {
    await context.read<AuthService>().logout();
    if (mounted) context.go(AppRoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final email = auth.currentUser?.email ?? '';

    return AuthScaffold(
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
          const _WaitingForEmailLink(
            message: TeacherAuthMessages.emailVerificationWaiting,
          ),
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            key: const Key('verify_check_button'),
            label: "I've verified my email",
            isLoading: _isBusy,
            onPressed: _checkVerification,
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            key: const Key('verify_resend_button'),
            onPressed: _isBusy ? null : _resend,
            child: const Text('Resend verification email'),
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

class _WaitingForEmailLink extends StatelessWidget {
  const _WaitingForEmailLink({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: SizedBox(width: 18, height: 18, child: ProgressRing()),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message)),
      ],
    );
  }
}
