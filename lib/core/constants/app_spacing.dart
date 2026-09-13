abstract final class AppSpacing {
  /// The base unit for ELIXR layout. New shared components should compose this
  /// scale rather than introduce one-off spacing values.
  static const unit = 4.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const smPlus = 12.0;
  static const md = 16.0;
  static const mdPlus = 20.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const controlHeight = 40.0;
  static const compactControlHeight = 32.0;
  static const iconControlSize = 40.0;

  /// Shared vertical start for top-level page and hero headers.
  static const pageTopInset = xl;

  /// Guided practice dashboard layout.
  static const practiceDesktopBreakpoint = 1180.0;
  static const practiceCompactBreakpoint = 820.0;
  static const practiceMaxContentWidth = 1680.0;
  static const practicePanelMinWidth = 360.0;
  static const practicePanelMaxWidth = 420.0;
  static const practiceCameraPanelGap = 22.0;
  static const practiceSurfaceRadius = 22.0;
}
