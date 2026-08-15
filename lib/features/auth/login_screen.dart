import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

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
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
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
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          AuthTextField(
            controller: _passwordController,
            label: 'Password',
            placeholder: 'Password',
            icon: FluentIcons.lock_solid,
            obscureText: true,
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
            onPressed: _login,
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: AuthFooterLink(
              prompt: "Don't have an account?",
              action: 'Create one',
              onTap: () => context.go('/register'),
            ),
          ),
        ],
      ),
    );
  }
}
