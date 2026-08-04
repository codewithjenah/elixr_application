import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/profile_border.dart';

const _kBorderCardMainExtent = 188.0;
const _kBorderMaxCrossExtent = 168.0;

class ProfileBorderPicker extends StatelessWidget {
  const ProfileBorderPicker({
    super.key,
    required this.unlockedBorderIds,
    required this.equippedBorderId,
    required this.busyBorderId,
    required this.onEquip,
    required this.onUnequip,
  });

  final Set<String> unlockedBorderIds;
  final String? equippedBorderId;
  final String? busyBorderId;
  final ValueChanged<String> onEquip;
  final VoidCallback onUnequip;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: profileBorderCatalog.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _kBorderMaxCrossExtent,
        mainAxisExtent: _kBorderCardMainExtent,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemBuilder: (context, index) {
        final border = profileBorderCatalog[index];
        return _BorderCardItem(
          border: border,
          unlocked: unlockedBorderIds.contains(border.id),
          equipped: equippedBorderId == border.id,
          busy: busyBorderId == border.id,
          onEquip: () => onEquip(border.id),
        );
      },
    );
  }
}

class _BorderCardItem extends StatefulWidget {
  const _BorderCardItem({
    required this.border,
    required this.unlocked,
    required this.equipped,
    required this.busy,
    required this.onEquip,
  });

  final ProfileBorderDefinition border;
  final bool unlocked;
  final bool equipped;
  final bool busy;
  final VoidCallback onEquip;

  @override
  State<_BorderCardItem> createState() => _BorderCardItemState();
}

class _BorderCardItemState extends State<_BorderCardItem> {
  bool _hovered = false;
  bool _focused = false;

  Color get _accent => Color(widget.border.primaryColorValue);

  bool get _interactive => widget.unlocked && !widget.equipped && !widget.busy;

  void _handleEquip() {
    if (!_interactive) return;
    widget.onEquip();
  }

  Color _previewPlateColor(BuildContext context) {
    final base = context.isDarkTheme
        ? AppColors.background.withValues(alpha: 0.84)
        : AppColors.cardSurfaceLight.withValues(alpha: 0.96);
    return Color.alphaBlend(_accent.withValues(alpha: 0.08), base);
  }

  Color _previewGlyphColor(BuildContext context) {
    return widget.unlocked
        ? context.elixTextPrimary
        : context.elixTextSecondary;
  }

  Widget _buildBorderPreview(BuildContext context) {
    final glyphColor = _previewGlyphColor(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.unlocked)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _accent.withValues(alpha: 0.18),
                  _accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ProfileBorderFrame(
          size: 44,
          equippedBorderId: widget.border.id,
          child: ColoredBox(
            color: _previewPlateColor(context),
            child: Center(
              child: Icon(
                widget.unlocked ? FluentIcons.contact : FluentIcons.lock,
                size: widget.unlocked ? 22 : 20,
                color: glyphColor,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(
                      alpha: context.isDarkTheme ? 0.32 : 0.1,
                    ),
                    blurRadius: 1.5,
                    offset: const Offset(0, 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _interactive && (_hovered || _focused);
    final isDark = context.isDarkTheme;
    final accent = _accent;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, active ? -2.0 : 0.0, 0),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: isDark ? 0.08 : 0.05)
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.equipped
              ? AppColors.primary.withValues(alpha: active ? 0.75 : 0.6)
              : widget.unlocked
              ? accent.withValues(alpha: active ? 0.55 : 0.35)
              : context.elixBorder.withValues(alpha: isDark ? 0.65 : 0.85),
          width: widget.equipped || _focused ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isDark ? (active ? 0.28 : 0.14) : (active ? 0.09 : 0.04),
            ),
            blurRadius: active ? 10 : 5,
            offset: Offset(0, active ? 3 : 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                color: widget.unlocked ? accent : context.elixBorder,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
              child: Column(
                children: [
                  Expanded(child: Center(child: _buildBorderPreview(context))),
                  Text(
                    widget.border.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: context.elixTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.unlocked ? widget.border.rarity.name : 'Locked',
                    style: AppTheme.caption.copyWith(
                      fontSize: 9,
                      color: widget.unlocked
                          ? AppColors.accent
                          : context.elixTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildAction(context, accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.unlocked) {
      return Semantics(
        label: '${widget.border.displayName}. Locked border.',
        child: card,
      );
    }

    return Semantics(
      button: _interactive,
      enabled: _interactive,
      label: widget.equipped
          ? '${widget.border.displayName}. Equipped.'
          : '${widget.border.displayName}. ${widget.border.rarity.name}. Equip border.',
      child: FocusableActionDetector(
        enabled: _interactive,
        onShowFocusHighlight: (focused) {
          setState(() => _focused = focused);
        },
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: _interactive
            ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _handleEquip();
                    return null;
                  },
                ),
              }
            : const <Type, Action<Intent>>{},
        child: MouseRegion(
          onEnter: (_) {
            if (_interactive) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          cursor: _interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: _interactive ? _handleEquip : null,
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, Color accent) {
    if (widget.equipped) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Equipped',
          style: AppTheme.caption.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 9,
          ),
        ),
      );
    }

    if (!widget.unlocked) {
      return Text(
        'Locked',
        style: AppTheme.caption.copyWith(
          fontSize: 10,
          color: context.elixTextSecondary,
        ),
      );
    }

    return Button(
      onPressed: widget.busy ? null : _handleEquip,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        ),
      ),
      child: widget.busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: ProgressRing(strokeWidth: 2),
            )
          : const Text('Equip', style: TextStyle(fontSize: 10)),
    );
  }
}

class UnequipBorderButton extends StatelessWidget {
  const UnequipBorderButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !busy;
    return Button(
      onPressed: active ? onPressed : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (!active) {
            return context.elixBorder.withValues(alpha: 0.25);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(
              alpha: context.isDarkTheme ? 0.14 : 0.1,
            );
          }
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (!active) return context.elixTextSecondary;
          return context.elixTextPrimary;
        }),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : const Text('Unequip border'),
    );
  }
}
