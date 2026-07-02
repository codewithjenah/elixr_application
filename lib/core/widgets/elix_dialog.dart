import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'elix_primary_button.dart';

class ElixDialog extends StatelessWidget {
  const ElixDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.content,
    this.actions,
    this.maxWidth = 480,
    this.maxHeight,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;
  final double? maxHeight;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? icon,
    Color? iconColor,
    required Widget content,
    List<Widget>? actions,
    double maxWidth = 480,
    double? maxHeight,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => Center(
        child: ElixDialog(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: iconColor,
          content: content,
          actions: actions,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
      ),
    );
  }

  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = FluentIcons.info_solid,
    Color? iconColor,
    String actionLabel = 'OK',
  }) {
    return show<void>(
      context,
      title: title,
      icon: icon,
      iconColor: iconColor ?? AppColors.primary,
      maxWidth: 400,
      content: Text(message, style: AppTheme.body),
      actions: [
        ElixPrimaryButton(
          label: actionLabel,
          expanded: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Future<void> success(BuildContext context, String message) {
    return alert(
      context,
      title: 'Success',
      message: message,
      icon: FluentIcons.status_circle_checkmark,
      iconColor: AppColors.success,
    );
  }

  static Future<void> error(BuildContext context, String message) {
    return alert(
      context,
      title: 'Error',
      message: message,
      icon: FluentIcons.status_circle_error_x,
      iconColor: AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? size.height * 0.85,
        ),
        margin: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: (iconColor ?? AppColors.primary)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          color: iconColor ?? AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTheme.headingLarge),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(subtitle!, style: AppTheme.bodySecondary),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: content),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions!.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        actions![i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
