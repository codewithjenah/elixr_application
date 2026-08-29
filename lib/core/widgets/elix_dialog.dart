import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'elix_editorial_header.dart';
import 'elix_primary_button.dart';

class ElixDialog extends StatelessWidget {
  const ElixDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.headerAccentColor,
    required this.content,
    this.actions,
    this.uniformActionSize,
    this.maxWidth = 480,
    this.maxHeight,
    this.scrollableContent = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? headerAccentColor;
  final Widget content;
  final List<Widget>? actions;

  /// Applies the same tight size to every action in the footer.
  ///
  /// Confirmation dialogs use this to keep secondary and primary actions
  /// visually balanced even when their labels or button implementations differ.
  final Size? uniformActionSize;
  final double maxWidth;
  final double? maxHeight;

  /// When true, the content area scrolls inside [maxHeight] instead of
  /// expanding the dialog past the viewport.
  final bool scrollableContent;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? icon,
    Color? iconColor,
    Color? headerAccentColor,
    required Widget content,
    List<Widget>? actions,
    Size? uniformActionSize,
    double maxWidth = 480,
    double? maxHeight,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: context.isHighContrast
          ? Colors.black
          : const Color(0xCC000000),
      builder: (ctx) => Center(
        child: ElixDialog(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: iconColor,
          headerAccentColor: headerAccentColor,
          content: content,
          actions: actions,
          uniformActionSize: uniformActionSize,
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
    Color? headerAccentColor,
    String actionLabel = 'OK',
  }) {
    return show<void>(
      context,
      title: title,
      icon: icon,
      iconColor: iconColor ?? context.elixColors.brandPrimary,
      headerAccentColor: headerAccentColor,
      maxWidth: 400,
      content: Text(
        message,
        style: AppTheme.body.copyWith(
          fontSize: 14,
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        ElixPrimaryButton(
          label: actionLabel,
          expanded: false,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
      iconColor: context.elixColors.success,
      headerAccentColor: context.elixColors.success,
    );
  }

  static Future<String?> promptCurrentPassword(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final passwordController = TextEditingController();
    var obscured = true;

    return show<String>(
      context,
      title: title,
      subtitle: 'Confirm your identity',
      icon: FluentIcons.lock_solid,
      iconColor: context.elixColors.brandPrimary,
      maxWidth: 420,
      barrierDismissible: false,
      content: StatefulBuilder(
        builder: (ctx, setState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: AppTheme.body.copyWith(
                  fontSize: 14,
                  color: ctx.elixTextSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Current password',
                style: AppTheme.caption.copyWith(color: ctx.elixTextSecondary),
              ),
              const SizedBox(height: 6),
              TextBox(
                controller: passwordController,
                obscureText: obscured,
                autofocus: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 11,
                ),
                suffix: IconButton(
                  icon: Icon(
                    obscured ? FluentIcons.view : FluentIcons.hide,
                    size: 15,
                    color: ctx.elixTextSecondary,
                  ),
                  onPressed: () => setState(() => obscured = !obscured),
                ),
                onSubmitted: (_) {
                  final password = passwordController.text;
                  if (password.isNotEmpty) {
                    Navigator.of(ctx).pop(password);
                  }
                },
              ),
            ],
          );
        },
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        ElixPrimaryButton(
          label: 'Confirm',
          expanded: false,
          onPressed: () {
            final password = passwordController.text;
            if (password.isEmpty) return;
            Navigator.of(context, rootNavigator: true).pop(password);
          },
        ),
      ],
    ).whenComplete(passwordController.dispose);
  }

  static Future<void> emailVerificationSent(
    BuildContext context,
    String newEmail,
  ) {
    return alert(
      context,
      title: 'Verify your new email',
      message:
          'Firebase sent a verification link (not a numeric code) to $newEmail. '
          'Open that inbox, including Spam or Promotions, and tap the link. '
          'Your current sign-in email stays active until the new address is verified.',
      icon: FluentIcons.mail,
      iconColor: context.elixColors.brandPrimary,
    );
  }

  static Future<void> currentEmailVerificationSent(
    BuildContext context,
    String email,
  ) {
    return alert(
      context,
      title: 'Verify your email',
      message:
          'Firebase sent a verification link (not a numeric code) to $email. '
          'Check Spam or Promotions if you do not see it within a few minutes.',
      icon: FluentIcons.mail,
      iconColor: context.elixColors.brandPrimary,
    );
  }

  static Future<void> passwordUpdated(BuildContext context) {
    return show<void>(
      context,
      title: 'Password updated',
      subtitle: 'Your sign-in password has been changed',
      icon: FluentIcons.completed_solid,
      iconColor: context.elixColors.success,
      headerAccentColor: context.elixColors.success,
      maxWidth: 420,
      content: Builder(
        builder: (ctx) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your new password is now active on your Elixr account.',
                style: AppTheme.body.copyWith(
                  fontSize: 14,
                  color: ctx.elixTextSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 4,
                ),
                decoration: BoxDecoration(
                  color: ctx.isHighContrast
                      ? ctx.elixCardSurface
                      : ctx.elixColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ctx.isHighContrast
                        ? ctx.elixBorder
                        : ctx.elixColors.success.withValues(alpha: 0.22),
                    width: ctx.isHighContrast ? 2 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ctx.isHighContrast
                            ? ctx.elixCardSurface
                            : ctx.elixColors.success.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: ctx.isHighContrast
                            ? Border.all(color: ctx.elixBorder)
                            : null,
                      ),
                      child: Icon(
                        FluentIcons.lock_solid,
                        size: 14,
                        color: ctx.elixColors.success,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        'Use your new password the next time you sign in.',
                        style: AppTheme.caption.copyWith(
                          color: ctx.elixTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        ElixPrimaryButton(
          label: 'Done',
          expanded: true,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  static Future<void> error(BuildContext context, String message) {
    return alert(
      context,
      title: 'Error',
      message: message,
      icon: FluentIcons.status_circle_error_x,
      iconColor: context.elixColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final accent = headerAccentColor ?? context.elixColors.brandPrimary;
    final highContrast = context.isHighContrast;
    final iconTone = highContrast
        ? context.elixTextPrimary
        : (iconColor ?? context.elixColors.brandPrimary);

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
            color: highContrast
                ? context.elixBorder
                : accent.withValues(alpha: 0.22),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: context.elixColors.brandPrimary.withValues(
                      alpha: 0.08,
                    ),
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
            mainAxisSize: scrollableContent
                ? MainAxisSize.max
                : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                decoration: highContrast
                    ? null
                    : BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                child: ElixEditorialHeader(
                  heading: title,
                  subtitle: subtitle,
                  variant: ElixEditorialHeaderVariant.compact,
                  leading: icon == null
                      ? null
                      : Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: highContrast
                                ? context.elixCardSurface
                                : iconTone.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: highContrast
                                ? Border.all(
                                    color: context.elixBorder,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Icon(icon, color: iconTone, size: 22),
                        ),
                ),
              ),
              if (scrollableContent)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.md,
                    ),
                    child: content,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: content,
                ),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: actions!.length == 1
                      ? SizedBox(width: double.infinity, child: actions!.first)
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            for (var i = 0; i < actions!.length; i++) ...[
                              if (i > 0) const SizedBox(width: AppSpacing.sm),
                              if (uniformActionSize == null)
                                actions![i]
                              else
                                SizedBox.fromSize(
                                  size: uniformActionSize,
                                  child: actions![i],
                                ),
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
