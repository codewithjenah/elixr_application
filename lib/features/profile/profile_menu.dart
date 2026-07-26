import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'profile_settings_screen.dart';

class ProfileMenu {
  ProfileMenu._();

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
            left: offset.dx.clamp(8.0, screenSize.width - 300),
            bottom: screenSize.height - offset.dy + AppSpacing.sm,
            width: 300,
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

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({required this.onDismiss, required this.onLogout});

  final VoidCallback onDismiss;
  final VoidCallback onLogout;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  void _openSettings(BuildContext context, ProfileSettingsSection section) {
    onDismiss();
    ProfileSettingsScreen.show(context, initialSection: section);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final name = user?.fullName ?? 'User';
    final role = user?.role ?? 'Trainee';
    final initials = _initials(name);
    final isDark = context.isDarkTheme;

    return Container(
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.elixBorder.withValues(alpha: isDark ? 0.6 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
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
            imagePath: user?.profilePicturePath,
            onTap: () => _openSettings(context, ProfileSettingsSection.account),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: _ProfileMenuItem(
              icon: FluentIcons.settings,
              label: 'Settings',
              description: 'Preferences & appearance',
              onTap: () =>
                  _openSettings(context, ProfileSettingsSection.preferences),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _MenuDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: _ProfileMenuItem(
              icon: FluentIcons.sign_out,
              label: 'Log out',
              onTap: onLogout,
              isDestructive: true,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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
    required this.imagePath,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String initials;
  final String? imagePath;
  final VoidCallback onTap;

  @override
  State<_ProfileMenuHeader> createState() => _ProfileMenuHeaderState();
}

class _ProfileMenuHeaderState extends State<_ProfileMenuHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: _hovered ? 0.18 : 0.12),
                AppColors.primarySoft.withValues(alpha: _hovered ? 0.1 : 0.06),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primarySoft],
                  ),
                ),
                child: ProfileAvatarWidget(
                  imagePath: widget.imagePath,
                  initials: widget.initials,
                  radius: 22,
                ),
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
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
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
    final color = widget.isDestructive
        ? AppColors.error
        : context.elixTextPrimary;
    final iconBg = widget.isDestructive
        ? AppColors.error.withValues(alpha: 0.12)
        : context.elixBorder.withValues(alpha: 0.35);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 4,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDestructive
                      ? AppColors.error.withValues(alpha: 0.08)
                      : context.elixBorder.withValues(alpha: 0.25))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon, size: 17, color: color),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTheme.body.copyWith(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.description != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.description!,
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: context.elixTextSecondary,
                        ),
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
      color: context.elixBorder.withValues(alpha: 0.5),
    );
  }
}
