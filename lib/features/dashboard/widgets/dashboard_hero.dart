import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
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
  static const double _inlineCtaBreakpoint = 620;

  /// Below this, full-width stacked CTAs are acceptable.
  static const double _narrowCtaBreakpoint = 520;

  /// Prefer the named "Practice …" label when the hero content is wide enough.
  static const double _fullPrimaryLabelBreakpoint = 560;

  /// Smallest hero width that preserves the 226px slogan reservation while
  /// leaving enough room for readable, stacked CTA content.
  static const double _sloganVisibilityBreakpoint = 840;

  /// Banner art is ~16:9; a taller hero on wide layouts avoids cropping the subject.
  static const double _bannerWidthToHeight = 3.4;
  static const double _minImageLedHeight = 280.0;
  static const double _maxBannerHeight = 340.0;
  static const double _heroContentMaxWidth = 720.0;

  /// Keeps the bartender's face and pour action in frame when cover-cropping.
  static const Alignment _bannerAlignment = Alignment(0.58, -0.38);

  static String practiceRouteFor(TrainingRecommendation? recommendation) {
    final mastery = recommendation?.recommended;
    final variant = recommendation?.recommendedVariant;
    if (mastery == null ||
        variant == null ||
        !recommendation!.hasRunnablePractice) {
      return '/movements';
    }
    final encoded = Uri.encodeComponent(variant.movementName);
    return '/practice?movement=$encoded&difficulty=${mastery.movement.difficulty}&prop=${variant.trainingProp.protocolValue}';
  }

  void _startRecommended(BuildContext context) {
    context.go(practiceRouteFor(recommendation));
  }

  void _exploreMovements(BuildContext context) {
    context.go('/movements');
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
                  // A single restrained wash protects copy without turning the
                  // dashboard into another gradient-heavy surface.
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0x9E17111E)),
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
                    AppSpacing.lg,
                    AppSpacing.lg,
                    showSlogan ? 226 : AppSpacing.lg,
                    AppSpacing.lg,
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
