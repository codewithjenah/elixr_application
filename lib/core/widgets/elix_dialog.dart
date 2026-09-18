import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
import 'elix_editorial_header.dart';
import 'elix_form_field.dart';
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
    this.showCloseButton = true,
    this.expandSingleAction = true,
    this.showFooterDivider = false,
    this.showScrollbars = true,
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

  /// Controls only the visual Shad dialog close affordance. Keyboard and
  /// barrier dismissal continue to follow the route's existing behavior.
  final bool showCloseButton;

  /// Keeps the historical full-width treatment for one footer action by
  /// default. Information-dense desktop dialogs can opt into an end-aligned
  /// action instead.
  final bool expandSingleAction;

  /// Adds restrained separation when a pinned footer belongs to scrollable
  /// instructional content.
  final bool showFooterDivider;

  /// Whether desktop scroll indicators are shown for scrollable content.
  /// Disabling the indicator does not disable mouse-wheel or keyboard scroll.
  final bool showScrollbars;

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
    bool scrollableContent = false,
    bool showCloseButton = true,
    bool expandSingleAction = true,
    bool showFooterDivider = false,
    bool showScrollbars = true,
  }) {
    Widget dialog() => ElixDialog(
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
      scrollableContent: scrollableContent,
      showCloseButton: showCloseButton,
      expandSingleAction: expandSingleAction,
      showFooterDivider: showFooterDivider,
      showScrollbars: showScrollbars,
    );
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: context.isHighContrast
            ? const Color(0xFF000000)
            : const Color(0x8A000000),
        builder: (_) => Center(child: dialog()),
      );
    }
    return shad.showShadDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => ElixShadThemeBridge(child: dialog()),
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
    double maxWidth = 400,
  }) {
    return show<void>(
      context,
      title: title,
      icon: icon,
      iconColor: iconColor ?? context.elixColors.brandPrimary,
      headerAccentColor: headerAccentColor,
      maxWidth: maxWidth,
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

  /// Standard two-action confirmation. Returns true only when the confirm
  /// action is pressed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? subtitle,
    required String message,
    IconData? icon,
    Color? iconColor,
    Color? headerAccentColor,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool destructive = false,
    Key? confirmKey,
    Key? cancelKey,
    Size? uniformActionSize = const Size(128, 56),
    double maxWidth = 480,
    bool barrierDismissible = false,
  }) async {
    final accent = destructive
        ? context.elixColors.error
        : context.elixColors.brandPrimary;
    final result = await show<bool>(
      context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor ?? accent,
      headerAccentColor: headerAccentColor ?? (destructive ? accent : null),
      maxWidth: maxWidth,
      barrierDismissible: barrierDismissible,
      uniformActionSize: uniformActionSize,
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
          key: cancelKey,
          label: cancelLabel,
          expanded: false,
          autofocus: destructive,
          variant: ElixButtonVariant.secondary,
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
        ),
        ElixPrimaryButton(
          key: confirmKey,
          label: confirmLabel,
          expanded: false,
          variant: destructive
              ? ElixButtonVariant.destructive
              : ElixButtonVariant.primary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
    );
    return result == true;
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
              ElixTextField(
                controller: passwordController,
                label: 'Current password',
                obscureText: obscured,
                autofocus: true,
                trailing: IconButton(
                  icon: Icon(
                    obscured ? FluentIcons.view : FluentIcons.hide,
                    size: 15,
                    color: ctx.elixTextSecondary,
                  ),
                  onPressed: () => setState(() => obscured = !obscured),
                ),
                onSubmitted: (password) {
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
        ElixPrimaryButton(
          label: 'Cancel',
          expanded: false,
          variant: ElixButtonVariant.secondary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
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
                  borderRadius: BorderRadius.circular(ElixRadius.control),
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
                        borderRadius: BorderRadius.circular(ElixRadius.control),
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
    final dialogMaxHeight = maxHeight ?? size.height * 0.85;
    final iconTone = highContrast
        ? context.elixTextPrimary
        : (iconColor ?? context.elixColors.brandPrimary);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
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
                      : iconTone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ElixRadius.control),
                  border: highContrast
                      ? Border.all(color: context.elixBorder, width: 2)
                      : null,
                ),
                child: Icon(icon, color: iconTone, size: 22),
              ),
      ),
    );
    const bodyPadding = EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.sm,
      AppSpacing.xl,
      AppSpacing.md,
    );
    final stackedContents = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(padding: bodyPadding, child: content),
      ],
    );
    final dialogActions = actions == null || actions!.isEmpty
        ? const <Widget>[]
        : <Widget>[
            _ElixDialogFooter(
              actions: actions!,
              uniformActionSize: uniformActionSize,
              expandSingleAction: expandSingleAction,
              showDivider: showFooterDivider,
            ),
          ];
    final legacyBody = Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: dialogMaxHeight,
        ),
        margin: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(ElixRadius.dialog),
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
          borderRadius: BorderRadius.circular(ElixRadius.dialog),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scrollableContent) header,
              Flexible(
                fit: FlexFit.loose,
                child: scrollableContent
                    ? SingleChildScrollView(
                        padding: bodyPadding,
                        child: _legacyContent(context, accent, content),
                      )
                    : _legacyContent(context, accent, stackedContents),
              ),
              if (dialogActions.isNotEmpty) dialogActions.single,
            ],
          ),
        ),
      ),
    );
    if (highContrast || shad.ShadTheme.maybeOf(context) == null) {
      return _withScrollbarVisibility(context, legacyBody);
    }
    return _withScrollbarVisibility(
      context,
      shad.ShadDialog(
        key: const ValueKey('elix-shad-dialog'),
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: dialogMaxHeight,
        ),
        padding: EdgeInsets.zero,
        backgroundColor: context.elixCardSurface,
        border: Border.all(color: context.elixColors.borderSubtle),
        shadows: const [],
        // The shared footer owns its responsive layout and its explicit inner
        // spacing, rather than relying on ShadDialog defaults with zero padding.
        expandActionsWhenTiny: false,
        actions: dialogActions,
        scrollable: scrollableContent,
        // ShadDialog treats a supplied close widget as an override for its
        // theme-provided X. The empty widget removes only this dialog's visual
        // affordance; ESC and route dismissal remain unchanged.
        closeIcon: showCloseButton ? null : const SizedBox.shrink(),
        child: stackedContents,
      ),
    );
  }

  Widget _withScrollbarVisibility(BuildContext context, Widget child) {
    if (showScrollbars) return child;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }

  Widget _legacyContent(
    BuildContext context,
    Color accent,
    Widget dialogContents,
  ) {
    return DecoratedBox(
      decoration: context.isHighContrast
          ? const BoxDecoration()
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withValues(alpha: 0.12), Colors.transparent],
              ),
            ),
      child: dialogContents,
    );
  }
}

class _ElixDialogFooter extends StatelessWidget {
  const _ElixDialogFooter({
    required this.actions,
    this.uniformActionSize,
    required this.expandSingleAction,
    required this.showDivider,
  });

  final List<Widget> actions;
  final Size? uniformActionSize;
  final bool expandSingleAction;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final actionWidgets = [
      for (final action in actions)
        if (uniformActionSize == null)
          action
        else
          SizedBox.fromSize(size: uniformActionSize, child: action),
    ];

    return DecoratedBox(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: context.elixBorder)),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (actions.length == 1) {
              final action = actionWidgets.single;
              if (expandSingleAction && constraints.hasBoundedWidth) {
                return SizedBox(width: constraints.maxWidth, child: action);
              }
              return Align(alignment: Alignment.centerRight, child: action);
            }
            return Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actionWidgets,
            );
          },
        ),
      ),
    );
  }
}
