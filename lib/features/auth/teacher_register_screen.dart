import 'package:elixr_core/models/coach_code.dart';
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
import 'auth_validators.dart';

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
  final _accessCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _agreedToLegal = false;
  bool _isLoading = false;
  String? _error;
  int _step = 0;
  final Set<String> _touched = <String>{};

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _accessCodeController.dispose();
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
    return false;
  }

  void _continue() {
    if (_step == 0) {
      setState(() => _touched.addAll(['first', 'last']));
      if (!_validatePersonalDetails()) return;
    } else {
      setState(() => _touched.addAll(['email', 'code']));
      if (validateAuthEmail(_emailController.text) != null ||
          CoachCode.tryNormalize(_accessCodeController.text) == null) {
        return;
      }
    }
    setState(() {
      _step++;
      _error = null;
    });
  }

  Future<void> _register() async {
    setState(() => _touched.addAll(['password', 'confirm', 'legal']));
    if (!_agreedToLegal) {
      setState(() => _error = TeacherAuthMessages.legalConsentRequired);
      return;
    }
    if (!_validatePersonalDetails()) return;

    final accessCode = CoachCode.tryNormalize(_accessCodeController.text);
    if (accessCode == null) {
      setState(() => _error = TeacherAuthMessages.accessCodeInvalid);
      return;
    }

    if (validateAuthEmail(_emailController.text) != null ||
        validateRegistrationPassword(_passwordController.text) != null ||
        validatePasswordConfirmation(
              _passwordController.text,
              _confirmController.text,
            ) !=
            null) {
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
        teacherAccessCode: accessCode,
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
      noScrollForm: true,
      formOnLeft: true,
      title: 'Teach with ELIXR',
      subtitle:
          'Teacher accounts require an access code from an administrator or an existing Teacher.',
      formTitle: switch (_step) {
        0 => 'Create your profile',
        1 => 'Teacher access',
        _ => 'Secure your account',
      },
      formSubtitle: switch (_step) {
        0 => 'Students will see this name in classroom contexts.',
        1 => 'Enter your work email and Teacher access code.',
        _ => 'Choose a strong password and accept the legal terms.',
      },
      child: Column(
        key: const Key('teacher_register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TeacherProgress(step: _step),
          const SizedBox(height: AppSpacing.md),
          if (_step == 0) ...[
            AuthTextField(
              controller: _firstNameController,
              label: 'First name',
              placeholder: 'First name',
              icon: FluentIcons.contact,
              validationText: _nameError('first'),
              status: _status('first', _nameError('first')),
              onChanged: (_) => _live('first'),
              onFocusChanged: (v) => _blur('first', v),
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _middleNameController,
              label: 'Middle name (optional)',
              placeholder: 'Middle name (optional)',
              icon: FluentIcons.contact,
              onChanged: (_) => _live('middle'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _lastNameController,
              label: 'Last name',
              placeholder: 'Last name',
              icon: FluentIcons.contact,
              validationText: _nameError('last'),
              status: _status('last', _nameError('last')),
              onChanged: (_) => _live('last'),
              onFocusChanged: (v) => _blur('last', v),
            ),
          ] else if (_step == 1) ...[
            AuthTextField(
              controller: _emailController,
              label: 'Work email',
              placeholder: 'Work email',
              icon: FluentIcons.mail_solid,
              keyboardType: TextInputType.emailAddress,
              validationText: _touched.contains('email')
                  ? validateAuthEmail(_emailController.text)
                  : null,
              status: _status(
                'email',
                validateAuthEmail(_emailController.text),
              ),
              onChanged: (_) => _live('email'),
              onFocusChanged: (v) => _blur('email', v),
            ),
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _accessCodeController,
              label: 'Teacher access code',
              placeholder: '7KPM-XR4D-Q2WT',
              icon: FluentIcons.permissions,
              helperText:
                  'Required. Ask an administrator or an existing Teacher for a code.',
              validationText:
                  _touched.contains('code') &&
                      CoachCode.tryNormalize(_accessCodeController.text) == null
                  ? TeacherAuthMessages.accessCodeInvalid
                  : null,
              status: _status(
                'code',
                CoachCode.tryNormalize(_accessCodeController.text) == null
                    ? TeacherAuthMessages.accessCodeInvalid
                    : null,
              ),
              onChanged: (_) => _live('code'),
              onFocusChanged: (v) => _blur('code', v),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            AuthTextField(
              controller: _passwordController,
              label: 'Password',
              placeholder: 'Password',
              icon: FluentIcons.lock_solid,
              obscureText: true,
              helperText: '8+ characters, including a letter and a number',
              validationText: _touched.contains('password')
                  ? validateRegistrationPassword(_passwordController.text)
                  : null,
              status: _status(
                'password',
                validateRegistrationPassword(_passwordController.text),
              ),
              onChanged: (_) {
                _live('password');
                if (_touched.contains('confirm')) setState(() {});
              },
              onFocusChanged: (v) => _blur('password', v),
            ),
            AuthPasswordChecklist(password: _passwordController.text),
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
              validationText: _confirmationMessage,
              status: _confirmationStatus,
              onChanged: (_) => _live('confirm'),
              onFocusChanged: (v) => _blur('confirm', v),
            ),
            const SizedBox(height: AppSpacing.sm),
            _TeacherRegisterLegalConsent(
              agreed: _agreedToLegal,
              onChanged: (value) => setState(() => _agreedToLegal = value),
            ),
          ],
          if ((_step < 2 && !_currentStepValid) ||
              (_step == 2 && !_securityValid)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              switch (_step) {
                0 => 'Enter your first and last name to continue.',
                1 => 'Enter a valid work email and Teacher access code.',
                _ =>
                  'Complete the password, match, and legal consent requirements.',
              },
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_step < 2)
            Row(
              children: [
                if (_step > 0) ...[
                  Button(
                    onPressed: () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: ElixPrimaryButton(
                    label: 'Continue',
                    onPressed: _currentStepValid ? _continue : null,
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Button(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                          _step = 1;
                          _error = null;
                        }),
                  child: const Text('Back'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElixPrimaryButton(
                    label: 'Create Teacher account',
                    isLoading: _isLoading,
                    onPressed: _securityValid ? _register : null,
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

  void _blur(String field, bool focused) {
    if (!focused) setState(() => _touched.add(field));
  }

  void _live(String field) {
    setState(() {});
  }

  String? _nameError(String field) {
    if (!_touched.contains(field)) return null;
    final value = field == 'first'
        ? _firstNameController.text.trim()
        : _lastNameController.text.trim();
    return value.isEmpty
        ? '${field == 'first' ? 'First' : 'Last'} name is required.'
        : null;
  }

  AuthFieldStatus _status(String field, String? error) {
    if (!_touched.contains(field)) return AuthFieldStatus.neutral;
    return error == null ? AuthFieldStatus.success : AuthFieldStatus.error;
  }

  bool get _profileValid =>
      validateUserNameParts(
        firstName: _firstNameController.text,
        middleName: _middleNameController.text,
        lastName: _lastNameController.text,
      ) ==
      null;

  bool get _teacherAccessValid =>
      validateAuthEmail(_emailController.text) == null &&
      CoachCode.tryNormalize(_accessCodeController.text) != null;

  bool get _securityValid =>
      validateRegistrationPassword(_passwordController.text) == null &&
      validatePasswordConfirmation(
            _passwordController.text,
            _confirmController.text,
          ) ==
          null &&
      _agreedToLegal;

  bool get _currentStepValid =>
      _step == 0 ? _profileValid : _teacherAccessValid;

  String? get _confirmationMessage {
    if (_confirmController.text.isEmpty && !_touched.contains('confirm')) {
      return null;
    }
    return validatePasswordConfirmation(
          _passwordController.text,
          _confirmController.text,
        ) ??
        'Passwords match.';
  }

  AuthFieldStatus get _confirmationStatus {
    if (_confirmController.text.isEmpty && !_touched.contains('confirm')) {
      return AuthFieldStatus.neutral;
    }
    return validatePasswordConfirmation(
              _passwordController.text,
              _confirmController.text,
            ) ==
            null
        ? AuthFieldStatus.success
        : AuthFieldStatus.error;
  }
}

class _TeacherProgress extends StatelessWidget {
  const _TeacherProgress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Profile', 'Teacher access', 'Security'];
    return Semantics(
      label: 'Step ${step + 1} of 3: ${labels[step]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${step + 1} of 3',
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: index == 2 ? 0 : AppSpacing.xs,
                  ),
                  height: 4,
                  decoration: BoxDecoration(
                    color: index <= step
                        ? AppColors.primary
                        : context.elixBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
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
