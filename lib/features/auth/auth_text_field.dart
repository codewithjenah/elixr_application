import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.onSubmitted,
    this.helperText,
    this.dense = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final String? helperText;
  final bool dense;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isDark
                  ? Colors.white.withValues(alpha: _focused ? 0.05 : 0.025)
                  : Colors.black.withValues(alpha: _focused ? 0.025 : 0.015),
              border: Border.all(
                color: _focused
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
            child: TextBox(
              controller: widget.controller,
              placeholder: widget.placeholder,
              obscureText: _obscured,
              keyboardType: widget.keyboardType,
              onSubmitted: widget.onSubmitted,
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
              suffix: widget.obscureText
                  ? IconButton(
                      icon: Icon(
                        _obscured ? FluentIcons.view : FluentIcons.hide,
                        size: 15,
                        color: context.elixTextSecondary,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    )
                  : null,
              style: AppTheme.body.copyWith(
                color: context.elixTextPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              widget.helperText!,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
