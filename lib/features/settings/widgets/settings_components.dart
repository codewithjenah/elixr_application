import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';

/// Surface width at which Settings uses a left nav rail.
const double settingsWideBreakpoint = 860;

/// Maximum Settings dialog surface width.
const double settingsMaxSurfaceWidth = 1040;

/// Maximum content body width inside the Settings surface.
const double settingsMaxBodyWidth = 720;

const double settingsRadiusSm = 8;
const double settingsRadiusMd = 12;
const double settingsRadiusLg = 16;

/// Card-like panel used to group related Settings controls.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
  }
}

/// Label + description with a trailing control.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    required this.trailing,
  });

  final String label;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.body.copyWith(
                  fontSize: 14,
                  color: context.elixTextPrimary,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        trailing,
      ],
    );
  }
}

/// [SettingsRow] specialized for a [ToggleSwitch].
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.label,
    this.description,
    required this.checked,
    required this.onChanged,
    this.toggleKey,
  });

  final String label;
  final String? description;
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      label: label,
      description: description,
      trailing: ToggleSwitch(
        key: toggleKey,
        checked: checked,
        onChanged: onChanged,
      ),
    );
  }
}

/// Section title with optional supporting description.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return ElixEditorialHeader(
      heading: title,
      subtitle: description,
      variant: ElixEditorialHeaderVariant.compact,
    );
  }
}

/// Non-blocking warning or error text under Settings controls.
class SettingsStatusBanner extends StatelessWidget {
  const SettingsStatusBanner({
    super.key,
    required this.message,
    this.isError = true,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? context.elixColors.error
        : context.elixColors.warning;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? FluentIcons.error_badge : FluentIcons.warning,
            size: 14,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Left-rail navigation item with a short selection animation.
class SettingsNavItem extends StatefulWidget {
  const SettingsNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<SettingsNavItem> {
  bool _hovered = false;
  bool _focused = false;

  static const _duration = ElixMotion.micro;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final selected = widget.isSelected;
    final highlighted = selected || _hovered || _focused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs / 2,
        AppSpacing.md,
        AppSpacing.xs / 2,
      ),
      child: Semantics(
        button: true,
        enabled: true,
        selected: selected,
        label: widget.label,
        onTap: widget.onTap,
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: ElixMotion.duration(context, _duration),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: context.isHighContrast
                      ? context.elixCardSurface
                      : selected
                      ? context.elixColors.brandPrimary.withValues(alpha: 0.08)
                      : _hovered
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: _focused
                      ? Border.all(
                          color: context.elixColors.focusRing,
                          width: context.isHighContrast
                              ? ElixFocus.ringWidthHighContrast
                              : ElixFocus.ringWidth,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: ElixMotion.duration(context, _duration),
                      width: 3,
                      height: 28,
                      margin: const EdgeInsets.only(right: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: selected
                            ? context.elixColors.brandPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: context.isHighContrast
                            ? context.elixCardSurface
                            : selected
                            ? context.elixColors.brandPrimary.withValues(
                                alpha: 0.16,
                              )
                            : context.elixBorder.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(settingsRadiusSm),
                        border: context.isHighContrast
                            ? Border.all(color: context.elixBorder)
                            : null,
                      ),
                      child: Icon(
                        widget.icon,
                        size: 15,
                        color: selected
                            ? context.elixColors.brandPrimary
                            : highlighted
                            ? context.elixTextPrimary
                            : context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                          fontSize: 14,
                          color: selected || highlighted
                              ? context.elixTextPrimary
                              : context.elixTextSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled text field with a leading icon, matching Settings form chrome.
class SettingsFormField extends StatelessWidget {
  const SettingsFormField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.elixBackground,
            borderRadius: BorderRadius.circular(settingsRadiusMd),
            border: Border.all(color: context.elixBorder),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(icon, size: 18, color: context.elixTextSecondary),
              ),
              Expanded(
                child: TextBox(
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  enabled: enabled,
                  onChanged: onChanged,
                  style: AppTheme.body,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm + 2,
                    horizontal: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared discard confirmation for dirty Account & Profile / Practice drafts.
class SettingsDiscardConfirm {
  const SettingsDiscardConfirm._();

  /// Returns `true` when the user confirms discarding unsaved changes.
  static Future<bool> show(
    BuildContext context, {
    String message = 'You have unsaved changes. Discard them and close?',
  }) async {
    final result = await ElixDialog.show<bool>(
      context,
      title: 'Discard unsaved changes?',
      subtitle: 'Your edits will be lost',
      icon: FluentIcons.warning,
      iconColor: context.elixColors.warning,
      headerAccentColor: context.elixColors.warning,
      maxWidth: 420,
      barrierDismissible: false,
      content: Text(
        message,
        style: AppTheme.body.copyWith(
          fontSize: 14,
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElixPrimaryButton(
          label: 'Discard',
          expanded: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return result == true;
  }
}
