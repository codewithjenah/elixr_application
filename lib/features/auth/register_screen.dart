import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/utils/user_name.dart';
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
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final nameError = validateUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }

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

    final normalized = normalizeUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );

    try {
      await context.read<AuthService>().register(
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
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

  Widget _pairFields(AuthTextField left, AuthTextField right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: right),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      formOnLeft: true,
      title: 'Create Account',
      subtitle: 'Start your flair training journey',
      formTitle: 'Register',
      formSubtitle: 'Set up your trainee profile',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final paired = constraints.maxWidth >= 300;
          final gap = paired ? AppSpacing.sm : AppSpacing.sm + 4;
          final dense = paired;

          final firstNameField = AuthTextField(
            controller: _firstNameController,
            placeholder: 'First name',
            icon: FluentIcons.contact,
            dense: dense,
          );
          final lastNameField = AuthTextField(
            controller: _lastNameController,
            placeholder: 'Last name',
            icon: FluentIcons.contact,
            dense: dense,
          );
          final middleNameField = AuthTextField(
            controller: _middleNameController,
            placeholder: 'Middle name (optional)',
            icon: FluentIcons.contact,
            dense: dense,
          );
          final emailField = AuthTextField(
            controller: _emailController,
            placeholder: 'Email address',
            icon: FluentIcons.mail_solid,
            keyboardType: TextInputType.emailAddress,
            dense: dense,
          );
          final passwordField = AuthTextField(
            controller: _passwordController,
            placeholder: 'Password',
            icon: FluentIcons.lock_solid,
            obscureText: true,
            helperText: 'At least 6 characters',
            dense: dense,
          );
          final confirmField = AuthTextField(
            controller: _confirmController,
            placeholder: 'Confirm password',
            icon: FluentIcons.shield_solid,
            obscureText: true,
            onSubmitted: (_) => _register(),
            dense: dense,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (paired)
                _pairFields(firstNameField, lastNameField)
              else ...[
                firstNameField,
                SizedBox(height: gap),
                lastNameField,
              ],
              SizedBox(height: gap),
              if (paired)
                _pairFields(middleNameField, emailField)
              else ...[
                middleNameField,
                SizedBox(height: gap),
                emailField,
              ],
              SizedBox(height: gap),
              if (paired)
                _pairFields(passwordField, confirmField)
              else ...[
                passwordField,
                SizedBox(height: gap),
                confirmField,
              ],
              if (_error != null) ...[
                SizedBox(height: paired ? AppSpacing.sm : AppSpacing.md),
                AuthErrorBanner(message: _error!),
              ],
              SizedBox(height: paired ? AppSpacing.md : AppSpacing.lg),
              ElixPrimaryButton(
                label: 'Create Account',
                isLoading: _isLoading,
                onPressed: _register,
                dense: dense,
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: AuthFooterLink(
                  prompt: 'Already have an account?',
                  action: 'Sign in',
                  onTap: () => context.go('/login'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
