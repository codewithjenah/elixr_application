import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// Label, helper, and validation chrome shared by ELIXR form controls.
///
/// The field body intentionally remains a normal Flutter/Shadcn input so
/// controllers, formatters, keyboard behavior, and form ownership are never
/// hidden behind a custom state abstraction.
class ElixFieldFrame extends StatelessWidget {
  const ElixFieldFrame({
    super.key,
    required this.child,
    this.label,
    this.helperText,
    this.errorText,
    this.required = false,
  });

  final Widget child;
  final String? label;
  final String? helperText;
  final String? errorText;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final supporting = hasError ? errorText : helperText;
    final supportingColor = hasError
        ? context.elixColors.error
        : context.elixTextSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          RichText(
            text: TextSpan(
              style: AppTheme.label(color: context.elixTextPrimary),
              children: [
                TextSpan(text: label),
                if (required)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: context.elixColors.error),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AnimatedContainer(
          duration: ElixMotion.duration(context, ElixMotion.micro),
          curve: ElixMotion.microCurve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ElixRadius.control),
            border: hasError
                ? Border.all(color: context.elixColors.error, width: 2)
                : null,
          ),
          child: child,
        ),
        if (supporting != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: hasError,
            child: Text(
              supporting,
              style: AppTheme.caption.copyWith(color: supportingColor),
            ),
          ),
        ],
      ],
    );
  }
}

class ElixTextField extends StatelessWidget {
  const ElixTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.required = false,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.leading,
    this.trailing,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? placeholder;
  final String? helperText;
  final String? errorText;
  final bool required;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ElixFieldFrame(
    label: label,
    helperText: helperText,
    errorText: errorText,
    required: required,
    child: shad.ShadInput(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder == null ? null : Text(placeholder!),
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      leading: leading,
      trailing: trailing,
      style: AppTheme.body.copyWith(color: context.elixTextPrimary),
      placeholderStyle: AppTheme.body.copyWith(
        color: context.elixColors.textMuted,
      ),
    ),
  );
}

class ElixTextArea extends StatelessWidget {
  const ElixTextArea({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.required = false,
    this.enabled = true,
    this.minHeight = 96,
    this.maxHeight = 320,
    this.onChanged,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? placeholder;
  final String? helperText;
  final String? errorText;
  final bool required;
  final bool enabled;
  final double minHeight;
  final double maxHeight;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => ElixFieldFrame(
    label: label,
    helperText: helperText,
    errorText: errorText,
    required: required,
    child: shad.ShadTextarea(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder == null ? null : Text(placeholder!),
      enabled: enabled,
      minHeight: minHeight,
      maxHeight: maxHeight,
      onChanged: onChanged,
      style: AppTheme.body.copyWith(color: context.elixTextPrimary),
      placeholderStyle: AppTheme.body.copyWith(
        color: context.elixColors.textMuted,
      ),
    ),
  );
}

/// A semantic divider for card sections and dense desktop forms.
class ElixSeparator extends StatelessWidget {
  const ElixSeparator({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) => vertical
      ? shad.ShadSeparator.vertical(color: context.elixBorder)
      : shad.ShadSeparator.horizontal(color: context.elixBorder);
}
