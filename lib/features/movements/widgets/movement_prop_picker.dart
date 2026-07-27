import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Shows Bottle vs Cocktail Shaker for Medium movements.
///
/// Returns `'bottle'`, `'shaker'`, or `null` when cancelled.
Future<String?> showMovementPropPicker(
  BuildContext context,
  String movementName,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => ContentDialog(
      style: ContentDialogThemeData(
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(color: context.elixBorder),
        ),
      ),
      title: Text(
        movementName,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: context.elixTextPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the prop you want to practice with.',
            style: TextStyle(fontSize: 13, color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PropOption(
                  emoji: '🍾',
                  label: 'Bottle',
                  onTap: () => Navigator.of(context).pop('bottle'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PropOption(
                  emoji: '🍸',
                  label: 'Cocktail Shaker',
                  onTap: () => Navigator.of(context).pop('shaker'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _PropOption extends StatefulWidget {
  const _PropOption({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PropOption> createState() => _PropOptionState();
}

class _PropOptionState extends State<_PropOption> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _focused;

    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        onShowHoverHighlight: (hovered) {
          setState(() => _hovered = hovered);
        },
        onShowFocusHighlight: (focused) {
          setState(() => _focused = focused);
        },
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: active ? 0.12 : 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.55)
                    : context.elixBorder,
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: context.isDarkTheme
                        ? (active ? 0.28 : 0.16)
                        : (active ? 0.10 : 0.05),
                  ),
                  blurRadius: active ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                AnimatedScale(
                  scale: active ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
