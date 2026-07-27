import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/movement_visuals.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../movements_presentation.dart';
import 'movement_prop_picker.dart';

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
  bool _activating = false;

  bool get _enabled => widget.movement.enabled;
  bool get _practiced => widget.sessionCount > 0;

  Color get _accent => difficultyAccentColor(widget.movement.difficulty);

  String get _actionLabel {
    if (!_enabled) return 'Locked';
    if (_practiced) return 'Practice again';
    return 'Start practice';
  }

  Future<void> _activate() async {
    if (!_enabled || _activating) return;
    _activating = true;
    try {
      var prop = 'bottle';
      if (widget.movement.difficulty == 'Medium') {
        final choice = await showMovementPropPicker(
          context,
          widget.movement.name,
        );
        if (choice == null || !mounted) return;
        prop = choice;
      }
      if (!mounted) return;
      final encoded = Uri.encodeComponent(widget.movement.name);
      context.go(
        '/practice?movement=$encoded'
        '&difficulty=${widget.movement.difficulty}'
        '&prop=$prop',
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
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: interactive ? _activate : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, active ? -2.0 : 0.0, 0),
            decoration: BoxDecoration(
              color: context.elixCardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? (isDark
                          ? context.elixTextSecondary.withValues(alpha: 0.55)
                          : context.elixTextSecondary.withValues(alpha: 0.45))
                    : context.elixBorder.withValues(alpha: isDark ? 0.7 : 1),
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDark
                        ? (active ? 0.36 : 0.22)
                        : (active ? 0.12 : 0.07),
                  ),
                  blurRadius: active ? 16 : 10,
                  offset: Offset(0, active ? 5 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: _accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildIdentity(context),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 32,
                            child: Text(
                              widget.movement.description,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: context.elixTextSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildMetadata(context),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPerformance(context),
                                  const SizedBox(height: 6),
                                  _ActionButton(
                                    label: _actionLabel,
                                    enabled: interactive,
                                    accent: _accent,
                                    onPressed: _activate,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildIdentity(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: context.isDarkTheme ? 0.14 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.28)),
          ),
          child: Text(
            MovementVisuals.emojiFor(widget.movement.name),
            style: const TextStyle(fontSize: 26),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.movement.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              _DifficultyBadge(
                label: widget.movement.difficulty,
                color: _accent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
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

    if (chips.isEmpty) {
      return const SizedBox(height: 22);
    }

    return SizedBox(
      height: 22,
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _buildPerformance(BuildContext context) {
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
        'Not practiced yet',
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

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final Color accent;
  final VoidCallback onPressed;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final fill = enabled
        ? widget.accent.withValues(
            alpha: _hovered
                ? (context.isDarkTheme ? 0.22 : 0.16)
                : (context.isDarkTheme ? 0.14 : 0.10),
          )
        : context.elixBorder.withValues(alpha: 0.35);

    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled
                  ? widget.accent.withValues(alpha: 0.40)
                  : context.elixBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? context.elixTextPrimary
                      : context.elixTextSecondary,
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 6),
                Icon(
                  FluentIcons.chrome_back_mirrored,
                  size: 10,
                  color: context.elixTextPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
