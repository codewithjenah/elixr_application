import 'package:fluent_ui/fluent_ui.dart';

import '../theme/app_theme.dart';

/// Trainee-facing copy for personally unrevealed movement identity.
abstract final class MovementSpoilerCopy {
  static const lockedMovement = 'Locked Movement';

  static String unlocksAtLevel(int level) => 'Unlocks at Level $level';

  static String semanticsLabel({int? unlockLevel}) {
    if (unlockLevel == null) return 'Locked movement';
    return 'Locked movement, unlocks at Level $unlockLevel';
  }

  static String hiddenCompletedCount(int count) {
    if (count == 1) return '1 locked movement';
    return '$count locked movements';
  }
}

/// Non-identifiable lock plate. Never renders catalog artwork or names.
class LockedMovementMark extends StatelessWidget {
  const LockedMovementMark({
    super.key,
    required this.size,
    required this.accent,
  });

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final borderWidth = highContrast ? 2.0 : 1.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : accent.withValues(alpha: context.isDarkTheme ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : accent.withValues(alpha: 0.38),
          width: borderWidth,
        ),
      ),
      child: Icon(
        FluentIcons.lock_solid,
        size: size * 0.42,
        color: highContrast ? context.elixTextPrimary : accent,
      ),
    );
  }
}
