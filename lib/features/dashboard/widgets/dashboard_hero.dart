import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../progress/training_recommendation.dart';

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
  static const double _inlineCtaBreakpoint = 560;

  /// Below this, full-width stacked CTAs are acceptable.
  static const double _narrowCtaBreakpoint = 520;

  /// Prefer the named "Practice …" label when the hero content is wide enough.
  static const double _fullPrimaryLabelBreakpoint = 480;

  /// The photo is deliberately a compact decision surface rather than a
  /// second page header. This keeps the next practice visible above the fold.
  static const double _bannerWidthToHeight = 3.6;
  static const double _minImageLedHeight = 340.0;
  static const double _maxBannerHeight = 400.0;
  static const double _heroContentMaxWidth = 500.0;

  /// One deliberately contained brand moment balances the photo-led hero.
  static const double _sloganVisibilityBreakpoint = 880;

  /// Keeps the bartender's face and pour action in frame when cover-cropping.
  static const Alignment _bannerAlignment = Alignment(0.58, -0.38);

  static String practiceRouteFor(TrainingRecommendation? recommendation) {
    final mastery = recommendation?.recommended;
    final variant = recommendation?.recommendedVariant;
    if (mastery == null ||
        variant == null ||
        !recommendation!.hasRunnablePractice) {
      return AppRoutePaths.movements;
    }
    return AppRoutePaths.personalPractice(
      movement: variant.movementName,
      difficulty: mastery.movement.difficulty,
      prop: variant.trainingProp.protocolValue,
    );
  }

  void _startRecommended(BuildContext context) {
    context.go(practiceRouteFor(recommendation));
  }

  void _exploreMovements(BuildContext context) {
    context.go(AppRoutePaths.movements);
  }

  String get _fullPrimaryLabel {
    if (recommendation != null && !recommendation!.hasRunnablePractice) {
      return 'Explore Movements';
    }
    final name = recommendation?.recommended.movement.name;
    if (name == null || name.isEmpty) return 'Start Recommended Practice';
    return 'Practice $name';
  }

  String get _movementName =>
      recommendation?.recommended.movement.name ?? 'Normal Grip';

  /// Prefer the named practice label when it fits; otherwise use the short fallback.
  String _primaryLabelFor(double contentWidth) {
    final full = _fullPrimaryLabel;
    if (full == 'Start Recommended Practice' || full == 'Explore Movements') {
      return full;
    }
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
        final showSlogan =
            constraints.maxWidth >= _sloganVisibilityBreakpoint &&
            !highContrast;
        final minImageLedHeight = (constraints.maxWidth / _bannerWidthToHeight)
            .clamp(_minImageLedHeight, _maxBannerHeight);

        return ElixPanelCard(
          accent: context.elixColors.brandPrimary,
          showAccentBar: true,
          variant: ElixPanelVariant.hero,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
                  // A single restrained wash protects copy without turning
                  // the dashboard into another gradient-heavy surface.
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x9E17111E)),
                  ),
                ],
                if (showSlogan)
                  Positioned(
                    right: AppSpacing.lg,
                    bottom: AppSpacing.md,
                    width: 330,
                    child: IgnorePointer(
                      child: Semantics(
                        image: true,
                        label: 'Better bartenders, brighter tomorrows',
                        child: Image.asset(
                          'assets/slogan_3.png',
                          key: const ValueKey('dashboard-hero-slogan'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth;
                      final ctaContentWidth =
                          contentWidth < _heroContentMaxWidth
                          ? contentWidth
                          : _heroContentMaxWidth;
                      final inlineCtas =
                          ctaContentWidth >= _inlineCtaBreakpoint;
                      final stretchStacked =
                          ctaContentWidth < _narrowCtaBreakpoint;
                      final primaryLabel = _primaryLabelFor(ctaContentWidth);
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
                                  color: context.elixColors.brandPrimary,
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
                                Text(
                                  _movementName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.pageTitle(
                                    context,
                                    color: Colors.white,
                                  ).copyWith(height: 1.05),
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
                                showSecondary:
                                    recommendation?.hasRunnablePractice ??
                                    false,
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
    required this.showSecondary,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool inline;
  final bool stretchWhenStacked;
  final String primaryLabel;
  final bool showSecondary;
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

    if (!showSecondary) return primary;

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
    final color = context.isHighContrast
        ? context.elixTextSecondary
        : Colors.white.withValues(alpha: 0.68);
    return Text(
      '$sessionCount $unit completed',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _HeroActionButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final child = primary
        ? ElixPrimaryButton(
            label: label,
            icon: icon,
            onPressed: onPressed,
            expanded: expand,
            dense: true,
          )
        : context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
        ? Button(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14),
                  const SizedBox(width: 6),
                ],
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          )
        : shad.ShadButton.outline(
            onPressed: onPressed,
            expands: expand,
            leading: icon == null ? null : Icon(icon, size: 14),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          );
    return child;
  }
}
