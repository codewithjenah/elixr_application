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
  static const _animationDuration = Duration(milliseconds: 200);

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
                duration: _animationDuration,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: _headerFocused
                      ? Border.all(
                          color: accent.withValues(alpha: 0.55),
                          width: 1.5,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
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
                      duration: _animationDuration,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  for (var i = 0; i < widget.movements.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    MovementCard(
                      movement: widget.movements[i],
                      sessionCount:
                          widget.stats[widget.movements[i].name]?.count ?? 0,
                      averageRubricTotal: widget
                          .stats[widget.movements[i].name]
                          ?.averageRubricTotal,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
