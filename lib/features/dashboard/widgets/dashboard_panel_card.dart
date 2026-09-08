import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
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
    return ElixPanelCard(
      accent: accent,
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      showAccentBar: showAccentBar,
      expand: expand,
      variant: showAccentBar
          ? ElixPanelVariant.hero
          : ElixPanelVariant.elevated,
      child: child,
    );
  }
}
