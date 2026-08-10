import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
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
  bool _agreedToLegal = false;
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
    if (!_agreedToLegal) return;

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

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final verticalTight = viewportHeight < 720;
    final verticalCompact = viewportHeight < 840;
    final dense = verticalCompact;

    final fieldGap = verticalTight ? AppSpacing.xs : AppSpacing.sm;
    final actionGap = verticalTight ? AppSpacing.sm : AppSpacing.md;

    return AuthScaffold(
      formOnLeft: true,
      title: 'Create Account',
      subtitle: 'Start your flair training journey',
      formTitle: 'Register',
      formSubtitle: 'Set up your trainee profile',
      formVerticalCompact: verticalCompact,
      formVerticalTight: verticalTight,
      child: Column(
        key: const Key('register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _firstNameController,
            placeholder: 'First name',
            icon: FluentIcons.contact,
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          AuthTextField(
            controller: _middleNameController,
            placeholder: 'Middle name (optional)',
            icon: FluentIcons.contact,
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          AuthTextField(
            controller: _lastNameController,
            placeholder: 'Last name',
            icon: FluentIcons.contact,
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          AuthTextField(
            controller: _emailController,
            placeholder: 'Email address',
            icon: FluentIcons.mail_solid,
            keyboardType: TextInputType.emailAddress,
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          AuthTextField(
            controller: _passwordController,
            placeholder: 'Password',
            icon: FluentIcons.lock_solid,
            obscureText: true,
            helperText: 'At least 6 characters',
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          AuthTextField(
            controller: _confirmController,
            placeholder: 'Confirm password',
            icon: FluentIcons.shield_solid,
            obscureText: true,
            onSubmitted: (_) {
              if (_agreedToLegal) _register();
            },
            dense: dense,
          ),
          SizedBox(height: fieldGap),
          _RegisterLegalConsent(
            agreed: _agreedToLegal,
            onChanged: (value) => setState(() => _agreedToLegal = value),
          ),
          if (_error != null) ...[
            SizedBox(height: actionGap),
            AuthErrorBanner(message: _error!),
          ],
          SizedBox(height: actionGap),
          ElixPrimaryButton(
            label: 'Create Account',
            isLoading: _isLoading,
            onPressed: _agreedToLegal ? _register : null,
            dense: dense,
          ),
          SizedBox(height: verticalTight ? AppSpacing.xs : AppSpacing.sm),
          Center(
            child: AuthFooterLink(
              prompt: 'Already have an account?',
              action: 'Sign in',
              onTap: () => context.go('/login'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterLegalConsent extends StatelessWidget {
  const _RegisterLegalConsent({
    required this.agreed,
    required this.onChanged,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final linkStyle = AppTheme.caption.copyWith(
      color: AppColors.primary,
      height: 1.35,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    );
    final plainStyle = AppTheme.caption.copyWith(
      color: context.elixTextSecondary,
      height: 1.35,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: const Key('register_privacy_consent'),
          checked: agreed,
          onChanged: (value) => onChanged(value == true),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => onChanged(!agreed),
                child: Text('I agree to the ', style: plainStyle),
              ),
              GestureDetector(
                onTap: () => context.push('/privacy-policy'),
                child: Text('Privacy Policy', style: linkStyle),
              ),
              Text(' and ', style: plainStyle),
              GestureDetector(
                onTap: () => context.push('/terms-of-service'),
                child: Text('Terms of Service', style: linkStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
