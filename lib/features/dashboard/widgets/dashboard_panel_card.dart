import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';

export '../../../core/widgets/elix_panel_card.dart'
    show ElixHoverSurface, ElixPill;

typedef DashboardPill = ElixPill;
typedef DashboardHoverSurface = ElixHoverSurface;

/// Layered glass-like surface used by the trainee dashboard.
class DashboardPanelCard extends StatelessWidget {
  const DashboardPanelCard({
    super.key,
    required this.child,
    this.accent,
    this.padding,
    this.showAccentBar = false,
    this.expand = true,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry? padding;
  final bool showAccentBar;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final dark = context.isDarkTheme;
    final tint = accent ?? AppColors.accent;
    final radius = BorderRadius.circular(16);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: child,
    );

    return Container(
      width: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: highContrast ? context.elixCardSurface : null,
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [
                        Color(0xFF1B172A),
                        Color(0xFF12111D),
                        Color(0xFF211126),
                      ]
                    : [
                        context.elixCardSurface,
                        context.elixPanelSurface,
                        Color.alphaBlend(
                          tint.withValues(alpha: 0.04),
                          context.elixCardSurface,
                        ),
                      ],
                stops: const [0, 0.58, 1],
              ),
        borderRadius: radius,
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : tint.withValues(alpha: showAccentBar ? 0.48 : 0.20),
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast
            ? const []
            : [
                const BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
                if (showAccentBar)
                  BoxShadow(
                    color: tint.withValues(alpha: 0.16),
                    blurRadius: 24,
                    spreadRadius: -8,
                  ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (!highContrast)
              Positioned(
                right: -46,
                bottom: -62,
                child: Container(
                  width: 160,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        tint.withValues(alpha: showAccentBar ? 0.15 : 0.07),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            if (showAccentBar && accent != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tint,
                        tint.withValues(alpha: 0.28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            if (showAccentBar && accent != null)
              Padding(padding: const EdgeInsets.only(left: 3), child: content)
            else
              content,
          ],
        ),
      ),
    );
  }
}
