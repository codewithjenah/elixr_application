import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_panel_card.dart';
import 'calendar_chrome.dart';

/// Secondary agenda surface that sits beside the month calendar.
class CalendarAgendaPanel extends StatelessWidget {
  const CalendarAgendaPanel({
    super.key,
    required this.date,
    required this.subtitle,
    required this.child,
    this.eyebrow = 'AGENDA',
  });

  final DateTime date;
  final String subtitle;
  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return ElixPanelCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: ElixTypography.eyebrow(color: context.elixTextSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat.MMMMEEEEd().format(date),
            style: ElixTypography.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: ElixTypography.label(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(height: 1, color: colors.borderSubtle),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Section heading inside a daily agenda (training vs classroom).
class CalendarAgendaSection extends StatelessWidget {
  const CalendarAgendaSection({
    super.key,
    required this.title,
    required this.child,
    this.topSpacing = true,
  });

  final String title;
  final Widget child;
  final bool topSpacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topSpacing) const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: ElixTypography.eyebrow(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Quiet inset used for empty/unplanned agenda copy.
class CalendarAgendaInset extends StatelessWidget {
  const CalendarAgendaInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceTinted,
        borderRadius: BorderRadius.circular(CalendarLayout.tileRadius),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }
}

/// Shared interactive row for classroom/deadline work in the agenda.
class CalendarWorkRow extends StatefulWidget {
  const CalendarWorkRow({
    super.key,
    required this.title,
    required this.onOpen,
    required this.leadingIcon,
    required this.accent,
    this.subtitle,
    this.meta,
    this.actionLabel = 'Open',
    this.badges = const [],
  });

  final String title;
  final VoidCallback onOpen;
  final IconData leadingIcon;
  final Color accent;
  final String? subtitle;
  final String? meta;
  final String actionLabel;
  final List<Widget> badges;

  @override
  State<CalendarWorkRow> createState() => _CalendarWorkRowState();
}

class _CalendarWorkRowState extends State<CalendarWorkRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final accent = widget.accent;
    final border = _focused
        ? colors.focusRing
        : (_hovered && !highContrast
              ? colors.borderStrong
              : (highContrast
                    ? colors.borderStrong
                    : accent.withValues(alpha: 0.38)));
    final fill = highContrast
        ? colors.surfaceBase
        : Color.alphaBlend(
            accent.withValues(alpha: _hovered ? 0.12 : 0.07),
            colors.surfaceRaised,
          );

    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.actionLabel}',
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
              widget.onOpen();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(CalendarLayout.tileRadius),
              border: Border.all(
                color: border,
                width: _focused
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.leadingIcon, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: ElixTypography.label(
                          color: context.elixTextPrimary,
                        ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ElixTypography.supporting(
                            color: context.elixTextSecondary,
                          ).copyWith(fontSize: 11),
                        ),
                      ],
                      if (widget.meta != null)
                        Text(
                          widget.meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ElixTypography.supporting(
                            color: context.elixTextSecondary,
                          ).copyWith(fontSize: 11),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...widget.badges,
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FluentIcons.chevron_right,
                                size: 11,
                                color: context.elixTextPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.actionLabel,
                                style: ElixTypography.label(
                                  color: context.elixTextPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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
