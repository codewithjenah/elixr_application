import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_constants.dart';

/// Brand logo used on splash, auth, and sidebar surfaces.
class ElixAppLogo extends StatelessWidget {
  const ElixAppLogo({super.key, required this.size, this.borderRadius});

  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius ?? size * 0.22);
    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        AppConstants.appLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: '${AppConstants.appName} logo',
      ),
    );
  }
}
