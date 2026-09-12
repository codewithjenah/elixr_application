import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import 'auth_validators.dart';

enum AuthFieldStatus { neutral, error, success, help }

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.icon,
    this.label,
    this.obscureText = false,
    this.keyboardType,
    this.onSubmitted,
    this.helperText,
    this.dense = false,
    this.status = AuthFieldStatus.neutral,
    this.validationText,
    this.onChanged,
    this.onFocusChanged,
    this.focusNode,
    this.enabled = true,
    this.isLoading = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final String? label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final String? helperText;
  final bool dense;
  final AuthFieldStatus status;
  final String? validationText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<bool>? onFocusChanged;
  final FocusNode? focusNode;
  final bool enabled;
  final bool isLoading;
  final TextInputAction? textInputAction;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class AuthPasswordChecklist extends StatelessWidget {
  const AuthPasswordChecklist({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final length = passwordHasMinimumLength(password);
    final letter = passwordHasLetter(password);
    final number = passwordHasNumber(password);

    return Semantics(
      label:
          'Password requirements: 8 or more characters ${length ? 'met' : 'not met'}, '
          'letter ${letter ? 'met' : 'not met'}, number ${number ? 'met' : 'not met'}',
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _PasswordRequirementChip(met: length, label: '8+ characters'),
            _PasswordRequirementChip(met: letter, label: 'Letter'),
            _PasswordRequirementChip(met: number, label: 'Number'),
          ],
        ),
      ),
    );
  }
}

