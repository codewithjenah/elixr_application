import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/teacher_routes.dart';
import '../../core/theme/teacher_theme.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import 'teacher_auth_controller.dart';

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
  bool _passwordVisible = false;
  bool _confirmVisible = false;

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
    await context.read<TeacherAuthController>().register(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
      legalConsent: _agreedToLegal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final canSubmit = _agreedToLegal && !auth.isBusy;

    return TeacherAuthScaffold(
      title: 'Create Teacher account',
      subtitle: 'Register with your name and work email',
      child: Column(
        key: const Key('register_form_fields'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _firstNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'First name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _middleNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Middle name (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Last name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TeacherPasswordField(
            controller: _passwordController,
            label: 'Password',
            helperText: 'At least 6 characters',
            visible: _passwordVisible,
            onVisibilityChanged: (value) {
              setState(() => _passwordVisible = value);
            },
          ),
          const SizedBox(height: 12),
          TeacherPasswordField(
            controller: _confirmController,
            label: 'Confirm password',
            visible: _confirmVisible,
            onVisibilityChanged: (value) {
              setState(() => _confirmVisible = value);
            },
            onSubmitted: (_) {
              if (canSubmit) _register();
            },
          ),
          const SizedBox(height: 16),
          _RegisterLegalConsent(
            agreed: _agreedToLegal,
            onChanged: (value) => setState(() => _agreedToLegal = value),
          ),
          if (auth.errorMessage != null) ...[
            const SizedBox(height: 16),
            TeacherMessageBanner(message: auth.errorMessage!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('register_create_account'),
            onPressed: canSubmit ? _register : null,
            child: auth.isBusy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create Account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(TeacherRoutes.login),
            child: const Text('Already have an account? Sign in'),
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
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: TeacherColors.textSecondary,
      height: 1.35,
    );
    final linkStyle = baseStyle?.copyWith(
      color: TeacherColors.primary,
      decoration: TextDecoration.underline,
      decorationColor: TeacherColors.primary,
    );

    return CheckboxListTile(
      key: const Key('register_privacy_consent'),
      value: agreed,
      onChanged: (value) => onChanged(value == true),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GestureDetector(
            onTap: () => onChanged(!agreed),
            child: Text('I agree to the ', style: baseStyle),
          ),
          GestureDetector(
            onTap: () => context.push(TeacherRoutes.privacyPolicy),
            child: Text('Privacy Policy', style: linkStyle),
          ),
          Text(' and ', style: baseStyle),
          GestureDetector(
            onTap: () => context.push(TeacherRoutes.termsOfService),
            child: Text('Terms of Service', style: linkStyle),
          ),
        ],
      ),
    );
  }
}
