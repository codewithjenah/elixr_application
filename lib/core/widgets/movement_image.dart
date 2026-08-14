import 'package:fluent_ui/fluent_ui.dart';

import '../constants/movement_visuals.dart';

/// A consistently sized visual for a catalog movement.
///
/// Unknown or legacy movement names retain a readable, non-emoji fallback.
class MovementImage extends StatelessWidget {
  const MovementImage({
    super.key,
    required this.movementName,
    required this.size,
    this.paddingFactor = 0.08,
    this.alignment = Alignment.center,
  });

  final String movementName;
  final double size;
  final double paddingFactor;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final assetPath = MovementVisuals.assetPathFor(movementName);
    final imageSize =
        (size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1)).round();

    if (assetPath == null) {
      return Semantics(
        image: true,
        label: 'Movement icon: $movementName',
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            FluentIcons.running,
            size: size * 0.5,
            color: Colors.white,
          ),
        ),
      );
    }

    return Semantics(
      image: true,
      label: 'Movement image: $movementName',
      child: SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(size * paddingFactor),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.16),
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
              alignment: alignment,
              cacheWidth: imageSize,
              cacheHeight: imageSize,
            ),
          ),
        ),
      ),
    );
  }
}
