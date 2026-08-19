import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';

class TeacherRegisterScreen extends StatefulWidget {
  const TeacherRegisterScreen({super.key});

  @override
  State<TeacherRegisterScreen> createState() => _TeacherRegisterScreenState();
}

class _TeacherRegisterScreenState extends State<TeacherRegisterScreen> {
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _agreedToLegal = false;
  bool _isLoading = false;
  String? _error;
  int _step = 0;

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

  bool _validatePersonalDetails() {
    final nameError = validateUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    if (nameError == null) return true;
    setState(() => _error = nameError);
    return false;
  }

  void _continueToAccount() {
    if (!_validatePersonalDetails()) return;
    setState(() {
      _step = 1;
      _error = null;
    });
  }

  Future<void> _register() async {
    if (!_agreedToLegal) {
      setState(() => _error = TeacherAuthMessages.legalConsentRequired);
      return;
    }
    if (!_validatePersonalDetails()) return;

    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = TeacherAuthMessages.passwordMismatch);
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _error = TeacherAuthMessages.passwordTooShort);
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
      await context.read<AuthService>().registerTeacher(
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) context.go(AppRoutePaths.verifyEmail);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      formOnLeft: true,
      title: 'Teach with ELIXR',
      subtitle: 'Create a dedicated Teacher account',
      formTitle: _step == 0 ? 'Your name' : 'Work email & password',
      formSubtitle: _step == 0
          ? 'Students will see this name in classroom contexts.'
          : 'We will send a verification email before you can access the Teacher shell.',
      child: Column(
        key: const Key('teacher_register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == 0) ...[
            AuthTextField(
              controller: _firstNameController,
              label: 'First name',
              placeholder: 'First name',
              icon: FluentIcons.contact,
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _middleNameController,
              label: 'Middle name (optional)',
              placeholder: 'Middle name (optional)',
              icon: FluentIcons.contact,
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _lastNameController,
              label: 'Last name',
              placeholder: 'Last name',
              icon: FluentIcons.contact,
            ),
          ] else ...[
            AuthTextField(
              controller: _emailController,
              label: 'Work email',
              placeholder: 'Work email',
              icon: FluentIcons.mail_solid,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _passwordController,
              label: 'Password',
              placeholder: 'Password',
              icon: FluentIcons.lock_solid,
              obscureText: true,
              helperText: 'At least 6 characters',
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _confirmController,
              label: 'Confirm password',
              placeholder: 'Confirm password',
              icon: FluentIcons.shield_solid,
              obscureText: true,
              onSubmitted: (_) {
                if (_agreedToLegal) _register();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _TeacherRegisterLegalConsent(
              agreed: _agreedToLegal,
              onChanged: (value) => setState(() => _agreedToLegal = value),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0)
            ElixPrimaryButton(label: 'Continue', onPressed: _continueToAccount)
          else ...[
            Row(
              children: [
                Button(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                          _step = 0;
                          _error = null;
                        }),
                  child: const Text('Back'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElixPrimaryButton(
                    label: 'Create Teacher account',
                    isLoading: _isLoading,
                    onPressed: _agreedToLegal ? _register : null,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: AuthFooterLink(
              prompt: 'Already have an account?',
              action: 'Sign in',
              onTap: () => context.go(AppRoutePaths.login),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: AuthFooterLink(
              prompt: 'Training as a student?',
              action: 'Create Trainee account',
              onTap: () => context.go(AppRoutePaths.register),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherRegisterLegalConsent extends StatelessWidget {
  const _TeacherRegisterLegalConsent({
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
          key: const Key('teacher_register_privacy_consent'),
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
                onTap: () => context.push(AppRoutePaths.privacyPolicy),
                child: Text('Privacy Policy', style: linkStyle),
              ),
              Text(' and ', style: plainStyle),
              GestureDetector(
                onTap: () => context.push(AppRoutePaths.termsOfService),
                child: Text('Terms of Service', style: linkStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
