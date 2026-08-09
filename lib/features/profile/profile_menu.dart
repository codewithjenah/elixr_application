import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/user.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../services/auth_service.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';

class ProfileMenu {
  ProfileMenu._();

  static const double menuWidth = 312;

  static void show(
    BuildContext anchorContext, {
    required VoidCallback onLogout,
  }) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !anchorContext.mounted) return;

    final overlay = Overlay.of(anchorContext, rootOverlay: true);
    final offset = box.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(anchorContext);

    late OverlayEntry entry;

    void dismiss() {
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: dismiss,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Positioned(
            left: offset.dx.clamp(8.0, screenSize.width - menuWidth),
            bottom: screenSize.height - offset.dy + AppSpacing.sm,
            width: menuWidth,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Transform.scale(
                scale: 0.92 + (0.08 * value),
                alignment: Alignment.bottomLeft,
                child: Opacity(opacity: value, child: child),
              ),
              child: _ProfileMenuCard(
                onDismiss: dismiss,
                onLogout: () {
                  dismiss();
                  onLogout();
                },
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }
}

class _ProfileMenuCard extends StatefulWidget {
  const _ProfileMenuCard({required this.onDismiss, required this.onLogout});

  final VoidCallback onDismiss;
  final VoidCallback onLogout;

  @override
  State<_ProfileMenuCard> createState() => _ProfileMenuCardState();
}

class _ProfileMenuCardState extends State<_ProfileMenuCard> {
  final _leaderboardRepo = LeaderboardRepository();
  StreamSubscription<LeaderboardEntry?>? _sub;
  String? _equippedBorderId;
  String? _subscribedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AuthService>().currentUser?.id;
    if (userId != _subscribedUserId) {
      _subscribedUserId = userId;
      _sub?.cancel();
      _sub = null;
      if (userId == null) {
        _equippedBorderId = null;
        return;
      }
      _sub = _leaderboardRepo.watchPlayer(userId).listen((entry) {
        if (!mounted) return;
        setState(() => _equippedBorderId = entry?.equippedBorderId);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openSettings(BuildContext context) {
    widget.onDismiss();
    SettingsScreen.show(context, initialSection: SettingsSection.appearance);
  }

  void _openMyProfile(BuildContext context) {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    widget.onDismiss();
    context.go('/profile/$userId');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final name = user?.fullName ?? 'User';
    final role = user?.role ?? 'Trainee';
    final initials = userInitials(name);
    final isDark = context.isDarkTheme;

    return Container(
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileMenuHeader(
            name: name,
            subtitle: role,
            initials: initials,
            user: user,
            equippedBorderId: _equippedBorderId,
            onTap: () => _openMyProfile(context),
          ),
          const _MenuDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: _ProfileMenuItem(
              icon: FluentIcons.settings,
              label: 'Settings',
              description: 'Account, privacy & preferences',
              onTap: () => _openSettings(context),
            ),
          ),
          const _MenuDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: _ProfileMenuItem(
              icon: FluentIcons.sign_out,
              label: 'Log out',
              onTap: widget.onLogout,
              isDestructive: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuHeader extends StatefulWidget {
  const _ProfileMenuHeader({
    required this.name,
    required this.subtitle,
    required this.initials,
    required this.user,
    required this.equippedBorderId,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String initials;
  final User? user;
  final String? equippedBorderId;
  final VoidCallback onTap;

  @override
  State<_ProfileMenuHeader> createState() => _ProfileMenuHeaderState();
}

class _ProfileMenuHeaderState extends State<_ProfileMenuHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: _hovered
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : AppColors.primary.withValues(alpha: 0.06))
                : Colors.transparent,
          ),
          child: Row(
            children: [
              ProfileAvatarWidget(
                networkImageUrl: widget.user?.profilePictureUrl,
                legacyLocalPath: widget.user?.profilePicturePath,
                initials: widget.initials,
                radius: 22,
                equippedBorderId: widget.equippedBorderId,
                animateBorder: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: context.elixTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.subtitle,
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                FluentIcons.chevron_right,
                size: 12,
                color: context.elixTextSecondary.withValues(
                  alpha: _hovered ? 0.9 : 0.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuItem extends StatefulWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final String? description;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_ProfileMenuItem> createState() => _ProfileMenuItemState();
}

class _ProfileMenuItemState extends State<_ProfileMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final color = widget.isDestructive
        ? AppColors.error
        : context.elixTextPrimary;
    final iconBg = widget.isDestructive
        ? AppColors.error.withValues(alpha: _hovered ? 0.14 : 0.08)
        : context.elixBorder.withValues(alpha: isDark ? 0.4 : 0.3);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDestructive
                      ? AppColors.error.withValues(alpha: isDark ? 0.1 : 0.07)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : context.elixBorder.withValues(alpha: 0.28)))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 15, color: color),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: AppTheme.body.copyWith(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.description != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.description!,
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: context.elixTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      color: context.elixBorder.withValues(alpha: 0.45),
    );
  }
}
