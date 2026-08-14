import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/training_prop.dart';
import '../movements_presentation.dart';

const _kCardRadius = 16.0;
const _kHeroHeight = 152.0;

class MovementCard extends StatefulWidget {
  const MovementCard({
    super.key,
    required this.movement,
    required this.sessionCount,
    required this.averageRubricTotal,
  });

  final Movement movement;
  final int sessionCount;

  /// Assessment V2 rubric average (0..12), or null without rubric sessions.
  final double? averageRubricTotal;

  @override
  State<MovementCard> createState() => _MovementCardState();
}

class _MovementCardState extends State<MovementCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _ctaHovered = false;
  final Map<TrainingProp, bool> _propHovered = {};
  final Map<TrainingProp, bool> _propFocused = {};
  bool _activating = false;

  bool get _enabled => widget.movement.enabled;
  bool get _practiced => widget.sessionCount > 0;

  /// Props this movement can be practiced with, per movement metadata.
  List<TrainingProp> get _supportedProps => widget.movement.supportedProps;

  /// True when the movement offers a choice between multiple props, shown
  /// as separate action chips rather than a single call-to-action button.
  bool get _hasPropChoice => _supportedProps.length > 1;

  /// The single prop used when the movement does not offer a choice.
  TrainingProp get _singleProp =>
      _supportedProps.length == 1 ? _supportedProps.first : TrainingProp.bottle;

  /// True when the movement's one fixed prop is not the default Bottle,
  /// e.g. a movement that always requires Bottle + Cocktail Shaker.
  bool get _requiresFixedNonDefaultProp =>
      !_hasPropChoice && _singleProp != TrainingProp.bottle;

  Color get _accent => difficultyAccentColor(widget.movement.difficulty);

  String get _statusLabel {
    if (!_enabled) return 'Locked';
    if (_practiced) return 'Practiced';
    return 'New';
  }

  String get _actionLabel {
    if (!_enabled) return 'Locked';
    if (_hasPropChoice) return 'Choose a prop';
    if (_requiresFixedNonDefaultProp) {
      return 'Start with ${_singleProp.displayLabel}';
    }
    if (_practiced) return 'Practice again';
    return 'Start practice';
  }

  void _startPractice([TrainingProp? prop]) {
    if (!_enabled || _activating) return;
    _activating = true;
    try {
      if (!mounted) return;
      final resolvedProp = prop ?? _singleProp;
      final encoded = Uri.encodeComponent(widget.movement.name);
      context.go(
        '/practice?movement=$encoded'
        '&difficulty=${widget.movement.difficulty}'
        '&prop=${resolvedProp.protocolValue}',
      );
    } finally {
      _activating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _enabled;
    final cardInteractive = interactive && !_hasPropChoice;
    final active = interactive && (_hovered || _focused);
    final isDark = context.isDarkTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          button: cardInteractive,
          enabled: interactive,
          label: '${widget.movement.name}. $_actionLabel',
          child: FocusableActionDetector(
            enabled: cardInteractive,
            onShowHoverHighlight: (hovered) {
              if (!interactive) return;
              setState(() => _hovered = hovered);
            },
            onShowFocusHighlight: (focused) {
              setState(() => _focused = focused);
            },
            mouseCursor: interactive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (cardInteractive) _startPractice();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: cardInteractive ? _startPractice : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                transformAlignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(0, 0, active ? 1.015 : 1)
                  ..setEntry(1, 1, active ? 1.015 : 1)
                  ..setTranslationRaw(0, active ? -4 : 0, 0),
                decoration: BoxDecoration(
                  color: context.elixCardSurface,
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  border: Border.all(
                    color: active
                        ? _accent.withValues(alpha: isDark ? 0.55 : 0.45)
                        : context.elixBorder.withValues(
                            alpha: isDark ? 0.7 : 1,
                          ),
                    width: _focused ? 1.6 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: active
                          ? _accent.withValues(alpha: isDark ? 0.24 : 0.18)
                          : context.elixBorder.withValues(
                              alpha: isDark ? 0.32 : 0.45,
                            ),
                      blurRadius: active ? 14 : 8,
                      spreadRadius: active ? 1 : 0,
                      offset: Offset(0, active ? 6 : 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  child: _buildTileLayout(
                    context,
                    pinActions: constraints.hasBoundedHeight,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTileLayout(BuildContext context, {required bool pinActions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHero(context),
        if (pinActions)
          Expanded(child: _buildCardBody(context, pinActions: true))
        else
          _buildCardBody(context, pinActions: false),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    return SizedBox(
      height: _kHeroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accent.withValues(alpha: 0.18),
                  _accent.withValues(alpha: 0.04),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: _accent.withValues(alpha: 0.18)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: MovementImage(
              movementName: widget.movement.name,
              size: 132,
              paddingFactor: 0.015,
              alignment: Alignment.bottomCenter,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _StatusBadge(
              label: _statusLabel,
              color: _statusColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBody(BuildContext context, {required bool pinActions}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoColumn(context),
          if (pinActions) const Spacer() else const SizedBox(height: 16),
          if (_hasPropChoice && _enabled)
            _buildPropChoiceActions(context)
          else
            _ActionButton(
              label: _actionLabel,
              enabled: _enabled,
              accent: _accent,
              fullWidth: true,
              hovered: _ctaHovered,
              onHoverChanged: (hovered) {
                if (_enabled) setState(() => _ctaHovered = hovered);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.movement.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          widget.movement.description,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: context.elixTextSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_buildMetadata(context) != null) ...[
          const SizedBox(height: 10),
          _buildMetadata(context)!,
        ],
      ],
    );
  }

  Color _statusColor(BuildContext context) {
    if (!_enabled) return context.elixTextSecondary;
    if (_practiced) return AppColors.success;
    return AppColors.accent;
  }

  Widget? _buildMetadata(BuildContext context) {
    final chips = <Widget>[];
    if (widget.movement.requiresHandsDetection) {
      chips.add(
        _MetaChip(
          icon: FluentIcons.hands_free,
          label: 'Hands tracking',
          color: context.elixTextSecondary,
        ),
      );
    }
    if (!_enabled) {
      chips.add(
        _MetaChip(
          icon: FluentIcons.lock,
          label: 'Coming soon',
          color: context.elixTextSecondary,
        ),
      );
    } else if (!_practiced) {
      chips.add(
        _MetaChip(
          icon: FluentIcons.education,
          label: 'Ready to learn',
          color: context.elixTextSecondary,
        ),
      );
    } else {
      chips.add(
        _MetaChip(
          icon: FluentIcons.history,
          label:
              '${widget.sessionCount} session${widget.sessionCount == 1 ? '' : 's'}',
          color: context.elixTextSecondary,
        ),
      );
      chips.add(
        _MetaChip(
          icon: FluentIcons.completed,
          label: widget.averageRubricTotal == null
              ? 'No rubric result yet'
              : 'Average rubric ${widget.averageRubricTotal!.round()} / 12',
          color: context.elixTextSecondary,
        ),
      );
    }

    if (chips.isEmpty) return null;

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  String _emojiForProp(TrainingProp prop) {
    return switch (prop) {
      TrainingProp.bottle => '🍾',
      TrainingProp.shaker => '🍸',
      TrainingProp.bottleAndShaker => '🍾🍸',
    };
  }

  Widget _buildPropChoiceActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Practice with',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _supportedProps.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _PropActionChip(
            emoji: _emojiForProp(_supportedProps[i]),
            label: _supportedProps[i].displayLabel,
            enabled: true,
            accent: _accent,
            hovered: _propHovered[_supportedProps[i]] ?? false,
            focused: _propFocused[_supportedProps[i]] ?? false,
            onHoverChanged: (hovered) {
              setState(() => _propHovered[_supportedProps[i]] = hovered);
            },
            onFocusChanged: (focused) {
              setState(() => _propFocused[_supportedProps[i]] = focused);
            },
            onTap: () => _startPractice(_supportedProps[i]),
            semanticLabel: 'Practice with ${_supportedProps[i].displayLabel}',
          ),
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: context.elixCardSurface.withValues(
              alpha: context.isDarkTheme ? 0.62 : 0.72,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.38)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.elixBorder.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.accent,
    required this.fullWidth,
    required this.hovered,
    required this.onHoverChanged,
  });

  final String label;
  final bool enabled;
  final Color accent;
  final bool fullWidth;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final fill = enabled
        ? accent.withValues(
            alpha: hovered
                ? (context.isDarkTheme ? 0.24 : 0.18)
                : (context.isDarkTheme ? 0.14 : 0.10),
          )
        : context.elixBorder.withValues(alpha: 0.35);

    return MouseRegion(
      onEnter: (_) {
        if (enabled) onHoverChanged(true);
      },
      onExit: (_) => onHoverChanged(false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth ? null : const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? accent.withValues(alpha: 0.40)
                : context.elixBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? context.elixTextPrimary
                      : context.elixTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                transform: Matrix4.translationValues(hovered ? 3.0 : 0.0, 0, 0),
                child: Icon(
                  FluentIcons.chrome_back_mirrored,
                  size: 10,
                  color: context.elixTextPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PropActionChip extends StatelessWidget {
  const _PropActionChip({
    required this.emoji,
    required this.label,
    required this.enabled,
    required this.accent,
    required this.hovered,
    required this.focused,
    required this.onHoverChanged,
    required this.onFocusChanged,
    required this.onTap,
    required this.semanticLabel,
  });

  final String emoji;
  final String label;
  final bool enabled;
  final Color accent;
  final bool hovered;
  final bool focused;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onFocusChanged;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fill = enabled
        ? accent.withValues(
            alpha: hovered
                ? (context.isDarkTheme ? 0.24 : 0.18)
                : (context.isDarkTheme ? 0.14 : 0.10),
          )
        : context.elixBorder.withValues(alpha: 0.35);

    final chip = Semantics(
      button: enabled,
      enabled: enabled,
      label: semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowHoverHighlight: (value) {
          if (enabled) onHoverChanged(value);
        },
        onShowFocusHighlight: (value) {
          if (enabled) onFocusChanged(value);
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: enabled
            ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onTap();
                    return null;
                  },
                ),
              }
            : const <Type, Action<Intent>>{},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: focused ? 0.75 : 0.40)
                    : context.elixBorder,
                width: focused ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? context.elixTextPrimary
                              : context.elixTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return chip;
  }
}
