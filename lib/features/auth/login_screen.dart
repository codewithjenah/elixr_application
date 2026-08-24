import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';
import 'auth_validators.dart';
import 'google_auth_button.dart';
import 'package:elixr_core/repositories/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;
  bool _emailTouched = false;
  bool _passwordTouched = false;
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = context.read<AuthService>().takeAccountDeletedMessage();
      if (message != null) {
        ElixDialog.success(context, message);
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading || _isGoogleLoading) return;
    setState(() {
      _emailTouched = true;
      _passwordTouched = true;
    });
    if (!_isValid) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = switch (failure.kind) {
          AuthFailureKind.network =>
            'Network error. Check your connection and try again.',
          AuthFailureKind.rateLimited =>
            'Too many attempts. Wait a moment and try again.',
          AuthFailureKind.disabledAccount =>
            'This account has been disabled. Contact support for help.',
          AuthFailureKind.missingProfile => failure.message,
          _ => 'Email or password is incorrect.',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Email or password is incorrect.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleLogin() async {
    if (_isLoading || _isGoogleLoading) return;
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signInWithGoogle();
    } on GoogleSignInCancelledException {
      // Browser closure is an intentional no-op, not a failed login.
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailError = _emailTouched
        ? validateAuthEmail(_emailController.text)
        : null;
    final passwordError = _passwordTouched && _passwordController.text.isEmpty
        ? 'Password is required.'
        : null;
    return AuthScaffold(
      noScrollForm: true,
      title: 'Welcome back',
      subtitle: 'Sign in to continue your flair training',
      formTitle: 'Sign In',
      formSubtitle: 'Enter your account details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthTextField(
            controller: _emailController,
            label: 'Email address',
            placeholder: 'Email address',
            icon: FluentIcons.mail_solid,
            keyboardType: TextInputType.emailAddress,
            focusNode: _emailFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
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
          const SizedBox(height: AppSpacing.sm + 4),
          AuthTextField(
            controller: _passwordController,
            label: 'Password',
            placeholder: 'Password',
            icon: FluentIcons.lock_solid,
            obscureText: true,
            focusNode: _passwordFocus,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_passwordTouched) setState(() {});
            },
            onFocusChanged: (focused) {
              if (!focused) setState(() => _passwordTouched = true);
            },
            status: passwordError == null
                ? AuthFieldStatus.neutral
                : AuthFieldStatus.error,
            validationText: passwordError,
            onSubmitted: (_) => _login(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AuthFooterLink(
              prompt: '',
              action: 'Forgot password?',
              onTap: () => context.go('/forgot-password'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElixPrimaryButton(
            label: 'Sign In',
            isLoading: _isLoading,
            onPressed: _isGoogleLoading ? null : _login,
          ),
          const SizedBox(height: AppSpacing.sm),
          const AuthOrDivider(),
          const SizedBox(height: AppSpacing.sm),
          GoogleAuthButton(
            key: const Key('login_google_button'),
            label: 'Continue with Google',
            isLoading: _isGoogleLoading,
            onPressed: _isLoading ? null : _googleLogin,
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: AuthFooterLink(
              prompt: "Don't have an account?",
              action: 'Create one',
              onTap: () => context.go(AppRoutePaths.register),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: AuthFooterLink(
              prompt: 'Have a Teacher access code?',
              action: 'Register as a Teacher',
              onTap: () => context.go(AppRoutePaths.registerTeacher),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isValid =>
      validateAuthEmail(_emailController.text) == null &&
      _passwordController.text.isNotEmpty;
}
