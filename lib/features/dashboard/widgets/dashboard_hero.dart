import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../progress/training_recommendation.dart';

const _pink = AppColors.primary;

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

  /// Content width at which CTAs stay on one compact row.
  static const double _inlineCtaBreakpoint = 620;

  /// Below this, full-width stacked CTAs are acceptable.
  static const double _narrowCtaBreakpoint = 520;

  /// Prefer the named "Practice …" label when the hero content is wide enough.
  static const double _fullPrimaryLabelBreakpoint = 560;

  /// Banner art is ~16:9; a taller hero on wide layouts avoids cropping the subject.
  static const double _bannerWidthToHeight = 3.4;
  static const double _minImageLedHeight = 280.0;
  static const double _maxBannerHeight = 340.0;

  /// Keeps the bartender's face and pour action in frame when cover-cropping.
  static const Alignment _bannerAlignment = Alignment(0.58, -0.38);

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

  String get _fullPrimaryLabel {
    final name = recommendation?.recommended.movement.name;
    if (name == null || name.isEmpty) return 'Start Recommended Practice';
    return 'Practice $name';
  }

  /// Prefer the named practice label when it fits; otherwise use the short fallback.
  String _primaryLabelFor(double contentWidth) {
    final full = _fullPrimaryLabel;
    if (full == 'Start Recommended Practice') return full;
    // Long movement names never get the named label in a constrained CTA area.
    if (full.length > 28 || contentWidth < _fullPrimaryLabelBreakpoint) {
      return 'Start Recommended Practice';
    }
    return full;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minImageLedHeight = (constraints.maxWidth / _bannerWidthToHeight)
            .clamp(_minImageLedHeight, _maxBannerHeight);

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Establishes minimum banner height without clipping overflowing content.
                SizedBox(height: minImageLedHeight, width: double.infinity),
                Positioned.fill(
                  child: Image.asset(
                    'assets/banner.png',
                    fit: BoxFit.cover,
                    alignment: _bannerAlignment,
                  ),
                ),
                // Left-weighted readability wash; keeps the bartender clear on the right.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: [0.0, 0.42, 0.70, 1.0],
                        colors: [
                          Color(0xF20D0D0F),
                          Color(0xB313091F),
                          Color(0x4013091F),
                          Color(0x0A13091F),
                        ],
                      ),
                    ),
                  ),
                ),
                // Soft bottom vignette for chip/CTA legibility without darkening the art.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.55, 1.0],
                        colors: [Color(0x00000000), Color(0x33000000)],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth;
                      final inlineCtas = contentWidth >= _inlineCtaBreakpoint;
                      final stretchStacked =
                          contentWidth < _narrowCtaBreakpoint;
                      final headlineSize = contentWidth < 700 ? 36.0 : 39.0;
                      final primaryLabel = _primaryLabelFor(contentWidth);

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xB3FFFFFF),
                                  ),
                                  children: [
                                    TextSpan(text: '$greeting, '),
                                    TextSpan(
                                      text: firstName,
                                      style: TextStyle(
                                        color: AppColors.primarySoft.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: headlineSize,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05,
                                    letterSpacing: -0.5,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: 'Train. Flip. ',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                    TextSpan(
                                      text: 'Master.',
                                      style: TextStyle(color: _pink),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Build consistency, one movement at a time.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Color(0xB3FFFFFF),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _SessionStatusChip(sessionCount: sessionCount),
                              const SizedBox(height: 17),
                              _HeroCtaRow(
                                inline: inlineCtas,
                                stretchWhenStacked: stretchStacked,
                                primaryLabel: primaryLabel,
                                onPrimary: () => _startRecommended(context),
                                onSecondary: () => _exploreMovements(context),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroCtaRow extends StatelessWidget {
  const _HeroCtaRow({
    required this.inline,
    required this.stretchWhenStacked,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool inline;
  final bool stretchWhenStacked;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final primary = _HeroActionButton(
      label: primaryLabel,
      icon: FluentIcons.play_solid,
      primary: true,
      onPressed: onPrimary,
      expand: !inline && stretchWhenStacked,
    );
    final secondary = _HeroActionButton(
      label: 'Explore Movements',
      icon: FluentIcons.grid_view_medium,
      onPressed: onSecondary,
      expand: !inline && stretchWhenStacked,
    );

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [primary, const SizedBox(width: 10), secondary],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: stretchWhenStacked
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [primary, const SizedBox(height: 10), secondary],
      ),
    );
  }
}

class _SessionStatusChip extends StatelessWidget {
  const _SessionStatusChip({required this.sessionCount});

  final int sessionCount;

  String get _label {
    final unit = sessionCount == 1 ? 'session' : 'sessions';
    return '$sessionCount $unit completed';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.timer,
            size: 11,
            color: Colors.white.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.78),
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
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool expand;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(11),
      gradient: widget.primary
          ? LinearGradient(
              colors: _hovered
                  ? const [Color(0xFFFF6A9E), Color(0xFF9B74F0)]
                  : const [Color(0xFFE8457A), Color(0xFF7C4FD6)],
            )
          : null,
      color: widget.primary
          ? null
          : Colors.white.withValues(alpha: _hovered ? 0.14 : 0.07),
      border: widget.primary
          ? null
          : Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.32 : 0.16),
            ),
      boxShadow: widget.primary
          ? [
              BoxShadow(
                color: _pink.withValues(alpha: _hovered ? 0.22 : 0.12),
                blurRadius: _hovered ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );

    final labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: widget.primary ? 1 : 0.92),
    );

    // Flexible + loose keeps the CTA content-sized when space allows, and
    // prevents RenderFlex overflow when the parent caps width.
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: decoration,
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 11.5, color: Colors.white),
            const SizedBox(width: 7),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );

    final child = widget.expand
        ? button
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.primary ? 300 : 220),
            child: button,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onPressed, child: child),
    );
  }
}
