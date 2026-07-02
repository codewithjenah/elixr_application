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
              child: Container(color: const Color(0x66000000)),
            ),
          ),
          Positioned(
            left: offset.dx,
            bottom: screenSize.height - offset.dy + AppSpacing.sm,
            width: 280,
            child: _ProfileMenuCard(
              onDismiss: dismiss,
              onLogout: () {
                dismiss();
                onLogout();
              },
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({
    required this.onDismiss,
    required this.onLogout,
  });

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

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
          const _MenuDivider(),
          _ProfileMenuItem(
            icon: FluentIcons.contact,
            label: 'Profile',
            onTap: () => _openSettings(context, ProfileSettingsSection.profile),
          ),
          _ProfileMenuItem(
            icon: FluentIcons.settings,
            label: 'Settings',
            onTap: () =>
                _openSettings(context, ProfileSettingsSection.preferences),
          ),
          const _MenuDivider(),
          _ProfileMenuItem(
            icon: FluentIcons.sign_out,
            label: 'Log out',
            onTap: onLogout,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              ProfileAvatarWidget(
                imagePath: imagePath,
                initials: initials,
                radius: 18,
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTheme.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.caption.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                FluentIcons.chevron_right,
                size: 14,
                color: AppColors.textSecondary,
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
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_ProfileMenuItem> createState() => _ProfileMenuItemState();
}

class _ProfileMenuItemState extends State<_ProfileMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isDestructive ? AppColors.error : AppColors.textPrimary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: _hovered
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm + 4),
              Text(
                widget.label,
                style: AppTheme.body.copyWith(
                  fontSize: 14,
                  color: color,
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
      color: AppColors.border.withValues(alpha: 0.5),
    );
  }
}
