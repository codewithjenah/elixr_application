import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';

/// Shared medal / badge visuals for podium and ranking rows.
abstract final class LeaderboardRankStyle {
  static const silver = Color(0xFFB8C0CC);
  static const bronze = Color(0xFFCD7F32);

  static Color medalForRank(int rank) {
    switch (rank) {
      case 1:
        return AppColors.warning;
      case 2:
        return silver;
      case 3:
        return bronze;
      default:
        return AppColors.accent;
    }
  }
}

class LeaderboardInitialsAvatar extends StatelessWidget {
  const LeaderboardInitialsAvatar({
    super.key,
    required this.initials,
    required this.accent,
    required this.size,
    this.profilePictureUrl,
    this.equippedBorderId,
    this.highlightRing = false,
  });

  final String initials;
  final Color accent;
  final double size;

  /// Optional HTTPS Cloud Storage download URL mirrored on the leaderboard row.
  final String? profilePictureUrl;

  /// Public equipped cosmetic border id. Does not replace medal / YOU chrome.
  final String? equippedBorderId;

  /// Subtle current-user ring that does not replace the medal accent.
  final bool highlightRing;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = profilePictureUrl?.trim();
    final hasUrl = trimmedUrl != null && trimmedUrl.isNotEmpty;

    final inner = hasUrl
        ? Image.network(
            trimmedUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _initialsContent(context);
            },
            errorBuilder: (context, error, stackTrace) =>
                _initialsContent(context),
          )
        : _initialsContent(context);

    return ProfileBorderFrame(
      size: size,
      equippedBorderId: equippedBorderId,
      showBorder: true,
      fallbackNeutral: false,
      highlightAccent: highlightRing ? AppColors.primary : accent,
      child: inner,
    );
  }

  Widget _initialsContent(BuildContext context) {
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
  const LeaderboardYouBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
      ),
      child: Text(
        'YOU',
        style: TextStyle(
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
