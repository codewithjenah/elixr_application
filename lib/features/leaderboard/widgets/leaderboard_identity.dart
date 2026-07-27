import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class LeaderboardInitialsAvatar extends StatelessWidget {
  const LeaderboardInitialsAvatar({
    super.key,
    required this.initials,
    required this.accent,
    required this.size,
  });

  final String initials;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.35),
            AppColors.primary.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: context.elixTextPrimary,
        ),
      ),
    );
  }
}

class LeaderboardYouBadge extends StatelessWidget {
  const LeaderboardYouBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
      ),
      child: const Text(
        'YOU',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
