import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/teacher_routes.dart';
import '../theme/teacher_theme.dart';

class TeacherBrandMark extends StatelessWidget {
  const TeacherBrandMark({
    super.key,
    this.compact = false,
    this.alignment = CrossAxisAlignment.start,
  });

  final bool compact;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 28.0 : 40.0;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          'ELIXR',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
            color: TeacherColors.primary,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'TEACHER',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 4.5,
            color: TeacherColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class TeacherMessageBanner extends StatelessWidget {
  const TeacherMessageBanner({
    super.key,
    required this.message,
    this.isError = true,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? TeacherColors.error : TeacherColors.success;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(message, style: TextStyle(color: color, height: 1.35)),
      ),
    );
  }
}

class TeacherAuthScaffold extends StatelessWidget {
  const TeacherAuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showBack
          ? AppBar(
              leading: BackButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(TeacherRoutes.login);
                  }
                },
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TeacherBrandMark(compact: showBack),
              const SizedBox(height: 28),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TeacherColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TeacherColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class TeacherPasswordField extends StatelessWidget {
  const TeacherPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.visible,
    required this.onVisibilityChanged,
    this.onSubmitted,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<String>? onSubmitted;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide password' : 'Show password',
          onPressed: () => onVisibilityChanged(!visible),
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }
}