class _PasswordRequirementChip extends StatelessWidget {
  const _PasswordRequirementChip({required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final tone = met ? colors.success : colors.textMuted;
    final border = met
        ? (highContrast
              ? colors.success
              : colors.success.withValues(alpha: 0.5))
        : colors.borderSubtle;

    return AnimatedContainer(
      duration: ElixMotion.duration(context, ElixMotion.standard),
      curve: ElixMotion.standardCurve,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: highContrast
            ? colors.canvas
            : met
            ? colors.success.withValues(alpha: 0.12)
            : colors.surfaceInteractive.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: highContrast ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            child: Icon(
              met ? FluentIcons.check_mark : FluentIcons.status_circle_inner,
              key: ValueKey(met),
              size: 11,
              color: tone,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: met ? colors.textPrimary : colors.textSecondary,
              fontWeight: met ? FontWeight.w600 : FontWeight.w500,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant AuthTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText && widget.obscureText) {
      _obscured = true;
    }
    if (oldWidget.obscureText && !widget.obscureText) {
      _obscured = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final enabled = widget.enabled && !widget.isLoading;
    final statusColor = switch (widget.status) {
      AuthFieldStatus.error => colors.error,
      AuthFieldStatus.success => colors.success,
      AuthFieldStatus.help || AuthFieldStatus.neutral => colors.textSecondary,
    };
    final statusIcon = switch (widget.status) {
      AuthFieldStatus.error => FluentIcons.error_badge,
      AuthFieldStatus.success => FluentIcons.completed_solid,
      AuthFieldStatus.help => FluentIcons.info_solid,
      AuthFieldStatus.neutral => null,
    };
    final supportingText = widget.validationText ?? widget.helperText;
    final emphasizeStatus =
        widget.status == AuthFieldStatus.error ||
        widget.status == AuthFieldStatus.success;
    final motion = ElixMotion.duration(context, ElixMotion.standard);

    final Color borderColor;
    var borderWidth = highContrast ? 2.0 : 1.0;
    if (!enabled) {
      borderColor = colors.disabledBorder;
    } else if (emphasizeStatus) {
      borderColor = highContrast
          ? statusColor
          : statusColor.withValues(alpha: _focused ? 0.95 : 0.72);
      borderWidth = highContrast ? 2.5 : (_focused ? 1.6 : 1.15);
    } else if (_focused) {
      borderColor = highContrast ? colors.focusRing : colors.brandPrimary;
      borderWidth = highContrast ? 2.5 : 1.5;
    } else if (_hovered) {
      borderColor = highContrast
          ? colors.borderStrong
          : colors.borderInteractive.withValues(alpha: 0.7);
    } else {
      borderColor = colors.borderSubtle.withValues(alpha: isDark ? 0.9 : 1);
    }

    final fill = !enabled
        ? colors.disabledSurface
        : highContrast
        ? colors.surfaceRaised
        : Color.alphaBlend(
            colors.brandPrimary.withValues(
              alpha: _focused
                  ? (isDark ? 0.07 : 0.04)
                  : _hovered
                  ? (isDark ? 0.04 : 0.025)
                  : 0.0,
            ),
            isDark
                ? Colors.white.withValues(alpha: _focused ? 0.045 : 0.03)
                : Colors.black.withValues(alpha: _focused ? 0.03 : 0.018),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTheme.label(
              color: _focused && enabled
                  ? colors.textPrimary
                  : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        MouseRegion(
          onEnter: (_) {
            if (enabled) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          cursor: enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
          child: Focus(
            onFocusChange: (v) {
              setState(() => _focused = v);
              widget.onFocusChanged?.call(v);
            },
            child: AnimatedContainer(
              duration: motion,
              curve: ElixMotion.standardCurve,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: fill,
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: highContrast || !enabled
                    ? const []
                    : [
                        if (_focused && !emphasizeStatus)
                          BoxShadow(
                            color: colors.glowPrimary.withValues(alpha: 0.16),
                            blurRadius: 14,
                            spreadRadius: -4,
                          ),
                        if (_focused && widget.status == AuthFieldStatus.error)
                          BoxShadow(
                            color: colors.error.withValues(alpha: 0.16),
                            blurRadius: 12,
                            spreadRadius: -4,
                          ),
                        if (_focused &&
                            widget.status == AuthFieldStatus.success)
                          BoxShadow(
                            color: colors.success.withValues(alpha: 0.14),
                            blurRadius: 12,
                            spreadRadius: -4,
                          ),
                      ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: widget.dense ? 46 : 50),
                child: context.isHighContrast
                    ? TextBox(
                        controller: widget.controller,
                        placeholder: widget.placeholder,
                        placeholderStyle: AppTheme.body.copyWith(
                          color: colors.textMuted.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                        obscureText: _obscured,
                        keyboardType: widget.keyboardType,
                        onSubmitted: widget.onSubmitted,
                        onChanged: widget.onChanged,
                        focusNode: widget.focusNode,
                        enabled: enabled,
                        textInputAction: widget.textInputAction,
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: widget.dense ? 8 : 11,
                        ),
                        prefix: Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.sm + 2,
                          ),
                          child: Icon(
                            widget.icon,
                            color: !enabled
                                ? colors.disabledText
                                : _focused
                                ? (emphasizeStatus
                                      ? statusColor
                                      : colors.brandPrimary)
                                : colors.textSecondary,
                            size: 16,
                          ),
                        ),
                        suffix: widget.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ProgressRing(strokeWidth: 2),
                                ),
                              )
                            : widget.obscureText
                            ? Semantics(
                                button: true,
                                label: _obscured
                                    ? 'Show password'
                                    : 'Hide password',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: IconButton(
                                    icon: Icon(
                                      _obscured
                                          ? FluentIcons.view
                                          : FluentIcons.hide,
                                      size: 15,
                                      color: colors.textSecondary,
                                    ),
                                    onPressed: enabled
                                        ? () => setState(
                                            () => _obscured = !_obscured,
                                          )
                                        : null,
                                  ),
                                ),
                              )
                            : null,
                        style: AppTheme.body.copyWith(
                          color: enabled
                              ? colors.textPrimary
                              : colors.disabledText,
                          fontSize: 14,
                        ),
                      )
                    : shad.ShadInput(
                        key: const ValueKey('auth-shad-input'),
                        controller: widget.controller,
                        placeholder: Text(widget.placeholder),
                        obscureText: _obscured,
                        keyboardType: widget.keyboardType,
                        onSubmitted: widget.onSubmitted,
                        onChanged: widget.onChanged,
                        focusNode: widget.focusNode,
                        enabled: enabled,
                        textInputAction: widget.textInputAction,
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: widget.dense ? 8 : 11,
                        ),
                        leading: Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.sm + 2,
                          ),
                          child: Icon(
                            widget.icon,
                            color: !enabled
                                ? colors.disabledText
                                : _focused
                                ? (emphasizeStatus
                                      ? statusColor
                                      : colors.brandPrimary)
                                : colors.textSecondary,
                            size: 16,
                          ),
                        ),
                        trailing: widget.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ProgressRing(strokeWidth: 2),
                                ),
                              )
                            : widget.obscureText
                            ? Semantics(
                                button: true,
                                label: _obscured
                                    ? 'Show password'
                                    : 'Hide password',
                                child: IconButton(
                                  icon: Icon(
                                    _obscured
                                        ? FluentIcons.view
                                        : FluentIcons.hide,
                                    size: 15,
                                    color: colors.textSecondary,
                                  ),
                                  onPressed: enabled
                                      ? () => setState(
                                          () => _obscured = !_obscured,
                                        )
                                      : null,
                                ),
                              )
                            : null,
                        style: AppTheme.body.copyWith(
                          color: enabled
                              ? colors.textPrimary
                              : colors.disabledText,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 22,
          child: supportingText == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 2, top: 5),
                  child: Row(
                    children: [
                      if (statusIcon != null) ...[
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          supportingText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
