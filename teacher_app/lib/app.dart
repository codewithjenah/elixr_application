import 'dart:async';

import 'package:elixr_core/repositories/firebase_teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/teacher_router.dart';
import 'core/theme/teacher_theme.dart';
import 'core/widgets/teacher_auth_widgets.dart';
import 'features/auth/teacher_auth_controller.dart';

class ElixrTeacherApp extends StatefulWidget {
  const ElixrTeacherApp({
    super.key,
    required this.authController,
    this.relationshipRepository,
  });

  final TeacherAuthController authController;
  final TeacherRelationshipRepository? relationshipRepository;

  @override
  State<ElixrTeacherApp> createState() => _ElixrTeacherAppState();
}

class _ElixrTeacherAppState extends State<ElixrTeacherApp> {
  late final GoRouter _router;
  late final TeacherRelationshipRepository _relationshipRepository;

  @override
  void initState() {
    super.initState();
    _router = createTeacherRouter(widget.authController);
    _relationshipRepository =
        widget.relationshipRepository ??
        FirebaseTeacherRelationshipRepository();
    unawaited(widget.authController.initialize());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TeacherAuthController>.value(
      value: widget.authController,
      child: Provider<TeacherRelationshipRepository>.value(
        value: _relationshipRepository,
        child: MaterialApp.router(
          title: 'ELIXR Teacher',
          theme: buildTeacherTheme(),
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return Consumer<TeacherAuthController>(
              builder: (context, auth, _) {
                if (auth.showsStartupOverlay) {
                  return const TeacherStartupScreen();
                }
                return child ?? const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );
  }
}

class TeacherStartupScreen extends StatelessWidget {
  const TeacherStartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final failed = auth.hasInitializationFailed;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TeacherBrandMark(alignment: CrossAxisAlignment.center),
                const SizedBox(height: 28),
                if (!failed)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else ...[
                  TeacherMessageBanner(
                    message:
                        auth.errorMessage ??
                        TeacherAuthMessages.initializationTimeout,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('startup_retry'),
                    onPressed: auth.isBusy
                        ? null
                        : () => unawaited(auth.retryInitialization()),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('startup_sign_out'),
                    onPressed: auth.isBusy
                        ? null
                        : () => unawaited(auth.signOut()),
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
