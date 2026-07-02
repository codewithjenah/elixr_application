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
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

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
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused
                ? AppColors.primary.withValues(alpha: 0.6)
                : context.elixBorder.withValues(alpha: 0.8),
            width: _focused ? 1.5 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
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
          padding: const EdgeInsets.all(AppSpacing.md),
          prefix: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: Icon(
              widget.icon,
              color: _focused ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
          ),
          suffix: widget.obscureText
              ? Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: IconButton(
                    icon: Icon(
                      _obscured ? FluentIcons.view : FluentIcons.hide,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                )
              : null,
          style: AppTheme.body,
        ),
      ),
    );
  }
}
