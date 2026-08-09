import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../progress/training_recommendation.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;

/// Dashboard hero: greeting, brand headline, session status, and CTAs.
///
/// Primary action starts the recommended guided practice session.
/// Secondary action opens the movement catalog.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.firstName,
    required this.greeting,
    required this.sessionCount,
    required this.recommendation,
  });

  final String firstName;
  final String greeting;
  final int sessionCount;
  final TrainingRecommendation? recommendation;

  static String practiceRouteFor(TrainingRecommendation? recommendation) {
    final mastery = recommendation?.recommended;
    if (mastery == null) return '/movements';
    final encoded = Uri.encodeComponent(mastery.movement.name);
    return '/practice?movement=$encoded&difficulty=${mastery.movement.difficulty}';
  }

  void _startRecommended(BuildContext context) {
    context.go(practiceRouteFor(recommendation));
  }

  void _exploreMovements(BuildContext context) {
    context.go('/movements');
  }

  String get _primaryLabel {
    final name = recommendation?.recommended.movement.name;
    if (name == null || name.isEmpty) return 'Start Recommended Practice';
    return 'Practice $name';
  }

  @override
  Widget build(BuildContext context) {
    // Content-sized height (not a fixed SizedBox): long primary labels can wrap
    // the CTA row, and a fixed 260px box was overflowing by ~25px in practice.
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 250),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/banner.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.5, 0.85, 1.0],
                      colors: [
                        Color(0xF213091F),
                        Color(0xCC13091F),
                        Color(0x6613091F),
                        Color(0x3313091F),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wideEnoughForFullLabel = constraints.maxWidth >= 780;
                    final showQuote = constraints.maxWidth >= 720;
                    final headlineSize = constraints.maxWidth < 700
                        ? 36.0
                        : 40.0;
                    final primaryLabel = wideEnoughForFullLabel
                        ? _primaryLabel
                        : 'Start Recommended Practice';

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xCCFFFFFF),
                            ),
                            children: [
                              TextSpan(text: '$greeting, '),
                              TextSpan(
                                text: firstName,
                                style: const TextStyle(
                                  color: AppColors.primarySoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Train. Flip. Master.',
                          style: TextStyle(
                            fontSize: headlineSize,
                            fontWeight: FontWeight.w900,
                            color: _pink,
                            height: 1.05,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your journey to flair excellence starts here.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SessionStatusChip(sessionCount: sessionCount),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _HeroActionButton(
                              label: primaryLabel,
                              icon: FluentIcons.play_solid,
                              primary: true,
                              onPressed: () => _startRecommended(context),
                            ),
                            _HeroActionButton(
                              label: 'Explore Movements',
                              icon: FluentIcons.grid_view_medium,
                              onPressed: () => _exploreMovements(context),
                            ),
                          ],
                        ),
                        if (showQuote) ...[
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '“Great flair starts with great practice.”',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Color(0xDDFFFFFF),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionStatusChip extends StatelessWidget {
  const _SessionStatusChip({required this.sessionCount});

  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.timer,
            size: 11,
            color: AppColors.primarySoft.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 6),
          Text(
            '$sessionCount Sessions Completed',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xEEFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: widget.primary
          ? LinearGradient(
              colors: _hovered
                  ? const [AppColors.primarySoft, AppColors.accentSoft]
                  : const [_pink, _purple],
            )
          : null,
      color: widget.primary
          ? null
          : Colors.white.withValues(alpha: _hovered ? 0.16 : 0.08),
      border: widget.primary
          ? null
          : Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.45 : 0.25),
            ),
      boxShadow: widget.primary
          ? [
              BoxShadow(
                color: _pink.withValues(alpha: _hovered ? 0.28 : 0.16),
                blurRadius: _hovered ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 12, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: widget.primary
            ? content
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: content,
                ),
              ),
      ),
    );
  }
}
