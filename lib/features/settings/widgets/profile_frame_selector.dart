import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/profile_border.dart';

/// Compact cosmetics loadout for equipping avatar frames in Settings.
class ProfileFrameSelector extends StatelessWidget {
  const ProfileFrameSelector({
    super.key,
    required this.unlockedBorderIds,
    required this.equippedBorderId,
    required this.busyBorderId,
    required this.actionsDisabled,
    required this.onSelectBorder,
    required this.onClearBorder,
  });

  final Set<String> unlockedBorderIds;
  final String? equippedBorderId;
  final String? busyBorderId;
  final bool actionsDisabled;
  final ValueChanged<String> onSelectBorder;
  final VoidCallback onClearBorder;

  bool get _noneSelected =>
      equippedBorderId == null || equippedBorderId!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _NoFrameTile(
          key: const Key('frame_tile_none'),
          selected: _noneSelected,
          busy: busyBorderId == '' && actionsDisabled,
          disabled: actionsDisabled,
          onTap: () {
            if (actionsDisabled || _noneSelected) return;
            onClearBorder();
          },
        ),
        for (final border in profileBorderCatalog)
          _FrameTile(
            key: Key('frame_tile_${border.id}'),
            border: border,
            unlocked: unlockedBorderIds.contains(border.id),
            selected: equippedBorderId == border.id,
            busy: busyBorderId == border.id,
            actionsDisabled: actionsDisabled,
            onSelect: () {
              if (actionsDisabled) return;
              if (!unlockedBorderIds.contains(border.id)) return;
              if (equippedBorderId == border.id) return;
              onSelectBorder(border.id);
            },
          ),
      ],
    );
  }
}

class _NoFrameTile extends StatefulWidget {
  const _NoFrameTile({
    super.key,
    required this.selected,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final bool selected;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<_NoFrameTile> createState() => _NoFrameTileState();
}

class _NoFrameTileState extends State<_NoFrameTile> {
  bool _hovered = false;
  bool _focused = false;

  bool get _interactive => !widget.selected && !widget.disabled && !widget.busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: _interactive,
      enabled: _interactive,
      selected: widget.selected,
      label: widget.selected
          ? 'No Frame. Selected.'
          : 'No Frame. Unequip avatar frame.',
      child: FocusableActionDetector(
        enabled: _interactive,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_interactive) widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) {
            if (_interactive) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _interactive ? widget.onTap : null,
            child: Tooltip(
              message: 'No Frame',
              child: _tileShell(
                context: context,
                selected: widget.selected,
                hovered: _hovered || _focused,
                locked: false,
                child: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : Icon(
                        FluentIcons.blocked2,
                        size: 18,
                        color: context.elixTextSecondary,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FrameTile extends StatefulWidget {
  const _FrameTile({
    super.key,
    required this.border,
    required this.unlocked,
    required this.selected,
    required this.busy,
    required this.actionsDisabled,
    required this.onSelect,
  });

  final ProfileBorderDefinition border;
  final bool unlocked;
  final bool selected;
  final bool busy;
  final bool actionsDisabled;
  final VoidCallback onSelect;

  @override
  State<_FrameTile> createState() => _FrameTileState();
}

class _FrameTileState extends State<_FrameTile> {
  bool _hovered = false;
  bool _focused = false;

  bool get _interactive =>
      widget.unlocked &&
      !widget.selected &&
      !widget.busy &&
      !widget.actionsDisabled;

  Color get _accent => Color(widget.border.primaryColorValue);

  @override
  Widget build(BuildContext context) {
    final label = widget.unlocked
        ? '${widget.border.displayName}. ${widget.border.rarityLabel}.'
              '${widget.selected ? ' Selected.' : ' Equip avatar frame.'}'
        : '${widget.border.displayName}. Locked.';

    return Semantics(
      button: _interactive,
      enabled: _interactive,
      selected: widget.selected,
      label: label,
      child: FocusableActionDetector(
        enabled: _interactive,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_interactive) widget.onSelect();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) {
            if (_interactive) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _interactive ? widget.onSelect : null,
            child: Tooltip(
              message:
                  '${widget.border.displayName} · ${widget.border.rarityLabel}',
              child: Opacity(
                opacity: widget.unlocked ? 1 : 0.55,
                child: widget.unlocked
                    ? _tileShell(
                        context: context,
                        selected: widget.selected,
                        hovered: _hovered || _focused,
                        locked: false,
                        accent: _accent,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ProfileBorderFrame(
                              size: 36,
                              equippedBorderId: widget.border.id,
                              animate: widget.selected && widget.unlocked,
                              child: ColoredBox(
                                color: context.isDarkTheme
                                    ? AppColors.cardSurface
                                    : AppColors.cardSurfaceLight,
                                child: Center(
                                  child: Text(
                                    'FL',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: context.elixTextPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (widget.busy)
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: ProgressRing(strokeWidth: 2),
                                ),
                              ),
                          ],
                        ),
                      )
                    : ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: _tileShell(
                          context: context,
                          selected: widget.selected,
                          hovered: _hovered || _focused,
                          locked: true,
                          accent: _accent,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ProfileBorderFrame(
                                size: 36,
                                equippedBorderId: widget.border.id,
                                animate: false,
                                child: ColoredBox(
                                  color: context.isDarkTheme
                                      ? AppColors.cardSurface
                                      : AppColors.cardSurfaceLight,
                                  child: Center(
                                    child: Text(
                                      'FL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: context.elixTextPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Icon(
                                FluentIcons.lock,
                                size: 14,
                                color: context.elixTextSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _tileShell({
  required BuildContext context,
  required bool selected,
  required bool hovered,
  required bool locked,
  required Widget child,
  Color? accent,
}) {
  final borderColor = selected
      ? AppColors.primary.withValues(alpha: 0.85)
      : hovered && !locked
      ? (accent ?? AppColors.accent).withValues(alpha: 0.55)
      : context.elixBorder.withValues(alpha: 0.75);

  return AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: 64,
    height: 72,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: selected
          ? AppColors.primary.withValues(
              alpha: context.isDarkTheme ? 0.14 : 0.08,
            )
          : context.elixCardSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: borderColor,
        width: selected || hovered ? 1.6 : 1,
      ),
      boxShadow: [
        if (selected)
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
      ],
    ),
    child: Center(child: child),
  );
}
