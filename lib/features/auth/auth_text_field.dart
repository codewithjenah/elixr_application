import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
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
    String item(bool met, String label) => '${met ? '✓' : '○'} $label';

    return Semantics(
      label:
          'Password requirements: 8 or more characters ${length ? 'met' : 'not met'}, '
          'letter ${letter ? 'met' : 'not met'}, number ${number ? 'met' : 'not met'}',
      child: Text(
        '${item(length, '8+ characters')}   ${item(letter, 'Letter')}   ${item(number, 'Number')}',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      ),
    );
  }
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final statusColor = switch (widget.status) {
      AuthFieldStatus.error => AppColors.error,
      AuthFieldStatus.success => AppColors.success,
      AuthFieldStatus.help ||
      AuthFieldStatus.neutral => context.elixTextSecondary,
    };
    final statusIcon = switch (widget.status) {
      AuthFieldStatus.error => FluentIcons.error_badge,
      AuthFieldStatus.success => FluentIcons.completed_solid,
      AuthFieldStatus.help => FluentIcons.info_solid,
      AuthFieldStatus.neutral => null,
    };
    final supportingText = widget.validationText ?? widget.helperText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Focus(
          onFocusChange: (v) {
            setState(() => _focused = v);
            widget.onFocusChanged?.call(v);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isDark
                  ? Colors.white.withValues(alpha: _focused ? 0.05 : 0.025)
                  : Colors.black.withValues(alpha: _focused ? 0.025 : 0.015),
              border: Border.all(
                color:
                    widget.status == AuthFieldStatus.error ||
                        widget.status == AuthFieldStatus.success
                    ? statusColor.withValues(alpha: 0.75)
                    : _focused
                    ? AppColors.primary.withValues(alpha: 0.55)
                    : context.elixBorder.withValues(alpha: isDark ? 0.55 : 0.8),
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.dense ? 48 : 52),
              child: TextBox(
                controller: widget.controller,
                placeholder: widget.placeholder,
                obscureText: _obscured,
                keyboardType: widget.keyboardType,
                onSubmitted: widget.onSubmitted,
                onChanged: widget.onChanged,
                focusNode: widget.focusNode,
                enabled: widget.enabled && !widget.isLoading,
                textInputAction: widget.textInputAction,
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: widget.dense ? 8 : 11,
                ),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm + 2),
                  child: Icon(
                    widget.icon,
                    color: _focused
                        ? AppColors.primary
                        : context.elixTextSecondary,
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
                    ? Tooltip(
                        message: _obscured ? 'Show password' : 'Hide password',
                        child: IconButton(
                          icon: Icon(
                            _obscured ? FluentIcons.view : FluentIcons.hide,
                            size: 15,
                            color: context.elixTextSecondary,
                          ),
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        ),
                      )
                    : null,
                style: AppTheme.body.copyWith(
                  color: context.elixTextPrimary,
                  fontSize: 14,
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
                  padding: const EdgeInsets.only(left: 2, top: AppSpacing.xs),
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
