import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import 'calendar_chrome.dart';

/// Compact calendar KPI tile shared by Teacher and Trainee overviews.
class CalendarMetricTile extends StatefulWidget {
  const CalendarMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final ElixTone tone;
  final String? detail;

  @override
  State<CalendarMetricTile> createState() => _CalendarMetricTileState();
}

class _CalendarMetricTileState extends State<CalendarMetricTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final accent = ElixToneCues.color(colors, widget.tone);
    final iconData = widget.icon;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: ElixMotion.duration(context, ElixMotion.micro),
        curve: ElixMotion.microCurve,
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(CalendarLayout.tileRadius),
          border: Border.all(
            color: _hovered && !highContrast
                ? accent.withValues(alpha: 0.45)
                : colors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: highContrast ? colors.borderStrong : accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              iconData,
              size: 14,
              color: highContrast ? context.elixTextPrimary : accent,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ElixTypography.label(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    widget.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ElixTypography.cardTitle(
                      color: context.elixTextPrimary,
                    ).copyWith(fontSize: 18, height: 1.1),
                  ),
                  if (widget.detail != null)
                    Text(
                      widget.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ElixTypography.supporting(
                        color: context.elixTextSecondary,
                      ).copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
