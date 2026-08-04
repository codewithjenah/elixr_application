import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/profile_border.dart';
import '../constants/app_colors.dart';

/// Renders a cosmetic profile border around [child] without clipping the
/// avatar content. Unknown / null borders fall back to a neutral ring when
/// [fallbackNeutral] is true, or no chrome when false.
class ProfileBorderFrame extends StatelessWidget {
  const ProfileBorderFrame({
    super.key,
    required this.size,
    required this.child,
    this.equippedBorderId,
    this.showBorder = true,
    this.fallbackNeutral = true,
    this.highlightAccent,
  });

  final double size;
  final Widget child;
  final String? equippedBorderId;
  final bool showBorder;
  final bool fallbackNeutral;

  /// Optional outer accent (e.g. current-user / medal ring) drawn outside
  /// the cosmetic border so ranking semantics stay visible.
  final Color? highlightAccent;

  @override
  Widget build(BuildContext context) {
    if (!showBorder) {
      return SizedBox(width: size, height: size, child: child);
    }

    final definition = equippedBorderId == null
        ? null
        : profileBorderById(equippedBorderId!);

    if (definition == null) {
      if (!fallbackNeutral && highlightAccent == null) {
        return SizedBox(width: size, height: size, child: child);
      }
      return _framed(
        size: size,
        strokeWidth: highlightAccent != null ? 2 : 1.5,
        gradient: LinearGradient(
          colors: [
            (highlightAccent ?? AppColors.accent).withValues(alpha: 0.55),
            AppColors.primary.withValues(alpha: 0.25),
          ],
        ),
        glow: highlightAccent != null
            ? [
                BoxShadow(
                  color: highlightAccent!.withValues(alpha: 0.22),
                  blurRadius: 6,
                ),
              ]
            : null,
        child: child,
      );
    }

    final primary = Color(definition.primaryColorValue);
    final secondary = Color(definition.secondaryColorValue);
    final glow = definition.glowStrength <= 0
        ? null
        : [
            BoxShadow(
              color: primary.withValues(alpha: 0.35),
              blurRadius: definition.glowStrength,
            ),
          ];

    Widget framed = _framed(
      size: size,
      strokeWidth: definition.strokeWidth,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, secondary],
      ),
      glow: glow,
      child: child,
    );

    if (highlightAccent != null) {
      framed = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: highlightAccent!.withValues(alpha: 0.75),
            width: 2,
          ),
        ),
        child: framed,
      );
    }

    return framed;
  }

  static Widget _framed({
    required double size,
    required double strokeWidth,
    required Gradient gradient,
    required List<BoxShadow>? glow,
    required Widget child,
  }) {
    // Outer size grows by the stroke so the clipped avatar keeps its
    // original [size] and is not cropped by the border.
    final outer = size + strokeWidth * 2;
    return Container(
      width: outer,
      height: outer,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: glow,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
