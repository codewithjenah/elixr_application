import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../progress/training_recommendation.dart';

const _pink = AppColors.primary;

/// Dashboard hero: greeting, brand headline, session status, and CTAs.
///
/// Primary action starts the recommended guided practice session.
/// Secondary action opens the movement catalog.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    this.firstName,
    this.greeting,
    required this.sessionCount,
    required this.recommendation,
  });

  /// Retained for source compatibility; the greeting now lives in the
  /// dashboard header so the hero can focus on the recommended movement.
  final String? firstName;
  final String? greeting;
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
  static const double _heroContentMaxWidth = 720.0;

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

  String get _movementName =>
      recommendation?.recommended.movement.name ?? 'Normal Grip';

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
    final highContrast = context.isHighContrast;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSlogan = constraints.maxWidth >= 900 && !highContrast;
        final minImageLedHeight = (constraints.maxWidth / _bannerWidthToHeight)
            .clamp(_minImageLedHeight, _maxBannerHeight);

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: highContrast ? context.elixCardSurface : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: highContrast
                    ? context.elixBorder
                    : Colors.white.withValues(alpha: 0.08),
                width: highContrast ? 2 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Establishes minimum banner height without clipping overflowing content.
                SizedBox(height: minImageLedHeight, width: double.infinity),
                if (!highContrast) ...[
                  const Positioned.fill(
                    child: Image(
                      image: AssetImage('assets/banner.png'),
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
                ],
                if (showSlogan)
                  Positioned(
                    right: 18,
                    top: 62,
                    height: 154,
                    width: 194,
                    child: Semantics(
                      image: true,
                      label: 'Discipline creates freedom',
                      child: Image.asset(
                        'assets/slogan_2.png',
                        key: const ValueKey('dashboard-hero-slogan'),
                        // Contain keeps the full three-line artwork visible;
                        // cover would crop the first and last letters.
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    26,
                    showSlogan ? 226 : 28,
                    26,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth;
                      final inlineCtas = contentWidth >= _inlineCtaBreakpoint;
                      final stretchStacked =
                          contentWidth < _narrowCtaBreakpoint;
                      final primaryLabel = _primaryLabelFor(contentWidth);
                      final onPhoto = !highContrast;

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _heroContentMaxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '✦  PRACTICE TODAY',
                                style: AppTheme.eyebrow(
                                  color: onPhoto
                                      ? AppColors.primarySoft
                                      : context.elixColors.brandPrimary,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Master',
                                style: AppTheme.pageTitle(
                                  context,
                                  color: onPhoto
                                      ? Colors.white
                                      : context.elixTextPrimary,
                                ).copyWith(height: 1),
                              ),
                              const SizedBox(height: 2),
                              if (highContrast)
                                Text(
                                  _movementName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.pageTitle(
                                    context,
                                    color: context.elixTextPrimary,
                                  ).copyWith(height: 1.05),
                                )
                              else
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                        colors: [
                                          AppColors.primary,
                                          AppColors.accentSoft,
                                        ],
                                      ).createShader(bounds),
                                  child: Text(
                                    _movementName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.pageTitle(
                                      context,
                                      color: Colors.white,
                                    ).copyWith(height: 1.05),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Build control. Move with confidence.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: onPhoto
                                      ? const Color(0xB3FFFFFF)
                                      : context.elixTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 11),
                              _SessionStatusChip(sessionCount: sessionCount),
                              const SizedBox(height: 20),
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

  @override
  Widget build(BuildContext context) {
    final unit = sessionCount == 1 ? 'session' : 'sessions';
    return Text(
      '$sessionCount $unit completed',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.68),
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
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(11),
      gradient: widget.primary && !highContrast
          ? LinearGradient(
              colors: _hovered
                  ? const [Color(0xFFFF6A9E), Color(0xFF9B74F0)]
                  : const [Color(0xFFE8457A), Color(0xFF7C4FD6)],
            )
          : null,
      color: widget.primary
          ? (highContrast ? colors.brandPrimary : null)
          : (highContrast
                ? colors.surfaceRaised
                : Colors.white.withValues(alpha: _hovered ? 0.14 : 0.07)),
      border: widget.primary && !highContrast
          ? null
          : Border.all(
              color: highContrast
                  ? colors.borderStrong
                  : Colors.white.withValues(alpha: _hovered ? 0.32 : 0.16),
              width: highContrast ? 2 : 1,
            ),
      boxShadow: widget.primary && !highContrast
          ? [
              BoxShadow(
                color: _pink.withValues(alpha: _hovered ? 0.22 : 0.12),
                blurRadius: _hovered ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ]
          : const [],
    );

    final labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: widget.primary && highContrast
          ? colors.onBrand
          : Colors.white.withValues(alpha: widget.primary ? 1 : 0.92),
    );

    // Flexible + loose keeps the CTA content-sized when space allows, and
    // prevents RenderFlex overflow when the parent caps width.
    final button = AnimatedContainer(
      duration: ElixMotion.duration(context, ElixMotion.standard),
      curve: ElixMotion.standardCurve,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: decoration,
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 11.5,
              color: widget.primary && highContrast
                  ? colors.onBrand
                  : Colors.white,
            ),
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
