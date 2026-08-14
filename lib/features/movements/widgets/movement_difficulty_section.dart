import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../movements_presentation.dart';
import 'movement_card.dart';

class MovementDifficultySection extends StatefulWidget {
  const MovementDifficultySection({
    super.key,
    required this.difficulty,
    required this.movements,
    required this.stats,
  });

  final String difficulty;
  final List<Movement> movements;
  final Map<String, MovementStats> stats;

  @override
  State<MovementDifficultySection> createState() =>
      _MovementDifficultySectionState();
}

class _MovementDifficultySectionState extends State<MovementDifficultySection>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 240);
  static const _threeColumnBreakpoint = 1050.0;
  static const _twoColumnBreakpoint = 680.0;
  // Sized for the densest card variant (two prop actions) so every card keeps
  // the same footprint without clipping or moving neighboring content.
  static const _cardHeight = 448.0;
  // Keeps the next row clear even while the card above is lifted on hover.
  static const _cardRowGap = 32.0;
  // Leaves visual separation below the level banner after a card lifts on hover.
  static const _sectionToGridGap = 32.0;

  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;
  bool _expanded = true;
  bool _headerFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _animationDuration,
      vsync: this,
      value: 1,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = _expanded ? 1 : 0;
      return;
    }
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccentColor(widget.difficulty);
    final practiced = widget.movements
        .where((m) => (widget.stats[m.name]?.count ?? 0) > 0)
        .length;
    final progress = widget.movements.isEmpty
        ? 0.0
        : practiced / widget.movements.length;
    final sectionTitle = difficultySectionTitle(widget.difficulty);
    final semanticsAction = _expanded ? 'Collapse' : 'Expand';
    final highContrast = context.isHighContrast;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label:
              '$semanticsAction $sectionTitle, '
              '$practiced of ${widget.movements.length} practiced',
          child: FocusableActionDetector(
            onShowFocusHighlight: (focused) {
              setState(() => _headerFocused = focused);
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _toggleExpanded();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              onTap: _toggleExpanded,
              child: AnimatedContainer(
                key: const ValueKey('difficulty-banner'),
                duration: reduceMotion ? Duration.zero : _animationDuration,
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: highContrast
                      ? context.elixCardSurface
                      : accent.withValues(
                          alpha: context.isDarkTheme ? 0.09 : 0.06,
                        ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _headerFocused || highContrast
                        ? (highContrast ? context.elixBorder : accent)
                        : accent.withValues(alpha: 0.30),
                    width: _headerFocused || highContrast ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sectionTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: context.elixTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '$practiced of ${widget.movements.length} practiced',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.elixTextSecondary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: SizedBox(
                                    height: 4,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Container(
                                          color: context.elixBorder.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                        FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: progress.clamp(0.0, 1.0),
                                          child: Container(color: accent),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                '${(progress * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: reduceMotion
                          ? Duration.zero
                          : _animationDuration,
                      curve: Curves.easeInOut,
                      child: Icon(
                        FluentIcons.chevron_down,
                        size: 14,
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ClipRect(
          child: SizeTransition(
            sizeFactor: _expandAnimation,
            alignment: Alignment.topLeft,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: _sectionToGridGap),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth >= _threeColumnBreakpoint
                        ? 3
                        : constraints.maxWidth >= _twoColumnBreakpoint
                        ? 2
                        : 1;

                    final columnChildren = List.generate(
                      columns,
                      (_) => <Widget>[],
                    );
                    for (
                      var index = 0;
                      index < widget.movements.length;
                      index++
                    ) {
                      final movement = widget.movements[index];
                      final children = columnChildren[index % columns];
                      if (children.isNotEmpty) {
                        children.add(const SizedBox(height: _cardRowGap));
                      }
                      children.add(
                        SizedBox(
                          width: double.infinity,
                          height: _cardHeight,
                          child: MovementCard(
                            movement: movement,
                            sessionCount:
                                widget.stats[movement.name]?.count ?? 0,
                            averageRubricTotal:
                                widget.stats[movement.name]?.averageRubricTotal,
                          ),
                        ),
                      );
                    }

                    // Cards scale on hover. Reserve a small outer gutter so
                    // the first and last cards stay inside the content lane
                    // instead of painting into the navigation sidebar.
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        key: const ValueKey('movement-grid'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < columns; index++) ...[
                            if (index > 0) const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: columnChildren[index],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
