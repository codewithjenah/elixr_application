import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/public_profile.dart';
import '../../leaderboard/leaderboard_presentation.dart';
import '../../leaderboard/widgets/leaderboard_identity.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.displayName,
    this.profilePictureUrl,
    this.equippedBorderId,
    this.level,
    this.totalXp,
    this.rank,
    this.showUnrankedLabel = false,
    this.visibility,
    this.showOwnerActions = false,
    this.onEditProfile,
    this.onPreviewProfile,
    this.onPrivacy,
    this.onEditAvatar,
    this.isTeacher = false,
  });

  final String displayName;
  final String? profilePictureUrl;
  final String? equippedBorderId;
  final int? level;
  final int? totalXp;
  final int? rank;
  final bool showUnrankedLabel;
  final ProfileVisibility? visibility;
  final bool showOwnerActions;
  final VoidCallback? onEditProfile;
  final VoidCallback? onPreviewProfile;
  final VoidCallback? onPrivacy;
  final VoidCallback? onEditAvatar;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 4,
      ),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? AppColors.panelSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactActions = constraints.maxWidth < 820;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AvatarBlock(
                displayName: displayName,
                profilePictureUrl: profilePictureUrl,
                equippedBorderId: equippedBorderId,
                editable: showOwnerActions && onEditAvatar != null,
                onEditAvatar: onEditAvatar,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _IdentityBlock(
                  displayName: displayName,
                  level: level,
                  totalXp: totalXp,
                  rank: rank,
                  showUnrankedLabel: showUnrankedLabel,
                  visibility: showOwnerActions ? visibility : null,
                  isTeacher: isTeacher,
                ),
              ),
              if (showOwnerActions) ...[
                const SizedBox(width: AppSpacing.md),
                _OwnerActions(
                  compact: compactActions,
                  onEditProfile: onEditProfile,
                  onPreviewProfile: onPreviewProfile,
                  onPrivacy: onPrivacy,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AvatarBlock extends StatefulWidget {
  const _AvatarBlock({
    required this.displayName,
    required this.editable,
    this.profilePictureUrl,
    this.equippedBorderId,
    this.onEditAvatar,
  });

  final String displayName;
  final String? profilePictureUrl;
  final String? equippedBorderId;
  final bool editable;
  final VoidCallback? onEditAvatar;

  @override
  State<_AvatarBlock> createState() => _AvatarBlockState();
}

class _AvatarBlockState extends State<_AvatarBlock> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 100.0;
    final avatar = LeaderboardInitialsAvatar(
      initials: LeaderboardPresentation.initialsFor(widget.displayName),
      accent: AppColors.primary,
      size: avatarSize,
      profilePictureUrl: widget.profilePictureUrl,
      equippedBorderId: widget.equippedBorderId,
      highlightRing: false,
      animateBorder: true,
    );

    if (!widget.editable) {
      return avatar;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Edit profile picture',
        child: Tooltip(
          message: 'Edit profile picture',
          child: GestureDetector(
            onTap: widget.onEditAvatar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                avatar,
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.42),
                      ),
                      child: const Icon(
                        FluentIcons.camera,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.displayName,
    this.level,
    this.totalXp,
    this.rank,
    this.showUnrankedLabel = false,
    this.visibility,
    this.isTeacher = false,
  });

  final String displayName;
  final int? level;
  final int? totalXp;
  final int? rank;
  final bool showUnrankedLabel;
  final ProfileVisibility? visibility;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[];
    if (level != null) metaParts.add('Level $level');
    if (totalXp != null) metaParts.add('$totalXp XP');
    if (rank != null) {
      metaParts.add('Rank #$rank');
    } else if (showUnrankedLabel) {
      metaParts.add('Unranked');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: context.elixTextPrimary,
          ),
        ),
        if (metaParts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            metaParts.join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: context.elixTextSecondary,
            ),
          ),
        ],
        if (isTeacher || visibility != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isTeacher) const _TeacherBadge(),
              if (visibility != null) _VisibilityBadge(visibility: visibility!),
            ],
          ),
        ],
      ],
    );
  }
}

class _TeacherBadge extends StatelessWidget {
  const _TeacherBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.education,
            size: 11,
            color: context.elixTextSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'Teacher',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility});

  final ProfileVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == ProfileVisibility.public;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.elixBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? FluentIcons.globe : FluentIcons.lock,
            size: 11,
            color: context.elixTextSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            isPublic ? 'Public' : 'Locked',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerActions extends StatelessWidget {
  const _OwnerActions({
    required this.compact,
    this.onEditProfile,
    this.onPreviewProfile,
    this.onPrivacy,
  });

  final bool compact;
  final VoidCallback? onEditProfile;
  final VoidCallback? onPreviewProfile;
  final VoidCallback? onPrivacy;

  @override
  Widget build(BuildContext context) {
    final previewButton = Button(
      onPressed: onPreviewProfile,
      child: const Text('Preview as Visitor'),
    );
    final privacyButton = HyperlinkButton(
      onPressed: onPrivacy,
      child: Text(
        'Privacy',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.elixTextSecondary,
        ),
      ),
    );
    final editButton = FilledButton(
      onPressed: onEditProfile,
      child: const Text('Edit Profile'),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          editButton,
          const SizedBox(height: AppSpacing.sm),
          previewButton,
          privacyButton,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            previewButton,
            const SizedBox(width: AppSpacing.sm),
            editButton,
          ],
        ),
        const SizedBox(height: 4),
        privacyButton,
      ],
    );
  }
}
