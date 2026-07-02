import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().register(
            fullName: _fullNameController.text.trim(),
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
      title: 'Create Account',
      subtitle: 'Start your flair training journey',
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Register as Trainee', style: AppTheme.headingMedium),
            const SizedBox(height: AppSpacing.lg),
            AuthTextField(
              controller: _fullNameController,
              placeholder: 'Full name',
              icon: FluentIcons.contact_card,
            ),
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              controller: _emailController,
              placeholder: 'Email address',
              icon: FluentIcons.mail_solid,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              controller: _passwordController,
              placeholder: 'Password',
              icon: FluentIcons.lock_solid,
              obscureText: true,
            ),
            const SizedBox(height: AppSpacing.md),
            AuthTextField(
              controller: _confirmController,
              placeholder: 'Confirm password',
              icon: FluentIcons.shield_solid,
              obscureText: true,
              onSubmitted: (_) => _register(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AuthErrorBanner(message: _error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElixPrimaryButton(
              label: 'Create Account',
              isLoading: _isLoading,
              onPressed: _register,
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: GestureDetector(
                onTap: () => context.go('/login'),
                child: RichText(
                  text: TextSpan(
                    style: AppTheme.bodySecondary,
                    children: const [
                      TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Sign In',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
