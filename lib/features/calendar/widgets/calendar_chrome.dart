import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_panel_card.dart';

/// Shared month-grid surface used by Teacher and Trainee calendars.
class CalendarSurface extends StatelessWidget {
  const CalendarSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
  }
}

/// Monday-first weekday labels for the month grid.
class CalendarWeekdayHeader extends StatelessWidget {
  const CalendarWeekdayHeader({super.key});

  static const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ElixTypography.label(
                color: context.elixTextSecondary,
              ).copyWith(letterSpacing: 0.4, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

/// Day-of-month numeral with Windows-style today and selected treatments.
class CalendarDayNumber extends StatelessWidget {
  const CalendarDayNumber({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isOutsideMonth,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final bool isOutsideMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final muted = isOutsideMonth;
    final numberColor = isSelected
        ? colors.onBrand
        : muted
        ? context.elixTextSecondary.withValues(alpha: 0.45)
        : context.elixTextPrimary;

    final label = Text(
      '$day',
      style: TextStyle(
        fontFamily: ElixTypography.fontFamily,
        fontFamilyFallback: ElixTypography.fontFallbacks,
        fontSize: 13,
        height: 1.1,
        fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
        color: numberColor,
      ),
    );

    if (!isSelected && !isToday) return label;

    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected ? colors.brandPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(isSelected ? 8 : 13),
        border: isSelected
            ? null
            : Border.all(
                color: highContrast
                    ? colors.borderStrong
                    : colors.brandSecondary,
                width: highContrast ? 2 : 1.4,
              ),
      ),
      child: label,
    );
  }
}

/// Keyboard-accessible day cell chrome with hover, selected, today, and focus.
class CalendarDayFrame extends StatefulWidget {
  const CalendarDayFrame({
    super.key,
    required this.onTap,
    required this.semanticLabel,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.child,
    this.height,
  });

  final VoidCallback onTap;
  final String semanticLabel;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideMonth;
  final Widget child;
  final double? height;

  @override
  State<CalendarDayFrame> createState() => _CalendarDayFrameState();
}

class _CalendarDayFrameState extends State<CalendarDayFrame> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.35);
    final minHeight = (widget.height ?? 56) * textScale;

    Color fill;
    Color border;
    var borderWidth = 1.0;

    if (widget.isSelected) {
      fill = highContrast
          ? colors.surfaceBase
          : colors.surfaceSelected.withValues(
              alpha: context.isDarkTheme ? 1 : 0.9,
            );
      border = colors.brandPrimary;
      borderWidth = highContrast ? 2.5 : 1.6;
    } else if (widget.isToday) {
      fill = _hovered ? colors.interactiveHover : Colors.transparent;
      border = colors.brandSecondary;
      borderWidth = highContrast ? 2.5 : 1.4;
    } else {
      fill = _hovered && !highContrast
          ? colors.interactiveHover
          : Colors.transparent;
      border = widget.isOutsideMonth
          ? colors.borderSubtle.withValues(alpha: highContrast ? 1 : 0.35)
          : colors.borderSubtle.withValues(alpha: highContrast ? 1 : 0.7);
    }

    if (_focused) {
      border = colors.focusRing;
      borderWidth = highContrast
          ? ElixFocus.ringWidthHighContrast
          : ElixFocus.ringWidth;
    }

    return Semantics(
      button: true,
      selected: widget.isSelected,
      enabled: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            width: double.infinity,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: borderWidth),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
