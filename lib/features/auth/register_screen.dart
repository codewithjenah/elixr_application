import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_route_paths.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/auth_scaffold.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../services/auth_service.dart';
import 'auth_text_field.dart';
import 'auth_validators.dart';

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
  int _step = 0;
  final Set<String> _touched = <String>{};

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
    return false;
  }

  void _continueToAccount() {
    setState(() => _touched.addAll(['first', 'last']));
    if (!_validatePersonalDetails()) return;
    setState(() {
      _step = 1;
      _error = null;
    });
  }

  Future<void> _register() async {
    setState(() => _touched.addAll(['email', 'password', 'confirm', 'legal']));
    if (!_agreedToLegal) return;
    if (!_validatePersonalDetails()) return;

    final emailError = validateAuthEmail(_emailController.text);
    final passwordError = validateRegistrationPassword(
      _passwordController.text,
    );
    final confirmError = validatePasswordConfirmation(
      _passwordController.text,
      _confirmController.text,
    );
    if (emailError != null || passwordError != null || confirmError != null) {
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
      noScrollForm: true,
      formOnLeft: true,
      title: 'Train with intention',
      subtitle: 'Start your flair training journey',
      formTitle: _step == 0 ? 'Create your profile' : 'Secure your account',
      formSubtitle: _step == 0
          ? 'Tell us how to address you.'
          : 'Use an email and password to finish setup.',
      formVerticalCompact: verticalCompact,
      formVerticalTight: verticalTight,
      child: Column(
        key: const Key('register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RegistrationProgress(step: _step),
          SizedBox(height: actionGap),
          if (_step == 0) ...[
            AuthTextField(
              controller: _firstNameController,
              label: 'First name',
              placeholder: 'First name',
              icon: FluentIcons.contact,
              dense: dense,
              validationText: _nameError('first'),
              status: _nameStatus('first'),
              onChanged: (_) => _live('first'),
              onFocusChanged: (v) => _blur('first', v),
            ),
            SizedBox(height: fieldGap),
            AuthTextField(
              controller: _middleNameController,
              label: 'Middle name (optional)',
              placeholder: 'Middle name (optional)',
              icon: FluentIcons.contact,
              dense: dense,
              onChanged: (_) => _live('middle'),
            ),
            SizedBox(height: fieldGap),
            AuthTextField(
              controller: _lastNameController,
              label: 'Last name',
              placeholder: 'Last name',
              icon: FluentIcons.contact,
              dense: dense,
              validationText: _nameError('last'),
              status: _nameStatus('last'),
              onChanged: (_) => _live('last'),
              onFocusChanged: (v) => _blur('last', v),
            ),
          ] else ...[
            AuthTextField(
              controller: _emailController,
              label: 'Email address',
              placeholder: 'Email address',
              icon: FluentIcons.mail_solid,
              keyboardType: TextInputType.emailAddress,
              dense: dense,
              validationText: _touched.contains('email')
                  ? validateAuthEmail(_emailController.text)
                  : null,
              status: _fieldStatus(
                'email',
                validateAuthEmail(_emailController.text),
              ),
              onChanged: (_) => _live('email'),
              onFocusChanged: (v) => _blur('email', v),
            ),
            SizedBox(height: fieldGap),
            AuthTextField(
              controller: _passwordController,
              label: 'Password',
              placeholder: 'Password',
              icon: FluentIcons.lock_solid,
              obscureText: true,
              helperText: '8+ characters, including a letter and a number',
              dense: dense,
              validationText: _touched.contains('password')
                  ? validateRegistrationPassword(_passwordController.text)
                  : null,
              status: _fieldStatus(
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
            SizedBox(height: fieldGap),
            AuthTextField(
              controller: _confirmController,
              label: 'Confirm password',
              placeholder: 'Confirm password',
              icon: FluentIcons.shield_solid,
              obscureText: true,
              onSubmitted: (_) {
                if (_agreedToLegal) _register();
              },
              dense: dense,
              validationText: _confirmationMessage,
              status: _confirmationStatus,
              onChanged: (_) => _live('confirm'),
              onFocusChanged: (v) => _blur('confirm', v),
            ),
            SizedBox(height: fieldGap),
            _RegisterLegalConsent(
              agreed: _agreedToLegal,
              onChanged: (value) => setState(() => _agreedToLegal = value),
            ),
          ],
          if ((_step == 0 && !_profileValid) ||
              (_step == 1 && !_accountValid)) ...[
            SizedBox(height: fieldGap),
            Text(
              _step == 0
                  ? 'Enter your first and last name to continue.'
                  : 'Complete the email, password, match, and legal consent requirements.',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: actionGap),
            AuthErrorBanner(message: _error!),
          ],
          SizedBox(height: actionGap),
          if (_step == 0)
            ElixPrimaryButton(
              label: 'Continue',
              onPressed: _profileValid ? _continueToAccount : null,
              dense: dense,
            )
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
                    label: 'Create Account',
                    isLoading: _isLoading,
                    onPressed: _accountValid ? _register : null,
                    dense: dense,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: verticalTight ? AppSpacing.xs : AppSpacing.sm),
          Center(
            child: AuthFooterLink(
              prompt: 'Already have an account?',
              action: 'Sign in',
              onTap: () => context.go(AppRoutePaths.login),
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

  AuthFieldStatus _nameStatus(String field) =>
      _fieldStatus(field, _nameError(field));

  AuthFieldStatus _fieldStatus(String field, String? error) {
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

  bool get _accountValid =>
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

class _RegistrationProgress extends StatelessWidget {
  const _RegistrationProgress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, int index) {
      final active = index <= step;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : context.elixBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${index + 1}. $label',
              style: AppTheme.caption.copyWith(
                color: active
                    ? context.elixTextPrimary
                    : context.elixTextSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: 'Step ${step + 1} of 2',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${step + 1} of 2',
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              segment('Personal details', 0),
              const SizedBox(width: AppSpacing.sm),
              segment('Account & security', 1),
            ],
          ),
        ],
      ),
    );
  }
}

class _RegisterLegalConsent extends StatelessWidget {
  const _RegisterLegalConsent({required this.agreed, required this.onChanged});

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
