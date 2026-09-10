import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// Compact accent-washed KPI chip used by Planner and History summaries.
class ElixSummaryStatCard extends StatefulWidget {
  const ElixSummaryStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.detail,
    this.infoTooltip,
    this.infoTooltipKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color accent;
  final String? infoTooltip;
  final Key? infoTooltipKey;

  @override
  State<ElixSummaryStatCard> createState() => _ElixSummaryStatCardState();
}

class _ElixSummaryStatCardState extends State<ElixSummaryStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final accent = widget.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: ElixMotion.duration(context, ElixMotion.micro),
        curve: ElixMotion.microCurve,
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered && !highContrast
                ? accent.withValues(alpha: 0.45)
                : context.elixBorder,
          ),
          gradient: highContrast
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(
                      alpha: context.isDarkTheme
                          ? (_hovered ? 0.14 : 0.08)
                          : 0.06,
                    ),
                    context.elixCardSurface,
                  ],
                ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: accent.withValues(
                      alpha: context.isDarkTheme
                          ? (_hovered ? 0.14 : 0.08)
                          : 0.05,
                    ),
                    blurRadius: 16,
                    spreadRadius: -8,
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: context.isDarkTheme ? 0.18 : 0.12,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.icon, size: 14, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.value,
                    style: TextStyle(
                      fontFamily: ElixTypography.fontFamily,
                      fontFamilyFallback: ElixTypography.fontFallbacks,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: context.elixTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.detail!,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.infoTooltip != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  key: widget.infoTooltipKey,
                  message: widget.infoTooltip!,
                  child: Semantics(
                    label: widget.infoTooltip,
                    button: false,
                    child: Icon(
                      FluentIcons.info,
                      size: 13,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
