import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/teacher_router.dart';
import 'core/theme/teacher_theme.dart';
import 'core/widgets/teacher_auth_widgets.dart';
import 'features/auth/teacher_auth_controller.dart';

class ElixrTeacherApp extends StatefulWidget {
  const ElixrTeacherApp({super.key, required this.authController});

  final TeacherAuthController authController;

  @override
  State<ElixrTeacherApp> createState() => _ElixrTeacherAppState();
}

class _ElixrTeacherAppState extends State<ElixrTeacherApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createTeacherRouter(widget.authController);
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
      child: MaterialApp.router(
        title: 'ELIXR Teacher',
        theme: buildTeacherTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return Consumer<TeacherAuthController>(
            builder: (context, auth, _) {
              if (auth.isInitializing) {
                return const TeacherStartupScreen();
              }
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}

class TeacherStartupScreen extends StatelessWidget {
  const TeacherStartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TeacherBrandMark(alignment: CrossAxisAlignment.center),
              SizedBox(height: 28),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
