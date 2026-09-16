import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/progression/practice_variant.dart';
import '../../../core/progression/progression_access.dart';
import '../../../core/progression/progression_catalog.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/training_prop.dart';
import '../../../services/trainee_progression_service.dart';
import '../../../services/tutorial_progress_service.dart';
import '../movements_presentation.dart';

const _kCardRadius = 20.0;
const _kHeroHeight = 176.0;

class _MysteryState {
  const _MysteryState({required this.isLocked, this.unlockLevel});

  final bool isLocked;
  final int? unlockLevel;
}

class MovementCard extends StatefulWidget {
  const MovementCard({
    super.key,
    required this.movement,
    required this.prop,
    required this.sessionCount,
    required this.averageRubricTotal,
  });

  final Movement movement;
  final TrainingProp prop;
  final int sessionCount;

  /// Assessment V2 rubric average (0..12), or null without rubric sessions.
  final double? averageRubricTotal;

  @override
  State<MovementCard> createState() => _MovementCardState();
}

class _MovementCardState extends State<MovementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _interactionController;
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    _interactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _interactionController.dispose();
    super.dispose();
  }

  bool get _enabled => widget.movement.enabled;
  bool get _practiced => widget.sessionCount > 0;

  Color get _accent => difficultyAccentColor(widget.movement.difficulty);

  String get _statusLabel {
    if (!_enabled) return 'Locked';
    if (_practiced) return 'Practiced';
    return 'New';
  }

  /// Null when progression providers are absent (legacy widget tests).
  ProgressionAccessResult? _accessFor(TrainingProp prop, {bool listen = true}) {
    final progression = Provider.of<TraineeProgressionService?>(
      context,
      listen: listen,
    );
    final tutorial = Provider.of<TutorialProgressService?>(
      context,
      listen: listen,
    );
    if (progression == null || tutorial == null) return null;
    return evaluatePersonal(
      variant: PracticeVariant(
        movementName: widget.movement.name,
        trainingProp: prop,
      ),
      currentLevel: progression.currentLevelOrNull,
      tutorialCompleted: tutorial.isInitialized
          ? tutorial.hasCompletedLesson(widget.movement.name, prop)
          : null,
    );
  }

  /// A movement identity is hidden until its earliest prop variant unlocks.
  /// Missing or loading providers retain the normal card for compatibility
  /// with standalone cards and to avoid transient loading-state flashes.
  _MysteryState _mysteryState() {
    if (!_enabled) {
      return const _MysteryState(isLocked: false);
    }
    final progression = Provider.of<TraineeProgressionService?>(
      context,
      listen: true,
    );
    final currentLevel = progression?.currentLevelOrNull;
    if (currentLevel == null ||
        isMovementIdentityRevealed(widget.movement.name, currentLevel)) {
      return const _MysteryState(isLocked: false);
    }
    final unlockLevel = earliestRequiredLevelForMovement(widget.movement.name);
    if (unlockLevel == null) return const _MysteryState(isLocked: false);
    return _MysteryState(isLocked: true, unlockLevel: unlockLevel);
  }

  String _actionLabelFor(TrainingProp prop, ProgressionAccessResult? access) {
    if (!_enabled) return 'Locked';
    if (access == null) {
      if (prop == TrainingProp.bottleAndShaker) {
        return 'Start with ${prop.displayLabel}';
      }
      final tutorial = Provider.of<TutorialProgressService?>(
        context,
        listen: false,
      );
      // Standalone cards (including legacy widget tests) retain the original
      // practice wording. In the app, the router still enforces the lesson gate.
      if (tutorial == null) {
        return _practiced ? 'Practice again' : 'Start practice';
      }
      if (tutorial.hasCompletedLesson(widget.movement.name, prop)) {
        return _practiced ? 'Practice again' : 'Start practice';
      }
      return 'Learn first';
    }
    switch (access) {
      case ProgressionAccessResult.personalReady:
        return _practiced ? 'Practice again' : 'Start practice';
      case ProgressionAccessResult.personalLearn:
        return 'Learn first';
      case ProgressionAccessResult.personalLocked:
        final level =
            requiredLevelFor(
              PracticeVariant(
                movementName: widget.movement.name,
                trainingProp: prop,
              ),
            ) ??
            '?';
        return 'Locked · Level $level';
      case ProgressionAccessResult.personalLoading:
        return 'Checking access…';
      case ProgressionAccessResult.invalid:
        return 'Unavailable';
      case ProgressionAccessResult.assignmentLoading:
      case ProgressionAccessResult.assignmentLearn:
      case ProgressionAccessResult.assignmentReady:
        return 'Unavailable';
    }
  }

  String get _actionLabel {
    if (!_enabled) return 'Locked';
    return _actionLabelFor(widget.prop, _accessFor(widget.prop));
  }

  bool _canActivate(ProgressionAccessResult? access) {
    if (!_enabled) return false;
    if (access == null) return true;
    return access == ProgressionAccessResult.personalLearn ||
        access == ProgressionAccessResult.personalReady;
  }

  void _activate() {
    if (!_enabled || _activating) return;
    final access = _accessFor(widget.prop, listen: false);
    if (!_canActivate(access)) return;
    _activating = true;
    try {
      if (!mounted) return;
      if (access == ProgressionAccessResult.personalLearn) {
        context.go(
          AppRoutePaths.movementLesson(
            movement: widget.movement.name,
            difficulty: widget.movement.difficulty,
            prop: widget.prop.protocolValue,
          ),
        );
        return;
      }
      context.go(
        AppRoutePaths.personalPractice(
          movement: widget.movement.name,
          difficulty: widget.movement.difficulty,
          prop: widget.prop.protocolValue,
        ),
      );
    } finally {
      _activating = false;
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _syncInteraction() {
    final active = _enabled && (_hovered || _focused);
    if (_reduceMotion) {
      _interactionController.value = active ? 1 : 0;
    } else if (active) {
      _interactionController.forward();
    } else {
      _interactionController.reverse();
    }
  }

  void _setHovered(bool value) {
    if (!_enabled || _hovered == value) return;
    setState(() => _hovered = value);
    _syncInteraction();
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    _syncInteraction();
  }

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final access = _accessFor(widget.prop);
    final mystery = _mysteryState();
    final cardInteractive =
        _enabled && !mystery.isLocked && _canActivate(access);
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final reduceMotion = _reduceMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        final alwaysRevealMetadata = constraints.maxWidth < 680;
        final statsLabel = _practiced
            ? '${widget.sessionCount} session${widget.sessionCount == 1 ? '' : 's'}, ${widget.averageRubricTotal == null ? 'no rubric result yet' : 'average rubric ${widget.averageRubricTotal!.round()} of 12'}'
            : (_enabled ? 'Ready to learn' : 'Coming soon');
        final card = Semantics(
          button: cardInteractive,
          enabled: cardInteractive,
          excludeSemantics: true,
          label: mystery.isLocked
              ? 'Mystery movement. Locked. Unlocks at Level ${mystery.unlockLevel}.'
              : '${widget.movement.name}. ${widget.prop.displayLabel}. '
                    '${widget.movement.difficulty}. $_statusLabel. '
                    '$statsLabel. $_actionLabel',
          child: FocusableActionDetector(
            enabled: cardInteractive,
            onShowFocusHighlight: _setFocused,
            mouseCursor: cardInteractive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  if (cardInteractive) _activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: cardInteractive ? _activate : null,
              onTapDown: cardInteractive ? (_) => _setPressed(true) : null,
              onTapUp: cardInteractive ? (_) => _setPressed(false) : null,
              onTapCancel: cardInteractive ? () => _setPressed(false) : null,
              child: AnimatedBuilder(
                animation: _interactionController,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(
                    _interactionController.value,
                  );
                  // Keep the catalog calm: hover confirms interactivity
                  // without moving neighboring cards or adding a glow stack.
                  final lift = reduceMotion ? 0.0 : 2 * t;
                  final scale = _pressed && !reduceMotion ? 0.996 : 1.0;
                  final baseSurface = context.elixCardSurface;
                  final highContrastSurface = Color.alphaBlend(
                    _accent.withValues(alpha: isDark ? 0.20 : 0.14),
                    baseSurface,
                  );
                  return AnimatedContainer(
                    key: const ValueKey('movement-card-surface'),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    transformAlignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translateByDouble(0, -lift, 0, 1)
                      ..scaleByDouble(scale, scale, scale, 1),
                    decoration: BoxDecoration(
                      color: highContrast
                          ? highContrastSurface
                          : Color.alphaBlend(
                              _accent.withValues(
                                alpha: (isDark ? 0.07 : 0.035) * t,
                              ),
                              baseSurface,
                            ),
                      gradient: highContrast
                          ? null
                          : LinearGradient(
                              colors: [
                                _accent.withValues(
                                  alpha: isDark ? 0.055 : 0.03,
                                ),
                                _accent.withValues(
                                  alpha: isDark ? 0.018 : 0.01,
                                ),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(_kCardRadius),
                      border: Border.all(
                        color: highContrast
                            ? context.elixBorder
                            : _focused
                            ? _accent
                            : Color.lerp(
                                context.elixBorder,
                                _accent,
                                0.18 + (0.20 * t),
                              )!,
                        width: highContrast || _focused ? 2 : 1,
                      ),
                      boxShadow: highContrast
                          ? const []
                          : [
                              if (t > 0)
                                BoxShadow(
                                  color: const Color(0xFF000000).withValues(
                                    alpha: isDark ? 0.20 * t : 0.08 * t,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                            ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_kCardRadius),
                      child: Opacity(
                        opacity: _enabled || highContrast ? 1 : 0.58,
                        child: mystery.isLocked
                            ? ExcludeSemantics(
                                child: _buildTileLayout(
                                  context,
                                  pinActions: constraints.hasBoundedHeight,
                                  revealMetadata: alwaysRevealMetadata,
                                  interactionValue: t,
                                  mystery: mystery,
                                ),
                              )
                            : _buildTileLayout(
                                context,
                                pinActions: constraints.hasBoundedHeight,
                                revealMetadata: alwaysRevealMetadata,
                                interactionValue: t,
                                mystery: mystery,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        return MouseRegion(
          onEnter: cardInteractive ? (_) => _setHovered(true) : null,
          onExit: (_) {
            _setHovered(false);
            _setPressed(false);
          },
          cursor: cardInteractive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: card,
        );
      },
    );
  }

  Widget _buildTileLayout(
    BuildContext context, {
    required bool pinActions,
    required bool revealMetadata,
    required double interactionValue,
    required _MysteryState mystery,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHero(context, interactionValue, mystery),
        if (pinActions)
          Expanded(
            child: _buildCardBody(
              context,
              pinActions: true,
              revealMetadata: revealMetadata,
              interactionValue: interactionValue,
              mystery: mystery,
            ),
          )
        else
          _buildCardBody(
            context,
            pinActions: false,
            revealMetadata: revealMetadata,
            interactionValue: interactionValue,
            mystery: mystery,
          ),
      ],
    );
  }

  Widget _buildHero(
    BuildContext context,
    double interactionValue,
    _MysteryState mystery,
  ) {
    final highContrast = context.isHighContrast;
    final reduceMotion = _reduceMotion;
    final artwork = Transform.translate(
      offset: Offset(0, reduceMotion ? 0 : -3 * interactionValue),
      child: Transform.scale(
        scale: reduceMotion ? 1 : 1 + (0.055 * interactionValue),
        alignment: Alignment.bottomCenter,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MovementImage(
            movementName: widget.movement.name,
            prop: widget.prop,
            size: 154,
            paddingFactor: 0.01,
            alignment: Alignment.bottomCenter,
          ),
        ),
      ),
    );
    return SizedBox(
      height: _kHeroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: null,
              color: highContrast
                  ? Color.alphaBlend(
                      _accent.withValues(
                        alpha: context.isDarkTheme ? 0.34 : 0.22,
                      ),
                      context.elixCardSurface,
                    )
                  : _accent.withValues(
                      alpha: context.isDarkTheme ? 0.14 : 0.08,
                    ),
              border: Border(
                bottom: BorderSide(color: _accent.withValues(alpha: 0.18)),
              ),
            ),
          ),
          ExcludeSemantics(
            child: mystery.isLocked
                ? ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Opacity(opacity: 0.16, child: artwork),
                  )
                : artwork,
          ),
          if (mystery.isLocked)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF120A22).withValues(alpha: 0.60),
                    const Color(0xFF241036).withValues(alpha: 0.76),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.lock,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'MYSTERY MOVEMENT',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: _StatusBadge(
              label: mystery.isLocked ? 'LOCKED' : _statusLabel,
              color: mystery.isLocked
                  ? context.elixTextSecondary
                  : _statusColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBody(
    BuildContext context, {
    required bool pinActions,
    required bool revealMetadata,
    required double interactionValue,
    required _MysteryState mystery,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoColumn(
            context,
            revealMetadata: revealMetadata,
            interactionValue: interactionValue,
            mystery: mystery,
          ),
          if (pinActions) const Spacer() else const SizedBox(height: 16),
          if (mystery.isLocked)
            _ActionButton(
              label: 'Unlocks at Level ${mystery.unlockLevel}',
              enabled: false,
              accent: _accent,
              fullWidth: true,
              active: false,
              reduceMotion: _reduceMotion,
            )
          else
            _ActionButton(
              label: _actionLabel,
              enabled: _enabled && _canActivate(_accessFor(widget.prop)),
              accent: _accent,
              fullWidth: true,
              active: _hovered || _focused,
              reduceMotion: _reduceMotion,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(
    BuildContext context, {
    required bool revealMetadata,
    required double interactionValue,
    required _MysteryState mystery,
  }) {
    if (mystery.isLocked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '???',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Reach Level ${mystery.unlockLevel} to reveal this movement',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: context.elixTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    final metadata = _buildMetadata(context);
    final visible = revealMetadata || _hovered || _focused;
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
        const SizedBox(height: 7),
        _PropBadge(prop: widget.prop, accent: _accent),
        const SizedBox(height: 7),
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
        if (metadata != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: _reduceMotion
                  ? Duration.zero
                  : Duration(milliseconds: visible ? 260 : 180),
              curve: Curves.easeOutCubic,
              alwaysIncludeSemantics: true,
              child: Transform.translate(
                offset: Offset(
                  0,
                  _reduceMotion || visible ? 0 : 8 * (1 - interactionValue),
                ),
                child: metadata,
              ),
            ),
          ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final chip in chips)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: chip,
              ),
          ],
        );
      },
    );
  }
}

class _PropBadge extends StatelessWidget {
  const _PropBadge({required this.prop, required this.accent});

  final TrainingProp prop;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: context.isDarkTheme ? 0.15 : 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : accent.withValues(alpha: 0.55),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Text(
          prop.displayLabel,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixCardSurface.withValues(
                alpha: context.isDarkTheme ? 0.68 : 0.80,
              ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: context.isHighContrast ? context.elixBorder : color,
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
    return badge;
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
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    required this.active,
    required this.reduceMotion,
  });

  final String label;
  final bool enabled;
  final Color accent;
  final bool fullWidth;
  final bool active;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      width: fullWidth ? double.infinity : null,
      constraints: fullWidth ? null : const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: null,
        color: !enabled
            ? context.elixBorder.withValues(alpha: highContrast ? 1 : 0.35)
            : active && !highContrast
            ? accent.withValues(alpha: context.isDarkTheme ? 0.20 : 0.12)
            : highContrast
            ? context.elixCardSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: enabled ? accent : context.elixBorder,
          width: highContrast ? 2 : 1,
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
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              transform: Matrix4.translationValues(active ? 4.0 : 0.0, 0, 0),
              child: Icon(
                FluentIcons.chrome_back_mirrored,
                size: 10,
                color: context.elixTextPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
