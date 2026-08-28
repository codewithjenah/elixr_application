import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../services/auth_service.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';

class ProfileMenu {
  ProfileMenu._();

  static const double menuWidth = 312;

  @visibleForTesting
  static String profilePathFor(User user) {
    final userId = user.id?.trim() ?? '';
    if (user.isTeacher) return AppRoutePaths.teacherProfile(userId);
    return '/profile/$userId';
  }

  static void show(
    BuildContext anchorContext, {
    required VoidCallback onLogout,

    /// When set (tests), skip [SettingsScreen.show] and invoke this instead.
    VoidCallback? onOpenSettings,
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
              child: Container(
                color: context.isHighContrast
                    ? Colors.black
                    : Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Positioned(
            left: offset.dx.clamp(8.0, screenSize.width - menuWidth),
            bottom: screenSize.height - offset.dy + AppSpacing.sm,
            width: menuWidth,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: ElixMotion.duration(context, ElixMotion.standard),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final highContrast = context.isHighContrast;
                return Transform.scale(
                  scale: 0.92 + (0.08 * value),
                  alignment: Alignment.bottomLeft,
                  child: highContrast
                      ? child
                      : Opacity(opacity: value, child: child),
                );
              },
              child: _ProfileMenuCard(
                hostContext: anchorContext,
                onDismiss: dismiss,
                onOpenSettings: onOpenSettings,
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
  const _ProfileMenuCard({
    required this.hostContext,
    required this.onDismiss,
    required this.onLogout,
    this.onOpenSettings,
  });

  /// Sidebar/profile tile that opened the menu. Still mounted after dismiss.
  final BuildContext hostContext;
  final VoidCallback onDismiss;
  final VoidCallback onLogout;
  final VoidCallback? onOpenSettings;

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
    final user = context.watch<AuthService>().currentUser;
    final userId = user?.id;
    if (userId != _subscribedUserId) {
      _subscribedUserId = userId;
      _sub?.cancel();
      _sub = null;
      if (userId == null || user?.isTeacher == true) {
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

  void _openSettings() {
    widget.onDismiss();
    final custom = widget.onOpenSettings;
    if (custom != null) {
      custom();
      return;
    }
    final host = widget.hostContext;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted) return;
      SettingsScreen.show(host, initialSection: SettingsSection.appearance);
    });
  }

  void _openMyProfile() {
    final host = widget.hostContext;
    if (!host.mounted) return;
    final user = host.read<AuthService>().currentUser;
    final userId = user?.id?.trim();
    if (user == null || userId == null || userId.isEmpty) return;
    widget.onDismiss();
    if (!host.mounted) return;
    host.go(ProfileMenu.profilePathFor(user));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final name = user?.fullName ?? 'User';
    final role = user?.role ?? 'Trainee';
    final initials = userInitials(name);
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;

    return Container(
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : context.elixBorder.withValues(alpha: isDark ? 0.55 : 1),
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast
            ? const []
            : [
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
            onTap: _openMyProfile,
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
              onTap: _openSettings,
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;

    return Semantics(
      button: true,
      enabled: true,
      label: '${widget.name}, ${widget.subtitle}',
      onTap: widget.onTap,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: ElixMotion.duration(context, ElixMotion.micro),
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : _hovered
                    ? (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : context.elixColors.brandPrimary.withValues(
                              alpha: 0.06,
                            ))
                    : Colors.transparent,
                border: _focused
                    ? Border.all(
                        color: context.elixColors.focusRing,
                        width: highContrast
                            ? ElixFocus.ringWidthHighContrast
                            : ElixFocus.ringWidth,
                      )
                    : null,
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
                            color: highContrast
                                ? context.elixCardSurface
                                : context.elixColors.brandPrimary.withValues(
                                    alpha: 0.14,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            border: highContrast
                                ? Border.all(color: context.elixBorder)
                                : null,
                          ),
                          child: Text(
                            widget.subtitle,
                            style: AppTheme.caption.copyWith(
                              fontSize: 11,
                              color: highContrast
                                  ? context.elixTextPrimary
                                  : context.elixColors.brandPrimary,
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
                    color: highContrast
                        ? context.elixTextPrimary
                        : context.elixTextSecondary.withValues(
                            alpha: _hovered ? 0.9 : 0.55,
                          ),
                  ),
                ],
              ),
            ),
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final color = widget.isDestructive && !highContrast
        ? context.elixColors.error
        : context.elixTextPrimary;
    final iconBg = highContrast
        ? context.elixCardSurface
        : widget.isDestructive
        ? context.elixColors.error.withValues(alpha: _hovered ? 0.14 : 0.08)
        : context.elixBorder.withValues(alpha: isDark ? 0.4 : 0.3);

    return Semantics(
      button: true,
      enabled: true,
      label: widget.description == null
          ? widget.label
          : '${widget.label}. ${widget.description}',
      onTap: widget.onTap,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: ElixMotion.duration(context, ElixMotion.micro),
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: highContrast
                    ? context.elixCardSurface
                    : _hovered
                    ? (widget.isDestructive
                          ? context.elixColors.error.withValues(
                              alpha: isDark ? 0.1 : 0.07,
                            )
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : context.elixBorder.withValues(alpha: 0.28)))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: _focused
                    ? Border.all(
                        color: context.elixColors.focusRing,
                        width: highContrast
                            ? ElixFocus.ringWidthHighContrast
                            : ElixFocus.ringWidth,
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(8),
                      border: highContrast
                          ? Border.all(color: context.elixBorder)
                          : null,
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
      color: context.isHighContrast
          ? context.elixBorder
          : context.elixBorder.withValues(alpha: 0.45),
    );
  }
}
