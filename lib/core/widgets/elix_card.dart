import 'package:flutter/widgets.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

class ElixCard extends StatelessWidget {
  const ElixCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: AppTheme.cardDecoration(context),
      child: child,
    );

    if (onTap == null) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}
