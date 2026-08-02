import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/movement_visuals.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../movements_presentation.dart';

const _kCompactLayoutBreakpoint = 720.0;

class MovementCard extends StatefulWidget {
  const MovementCard({
    super.key,
    required this.movement,
    required this.sessionCount,
    required this.avgScore,
  });

  final Movement movement;
  final int sessionCount;
  final double avgScore;

  @override
  State<MovementCard> createState() => _MovementCardState();
}

class _MovementCardState extends State<MovementCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _ctaHovered = false;
  bool _bottleHovered = false;
  bool _activating = false;

  bool get _enabled => widget.movement.enabled;
  bool get _practiced => widget.sessionCount > 0;
  bool get _isMedium => widget.movement.difficulty == 'Medium';

  Color get _accent => difficultyAccentColor(widget.movement.difficulty);

  String get _statusLabel {
    if (!_enabled) return 'Locked';
    if (_practiced) return 'Practiced';
    return 'New';
  }

  String get _actionLabel {
    if (!_enabled) return 'Locked';
    if (_isMedium) return 'Practice with Bottle';
    if (_practiced) return 'Practice again';
    return 'Start practice';
  }

  void _startPractice() {
    if (!_enabled || _activating) return;
    _activating = true;
    try {
      if (!mounted) return;
      final encoded = Uri.encodeComponent(widget.movement.name);
      // Prop is not included: app_router ignores unused query params and the
      // practice/session stack does not yet carry prop end to end.
      context.go(
        '/practice?movement=$encoded'
        '&difficulty=${widget.movement.difficulty}',
      );
    } finally {
      _activating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _enabled;
    final active = interactive && (_hovered || _focused);
    final isDark = context.isDarkTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _kCompactLayoutBreakpoint;
        return Semantics(
          button: interactive,
          enabled: interactive,
          label: '${widget.movement.name}. $_actionLabel',
          child: FocusableActionDetector(
            enabled: interactive,
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
                  _startPractice();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: interactive ? _startPractice : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, active ? -2.0 : 0.0, 0),
                decoration: BoxDecoration(
                  color: active
                      ? _accent.withValues(alpha: isDark ? 0.06 : 0.04)
                      : context.elixCardSurface,
                  borderRadius: BorderRadius.circular(14),
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
                      color: Colors.black.withValues(
                        alpha: isDark
                            ? (active ? 0.32 : 0.18)
                            : (active ? 0.10 : 0.05),
                      ),
                      blurRadius: active ? 14 : 8,
                      offset: Offset(0, active ? 4 : 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 4, color: _accent),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: compact
                            ? _buildStackedLayout(context)
                            : _buildHorizontalLayout(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHorizontalLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildVisual(context),
        const SizedBox(width: 12),
        Expanded(child: _buildInfoColumn(context)),
        const SizedBox(width: 16),
        SizedBox(
          width: _isMedium && _enabled ? 220 : 184,
          child: _buildPerformanceColumn(context, fullWidthCta: true),
        ),
      ],
    );
  }

  Widget _buildStackedLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVisual(context),
            const SizedBox(width: 12),
            Expanded(child: _buildInfoColumn(context)),
          ],
        ),
        const SizedBox(height: 12),
        _buildPerformanceColumn(context, fullWidthCta: true),
      ],
    );
  }

  Widget _buildVisual(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: context.isDarkTheme ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        MovementVisuals.emojiFor(widget.movement.name),
        style: const TextStyle(fontSize: 24),
      ),
    );
  }

  Widget _buildInfoColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.movement.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(label: _statusLabel, color: _statusColor(context)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          widget.movement.description,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: context.elixTextSecondary,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (_buildMetadata(context) != null) ...[
          const SizedBox(height: 6),
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
    }

    if (chips.isEmpty) return null;

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _buildPerformanceColumn(
    BuildContext context, {
    bool fullWidthCta = false,
  }) {
    return Column(
      crossAxisAlignment: fullWidthCta
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPerformanceStats(context, fullWidth: fullWidthCta),
        const SizedBox(height: 8),
        if (_isMedium && _enabled)
          _buildMediumPropActions(context)
        else
          _ActionButton(
            label: _actionLabel,
            enabled: _enabled,
            accent: _accent,
            fullWidth: fullWidthCta,
            hovered: _ctaHovered,
            onHoverChanged: (hovered) {
              if (_enabled) setState(() => _ctaHovered = hovered);
            },
          ),
      ],
    );
  }

  Widget _buildMediumPropActions(BuildContext context) {
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
        _PropActionChip(
          emoji: '🍾',
          label: 'Bottle',
          enabled: true,
          accent: _accent,
          hovered: _bottleHovered,
          onHoverChanged: (hovered) {
            setState(() => _bottleHovered = hovered);
          },
          onTap: _startPractice,
          semanticLabel: 'Practice with Bottle',
        ),
        const SizedBox(height: 8),
        const _PropActionChip(
          emoji: '🍸',
          label: 'Cocktail Shaker',
          enabled: false,
          accent: AppColors.warning,
          hovered: false,
          onHoverChanged: null,
          onTap: null,
          comingSoon: true,
          semanticLabel:
              'Cocktail Shaker. Coming soon. This option is unavailable.',
        ),
      ],
    );
  }

  Widget _buildPerformanceStats(
    BuildContext context, {
    bool fullWidth = false,
  }) {
    if (!_enabled) {
      return Text(
        'Locked',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.elixTextSecondary,
        ),
      );
    }

    if (!_practiced) {
      return Text(
        'Ready to learn',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.elixTextSecondary,
        ),
      );
    }

    final score = widget.avgScore.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.sessionCount} session${widget.sessionCount == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Average score $score%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            width: fullWidth ? double.infinity : 140,
            child: Stack(
              children: [
                Container(color: context.elixBorder),
                FractionallySizedBox(
                  widthFactor: (widget.avgScore / 100).clamp(0.0, 1.0),
                  child: Container(color: _accent.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
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
    required this.onHoverChanged,
    required this.onTap,
    required this.semanticLabel,
    this.comingSoon = false,
  });

  final String emoji;
  final String label;
  final bool enabled;
  final Color accent;
  final bool hovered;
  final ValueChanged<bool>? onHoverChanged;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool comingSoon;

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
          if (enabled) onHoverChanged?.call(value);
        },
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: enabled
            ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onTap?.call();
                    return null;
                  },
                ),
              }
            : const <Type, Action<Intent>>{},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : () {},
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      if (comingSoon)
                        Text(
                          'Coming soon',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: context.elixTextSecondary,
                          ),
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

    if (!enabled && comingSoon) {
      return Tooltip(message: 'Coming soon', child: chip);
    }
    return chip;
  }
}
