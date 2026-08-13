import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/teacher_routes.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import 'teacher_auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    await context.read<TeacherAuthController>().login(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();

    return TeacherAuthScaffold(
      title: 'Sign in',
      subtitle: 'Use your ELIXR Teacher account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            visible: _passwordVisible,
            onVisibilityChanged: (value) {
              setState(() => _passwordVisible = value);
            },
            onSubmitted: (_) {
              if (!auth.isBusy) _signIn();
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.go(TeacherRoutes.forgotPassword),
              child: const Text('Forgot password?'),
            ),
          ),
          if (auth.errorMessage != null) ...[
            TeacherMessageBanner(message: auth.errorMessage!),
            const SizedBox(height: 16),
          ],
          FilledButton(
            key: const Key('login_sign_in'),
            onPressed: auth.isBusy ? null : _signIn,
            child: auth.isBusy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign In'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(TeacherRoutes.register),
            child: const Text('Create Teacher Account'),
          ),
        ],
      ),
    );
  }
}
