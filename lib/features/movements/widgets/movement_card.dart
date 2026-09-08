import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/progression/practice_variant.dart';
import '../../../core/progression/progression_access.dart';
import '../../../core/progression/progression_catalog.dart';
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

class _MovementCardState extends State<MovementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _interactionController;
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  final Map<TrainingProp, bool> _propHovered = {};
  final Map<TrainingProp, bool> _propFocused = {};
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

  /// A movement identity is hidden only when every catalog-supported prop is
  /// personally locked. Missing or loading providers deliberately retain the
  /// normal card so they cannot briefly conceal or reveal content incorrectly.
  _MysteryState _mysteryState() {
    if (!_enabled || _supportedProps.isEmpty) {
      return const _MysteryState(isLocked: false);
    }
    final accesses = [for (final prop in _supportedProps) _accessFor(prop)];
    if (accesses.any(
      (access) => access != ProgressionAccessResult.personalLocked,
    )) {
      return const _MysteryState(isLocked: false);
    }
    final levels = [
      for (final prop in _supportedProps)
        requiredLevelFor(
          PracticeVariant(
            movementName: widget.movement.name,
            trainingProp: prop,
          ),
        ),
    ].whereType<int>();
    if (levels.isEmpty) return const _MysteryState(isLocked: false);
    return _MysteryState(
      isLocked: true,
      unlockLevel: levels.reduce((first, next) => first < next ? first : next),
    );
  }

  String _actionLabelFor(TrainingProp prop, ProgressionAccessResult? access) {
    if (!_enabled) return 'Locked';
    if (access == null) {
      if (_requiresFixedNonDefaultProp && prop == _singleProp) {
        return 'Start with ${prop.displayLabel}';
      }
      final tutorial = Provider.of<TutorialProgressService?>(
        context,
        listen: false,
      );
      // Standalone cards (including legacy widget tests) retain the original
      // practice wording. In the app, the router still enforces the lesson gate.
      if (tutorial == null) {
        if (_hasPropChoice) return 'Ready';
        return _practiced ? 'Practice again' : 'Start practice';
      }
      if (tutorial.hasCompletedLesson(widget.movement.name, prop)) {
        if (_hasPropChoice) {
          return _practiced ? 'Practice again' : 'Ready';
        }
        return _practiced ? 'Practice again' : 'Start practice';
      }
      return 'Learn first';
    }
    switch (access) {
      case ProgressionAccessResult.personalReady:
        if (_hasPropChoice) {
          return _practiced ? 'Practice again' : 'Ready';
        }
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

  String _actionLabel(BuildContext context) {
    if (!_enabled) return 'Locked';
    if (_hasPropChoice) return 'Choose a prop';
    return _actionLabelFor(_singleProp, _accessFor(_singleProp));
  }

  bool _canActivate(ProgressionAccessResult? access) {
    if (!_enabled) return false;
    if (access == null) return true;
    return access == ProgressionAccessResult.personalLearn ||
        access == ProgressionAccessResult.personalReady;
  }

  void _activate([TrainingProp? prop]) {
    if (!_enabled || _activating) return;
    final resolvedProp = prop ?? _singleProp;
    final access = _accessFor(resolvedProp, listen: false);
    if (!_canActivate(access)) return;
    _activating = true;
    try {
      if (!mounted) return;
      final encoded = Uri.encodeComponent(widget.movement.name);
      if (access == ProgressionAccessResult.personalLearn) {
        context.go(
          '/learn/movement/$encoded'
          '?difficulty=${widget.movement.difficulty}'
          '&prop=${resolvedProp.protocolValue}',
        );
        return;
      }
      context.go(
        '/practice?movement=$encoded'
        '&difficulty=${widget.movement.difficulty}'
        '&prop=${resolvedProp.protocolValue}',
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
    final singleAccess = _hasPropChoice ? null : _accessFor(_singleProp);
    final mystery = _mysteryState();
    final interactive = _enabled && !mystery.isLocked;
    final cardInteractive =
        interactive && !_hasPropChoice && _canActivate(singleAccess);
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
          enabled: interactive,
          label: mystery.isLocked
              ? 'Mystery movement. Locked. Unlocks at Level ${mystery.unlockLevel}.'
              : '${widget.movement.name}. $_statusLabel. $statsLabel. ${_actionLabel(context)}',
          child: FocusableActionDetector(
            enabled: cardInteractive,
            onShowFocusHighlight: _setFocused,
            mouseCursor: interactive
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
                  final lift = reduceMotion ? 0.0 : 7 * t;
                  final scale = reduceMotion
                      ? 1.0
                      : (_pressed ? 0.992 : 1 + (0.015 * t));
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
                      color: highContrast ? highContrastSurface : null,
                      gradient: highContrast
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.alphaBlend(
                                  _accent.withValues(
                                    alpha: (isDark ? 0.18 : 0.11) + (0.04 * t),
                                  ),
                                  baseSurface,
                                ),
                                Color.alphaBlend(
                                  AppColors.accent.withValues(
                                    alpha: isDark ? 0.08 : 0.045,
                                  ),
                                  baseSurface,
                                ),
                                Color.alphaBlend(
                                  _accent.withValues(
                                    alpha: isDark ? 0.10 : 0.06,
                                  ),
                                  baseSurface,
                                ),
                              ],
                              stops: const [0, 0.55, 1],
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
                                0.22 + (0.48 * t),
                              )!,
                        width: highContrast || _focused ? 2 : 1,
                      ),
                      boxShadow: highContrast
                          ? const []
                          : [
                              BoxShadow(
                                color: const Color(
                                  0xFF000000,
                                ).withValues(alpha: isDark ? 0.42 : 0.12),
                                blurRadius: 14 + (10 * t),
                                offset: Offset(0, 7 + (4 * t)),
                              ),
                              BoxShadow(
                                color: _accent.withValues(
                                  alpha: (isDark ? 0.22 : 0.13) * t,
                                ),
                                blurRadius: 28,
                                spreadRadius: -6,
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
          onEnter: (_) => _setHovered(true),
          onExit: (_) {
            _setHovered(false);
            _setPressed(false);
          },
          cursor: interactive
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
              color: highContrast
                  ? Color.alphaBlend(
                      _accent.withValues(
                        alpha: context.isDarkTheme ? 0.34 : 0.22,
                      ),
                      context.elixCardSurface,
                    )
                  : null,
              gradient: highContrast
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _accent.withValues(alpha: 0.44),
                        AppColors.accent.withValues(alpha: 0.16),
                        _accent.withValues(alpha: 0.08),
                      ],
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
          if (!highContrast && !reduceMotion)
            IgnorePointer(
              child: Opacity(
                opacity: interactionValue * 0.28,
                child: Transform.translate(
                  offset: Offset(150 * (interactionValue - 0.5), 0),
                  child: Transform.rotate(
                    angle: -0.32,
                    child: Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 42,
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
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
          else if (_hasPropChoice && _enabled)
            _buildPropChoiceActions(context)
          else
            _ActionButton(
              label: _actionLabel(context),
              enabled: _enabled && _canActivate(_accessFor(_singleProp)),
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
          Builder(
            builder: (context) {
              final prop = _supportedProps[i];
              final access = _accessFor(prop);
              final canActivate = _canActivate(access);
              final status = _actionLabelFor(prop, access);
              return _PropActionChip(
                emoji: _emojiForProp(prop),
                label: prop.displayLabel,
                statusLabel: status,
                enabled: canActivate,
                accent: _accent,
                hovered: _propHovered[prop] ?? false,
                focused: _propFocused[prop] ?? false,
                onHoverChanged: (hovered) {
                  setState(() => _propHovered[prop] = hovered);
                },
                onFocusChanged: (focused) {
                  setState(() => _propFocused[prop] = focused);
                  _setFocused(_propFocused.values.any((value) => value));
                },
                onPressedChanged: _setPressed,
                onTap: () => _activate(prop),
                semanticLabel: canActivate
                    ? '$status with ${prop.displayLabel}'
                    : '${prop.displayLabel}. $status',
              );
            },
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
    if (context.isHighContrast) return badge;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: badge,
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
        color: !enabled
            ? context.elixBorder.withValues(alpha: highContrast ? 1 : 0.35)
            : highContrast
            ? context.elixCardSurface
            : null,
        gradient: enabled && active && !highContrast
            ? LinearGradient(colors: [accent, AppColors.accent])
            : null,
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
                    ? (active && !highContrast
                          ? Colors.white
                          : context.elixTextPrimary)
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
                color: active && !highContrast
                    ? Colors.white
                    : context.elixTextPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PropActionChip extends StatelessWidget {
  const _PropActionChip({
    required this.emoji,
    required this.label,
    required this.statusLabel,
    required this.enabled,
    required this.accent,
    required this.hovered,
    required this.focused,
    required this.onHoverChanged,
    required this.onFocusChanged,
    required this.onPressedChanged,
    required this.onTap,
    required this.semanticLabel,
  });

  final String emoji;
  final String label;
  final String statusLabel;
  final bool enabled;
  final Color accent;
  final bool hovered;
  final bool focused;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onFocusChanged;
  final ValueChanged<bool> onPressedChanged;
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
          onTapDown: enabled ? (_) => onPressedChanged(true) : null,
          onTapUp: enabled ? (_) => onPressedChanged(false) : null,
          onTapCancel: enabled ? () => onPressedChanged(false) : null,
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
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: context.elixTextSecondary,
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
