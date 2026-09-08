import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/teacher_auth_messages.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_form_chrome.dart';
import 'auth_text_field.dart';
import 'auth_validators.dart';
import 'google_auth_button.dart';

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
  bool _isGoogleLoading = false;
  bool _isCheckingAccess = false;
  String? _prevalidatedAccessCode;
  String? _error;
  int _step = 0;
  bool _stepForward = true;
  final Set<String> _touched = <String>{};

  static const _stepLabels = [
    'Teacher access',
    'Method',
    'Profile',
    'Security',
  ];

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

  void _goToStep(int step) {
    setState(() {
      _stepForward = step > _step;
      _step = step;
      _error = null;
    });
  }

  Future<void> _continueFromAccess() async {
    if (_isCheckingAccess) return;
    setState(() => _touched.add('code'));
    final accessCode = CoachCode.tryNormalize(_accessCodeController.text);
    if (accessCode == null) return;

    setState(() {
      _isCheckingAccess = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().prevalidateTeacherAccessCode(
        accessCode,
      );
      if (!mounted) return;
      setState(() {
        _prevalidatedAccessCode = accessCode;
        _stepForward = true;
        _step = 1;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingAccess = false);
    }
  }

  void _chooseEmailAndPassword() {
    _goToStep(2);
  }

  void _continueToSecurity() {
    setState(() => _touched.addAll(['first', 'last']));
    if (!_validatePersonalDetails()) return;
    _goToStep(3);
  }

  Future<void> _register() async {
    if (_isLoading || _isGoogleLoading) return;
    setState(() => _touched.addAll(['email', 'password', 'confirm', 'legal']));
    if (!_agreedToLegal) {
      setState(() => _error = TeacherAuthMessages.legalConsentRequired);
      return;
    }
    if (!_validatePersonalDetails()) return;

    final accessCode = _usablePrevalidatedAccessCode;
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
        legalConsent: RegistrationLegalConsent.current(),
      );
      if (mounted) context.go(AppRoutePaths.verifyEmail);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    if (_isLoading || _isGoogleLoading) return;
    final accessCode = _usablePrevalidatedAccessCode;
    if (accessCode == null) {
      setState(() {
        _touched.add('code');
        _error = TeacherAuthMessages.accessCodeInvalid;
        _stepForward = false;
        _step = 0;
      });
      return;
    }
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signInWithGoogleTeacher(
        teacherAccessCode: accessCode,
      );
      if (mounted && context.read<AuthService>().hasPendingGoogleProfile) {
        context.go(AppRoutePaths.completeGoogleProfile);
      }
    } on GoogleSignInCancelledException {
      // Keep the code and the rest of the form available for another try.
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
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final dense = viewportHeight < 840;

    return AuthScaffold(
      noScrollForm: viewportHeight >= 680,
      compactBrandHero: true,
      title: 'Teach with ELIXR',
      subtitle:
          'Create a Teacher account with an access code from an administrator or an existing Teacher.',
      formTitle: switch (_step) {
        0 => 'Teacher access',
        1 => 'Choose how to register',
        2 => 'Create your profile',
        _ => 'Secure your account',
      },
      formSubtitle: switch (_step) {
        0 => 'Enter your Teacher access code to continue.',
        1 => 'Use Google, or create an account with email and password.',
        2 => 'Students will see this name in classroom contexts.',
        _ => 'Choose an email, set a password, and accept the legal terms.',
      },
      child: Column(
        key: const Key('teacher_register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthFlowStepper(step: _step, compact: dense, labels: _stepLabels),
          const SizedBox(height: AppSpacing.md),
          AuthStepSwitcher(
            step: _step,
            forward: _stepForward,
            child: _stepBody(dense: dense),
          ),
          if ((_step == 0 && !_teacherCodeValid) ||
              (_step == 2 && !_profileValid) ||
              (_step == 3 && !_securityValid)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              switch (_step) {
                0 => 'Enter a valid Teacher access code to continue.',
                2 => 'Enter your first and last name to continue.',
                _ =>
                  'Complete the email, password, match, and legal consent requirements.',
              },
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          AuthErrorSlot(message: _error),
          const SizedBox(height: AppSpacing.lg),
          ..._stepActions(dense: dense),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: AuthFooterLink(
              prompt: 'Already have an account?',
              action: 'Sign in',
              onTap: () => context.go(AppRoutePaths.login),
            ),
          ),
          Center(
            child: AuthFooterLink(
              prompt: 'Training as a student?',
              action: 'Create Trainee account',
              muted: true,
              dense: true,
              onTap: () => context.go(AppRoutePaths.register),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody({required bool dense}) {
    return switch (_step) {
      0 => AuthTextField(
        key: const Key('teacher_register_access_code_field'),
        controller: _accessCodeController,
        label: 'Teacher access code',
        placeholder: 'XXXX-XXXX-XXXX',
        icon: FluentIcons.permissions,
        helperText: 'Ask an administrator or an existing Teacher for a code.',
        isLoading: _isCheckingAccess,
        validationText: _touched.contains('code') && !_teacherCodeValid
            ? TeacherAuthMessages.accessCodeInvalid
            : null,
        status: _status(
          'code',
          _teacherCodeValid ? null : TeacherAuthMessages.accessCodeInvalid,
        ),
        onChanged: (_) {
          _prevalidatedAccessCode = null;
          _error = null;
          _live('code');
        },
        onFocusChanged: (v) => _blur('code', v),
        onSubmitted: (_) {
          if (_teacherCodeValid) _continueFromAccess();
        },
      ),
      1 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your access code is valid. Choose the sign-in method you want to use for this Teacher account.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          GoogleAuthButton(
            key: const Key('teacher_register_google_button'),
            label: 'Continue with Google',
            isLoading: _isGoogleLoading,
            onPressed: _isLoading ? null : _registerWithGoogle,
          ),
          const SizedBox(height: AppSpacing.md),
          const AuthOrDivider(),
          const SizedBox(height: AppSpacing.md),
          ElixPrimaryButton(
            key: const Key('teacher_register_email_button'),
            label: 'Use email and password',
            onPressed: _isGoogleLoading ? null : _chooseEmailAndPassword,
          ),
        ],
      ),
      2 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: _firstNameController,
            label: 'First name',
            placeholder: 'e.g. Jane',
            icon: FluentIcons.contact,
            dense: dense,
            validationText: _nameError('first'),
            status: _status('first', _nameError('first')),
            onChanged: (_) => _live('first'),
            onFocusChanged: (v) => _blur('first', v),
          ),
          AuthTextField(
            controller: _middleNameController,
            label: 'Middle name (optional)',
            placeholder: 'e.g. Marie',
            icon: FluentIcons.contact,
            dense: dense,
            onChanged: (_) => _live('middle'),
          ),
          AuthTextField(
            controller: _lastNameController,
            label: 'Last name',
            placeholder: 'e.g. Santos',
            icon: FluentIcons.contact,
            dense: dense,
            validationText: _nameError('last'),
            status: _status('last', _nameError('last')),
            onChanged: (_) => _live('last'),
            onFocusChanged: (v) => _blur('last', v),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            key: const Key('teacher_register_email_field'),
            controller: _emailController,
            label: 'Email address',
            placeholder: 'you@school.edu',
            icon: FluentIcons.mail_solid,
            keyboardType: TextInputType.emailAddress,
            dense: dense,
            validationText: _touched.contains('email')
                ? validateAuthEmail(_emailController.text)
                : null,
            status: _status('email', validateAuthEmail(_emailController.text)),
            onChanged: (_) => _live('email'),
            onFocusChanged: (v) => _blur('email', v),
          ),
          AuthTextField(
            controller: _passwordController,
            label: 'Password',
            placeholder: 'Create a password',
            icon: FluentIcons.lock_solid,
            obscureText: true,
            dense: dense,
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
            placeholder: 'Re-enter your password',
            icon: FluentIcons.shield_solid,
            obscureText: true,
            dense: dense,
            onSubmitted: (_) {
              if (_agreedToLegal) _register();
            },
            validationText: _confirmationMessage,
            status: _confirmationStatus,
            onChanged: (_) => _live('confirm'),
            onFocusChanged: (v) => _blur('confirm', v),
          ),
          AuthLegalConsent(
            agreed: _agreedToLegal,
            onChanged: (value) => setState(() => _agreedToLegal = value),
            checkboxKey: const Key('teacher_register_privacy_consent'),
          ),
        ],
      ),
    };
  }

  List<Widget> _stepActions({required bool dense}) {
    return switch (_step) {
      0 => [
        ElixPrimaryButton(
          label: 'Continue',
          isLoading: _isCheckingAccess,
          onPressed: _continueFromAccess,
        ),
      ],
      1 => [
        Align(
          alignment: Alignment.centerLeft,
          child: AuthSecondaryButton(
            label: 'Back',
            dense: dense,
            onPressed: _isGoogleLoading ? null : () => _goToStep(0),
          ),
        ),
      ],
      2 => [
        Row(
          children: [
            AuthSecondaryButton(
              label: 'Back',
              dense: dense,
              onPressed: () => _goToStep(1),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElixPrimaryButton(
                label: 'Continue',
                onPressed: _profileValid ? _continueToSecurity : null,
                dense: dense,
              ),
            ),
          ],
        ),
      ],
      _ => [
        Row(
          children: [
            AuthSecondaryButton(
              label: 'Back',
              dense: dense,
              onPressed: _isLoading ? null : () => _goToStep(2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElixPrimaryButton(
                label: 'Create Teacher account',
                isLoading: _isLoading,
                onPressed: _securityValid ? _register : null,
                dense: dense,
              ),
            ),
          ],
        ),
      ],
    };
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

  String? get _usablePrevalidatedAccessCode {
    final currentCode = CoachCode.tryNormalize(_accessCodeController.text);
    return currentCode == _prevalidatedAccessCode ? currentCode : null;
  }

  bool get _teacherCodeValid =>
      CoachCode.tryNormalize(_accessCodeController.text) != null;

  bool get _securityValid =>
      validateAuthEmail(_emailController.text) == null &&
      validateRegistrationPassword(_passwordController.text) == null &&
      validatePasswordConfirmation(
            _passwordController.text,
            _confirmController.text,
          ) ==
          null &&
      _agreedToLegal;

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
