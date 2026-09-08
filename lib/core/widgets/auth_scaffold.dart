import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
import 'elix_app_logo.dart';
import 'elix_editorial_header.dart';
import 'elix_scaffold_page.dart';

class AuthHeroFeature {
  const AuthHeroFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  static const defaults = [
    AuthHeroFeature(icon: FluentIcons.video_solid, label: 'Real-time guidance'),
    AuthHeroFeature(icon: FluentIcons.chart, label: 'Movement progression'),
    AuthHeroFeature(icon: FluentIcons.history, label: 'Practice tracking'),
  ];
}

abstract final class AuthHeroCopy {
  static const headline = 'Learn the movement. ';
  static const accentHeadline = 'Refine the technique.';
  static const supporting =
      'Desktop flair training with live movement guidance as you practice.';
}

class AuthScaffold extends StatefulWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.title,
    this.accentTitle,
    this.subtitle,
    this.formTitle,
    this.formSubtitle,
    this.formOnLeft = false,
    this.formVerticalCompact = false,
    this.formVerticalTight = false,
    this.noScrollForm = false,
    this.compactBrandHero = false,
    this.features = AuthHeroFeature.defaults,
  });

  final Widget child;
  final String? title;
  final String? accentTitle;
  final String? subtitle;
  final String? formTitle;
  final String? formSubtitle;
  final bool formOnLeft;
  final bool formVerticalCompact;
  final bool formVerticalTight;
  final bool noScrollForm;

  /// Keeps a split-screen hero visually paired with a compact auth card.
  final bool compactBrandHero;
  final List<AuthHeroFeature> features;

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _entryController;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;
  late final Animation<double> _brandFade;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: ElixMotion.ambient,
    );
    _entryController = AnimationController(
      vsync: this,
      duration: ElixMotion.intro,
    );
    _formFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.12, 1, curve: ElixMotion.introCurve),
    );
    _formSlide =
        Tween<Offset>(
          begin: Offset(widget.formOnLeft ? -0.035 : 0.035, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.12, 1, curve: ElixMotion.introCurve),
          ),
        );
    _brandFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.72, curve: ElixMotion.introCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _ambientController.stop();
      _ambientController.value = 0;
      _entryController.value = 1;
      return;
    }
    if (!_ambientController.isAnimating) _ambientController.repeat();
    if (_entryController.value == 0) _entryController.forward();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: LayoutBuilder(
        builder: (context, constraints) {
          final useSplit = constraints.maxWidth >= 900;
          final shortHeight = constraints.maxHeight < 700;
          final overlayOnly =
              !useSplit &&
              (constraints.maxHeight < 680 ||
                  (widget.noScrollForm && constraints.maxHeight < 760));
          final showFeatures =
              widget.features.isNotEmpty &&
              !overlayOnly &&
              (useSplit ? constraints.maxHeight >= 680 : false);

          final formPanel = _FormPanel(
            fadeAnimation: _formFade,
            slideAnimation: _formSlide,
            formTitle: widget.formTitle,
            formSubtitle: widget.formSubtitle,
            compact: !useSplit,
            verticalCompact: widget.formVerticalCompact,
            verticalTight: widget.formVerticalTight,
            wideSplit: constraints.maxWidth >= 1280,
            child: widget.child,
          );

          if (useSplit) {
            final brandPanel = Expanded(
              flex: constraints.maxWidth >= 1400 ? 11 : 10,
              child: _BrandPanel(
                ambientController: _ambientController,
                brandFade: _brandFade,
                title: widget.title,
                accentTitle: widget.accentTitle,
                subtitle: widget.subtitle,
                compactHero: widget.compactBrandHero || shortHeight,
                showFeatures: showFeatures,
                features: widget.features,
              ),
            );
            final divider = _AuthSplitDivider();
            final form = Expanded(
              flex: constraints.maxWidth >= 1400 ? 10 : 11,
              child: formPanel,
            );

            return Row(
              children: widget.formOnLeft
                  ? [form, divider, brandPanel]
                  : [brandPanel, divider, form],
            );
          }

          return _BrandPanel(
            ambientController: _ambientController,
            brandFade: _brandFade,
            title: widget.title,
            accentTitle: widget.accentTitle,
            subtitle: widget.subtitle,
            overlayOnly: overlayOnly,
            showFeatures: false,
            features: widget.features,
            overlay: formPanel,
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.ambientController,
    required this.brandFade,
    this.title,
    this.accentTitle,
    this.subtitle,
    this.overlay,
    this.overlayOnly = false,
    this.compactHero = false,
    this.showFeatures = true,
    this.features = const [],
  });

  final AnimationController ambientController;
  final Animation<double> brandFade;
  final String? title;
  final String? accentTitle;
  final String? subtitle;
  final Widget? overlay;
  final bool overlayOnly;
  final bool compactHero;
  final bool showFeatures;
  final List<AuthHeroFeature> features;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final colors = context.elixColors;

    final brandContent = FadeTransition(
      opacity: brandFade,
      child: _BrandContent(
        title: title,
        accentTitle: accentTitle,
        subtitle: subtitle,
        compact: overlay != null && !overlayOnly,
        compactHero: compactHero,
        showFeatures: showFeatures,
        features: features,
        ambientController: ambientController,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        const _AuthAtmosphere(),
        if (!highContrast && overlay == null) const _StaticAmbientOrbs(),
        if (!highContrast && !reduceMotion && overlay == null)
          IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: ambientController,
                builder: (context, _) {
                  final t = ambientController.value * 2 * math.pi;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _SoftOrb(
                        top: 36 + math.sin(t) * 10,
                        left: -72,
                        size: 280,
                        color: colors.brandPrimary.withValues(alpha: 0.16),
                      ),
                      _SoftOrb(
                        bottom: 48 + math.cos(t) * 8,
                        right: -64,
                        size: 240,
                        color: colors.brandSecondary.withValues(alpha: 0.14),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        if (overlay == null)
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compactHero ? AppSpacing.lg : AppSpacing.xxl,
                vertical: compactHero ? AppSpacing.lg : AppSpacing.xl,
              ),
              child: brandContent,
            ),
          )
        else if (overlayOnly)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(child: overlay!),
            ),
          )
        else
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.lg),
                _BrandContent(
                  title: title,
                  accentTitle: accentTitle,
                  subtitle: subtitle,
                  compact: true,
                  showFeatures: false,
                  features: features,
                  ambientController: ambientController,
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: overlay!,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AuthAtmosphere extends StatelessWidget {
  const _AuthAtmosphere();

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    if (highContrast) {
      return ColoredBox(color: colors.canvas);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.canvasDeep,
                colors.canvas,
                Color.alphaBlend(
                  colors.brandSecondary.withValues(alpha: isDark ? 0.10 : 0.04),
                  colors.canvas,
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.15, -0.35),
              radius: 1.05,
              colors: [
                colors.brandPrimary.withValues(alpha: isDark ? 0.16 : 0.07),
                colors.brandSecondary.withValues(alpha: isDark ? 0.08 : 0.04),
                colors.canvas.withValues(alpha: 0),
              ],
              stops: const [0, 0.34, 1],
            ),
          ),
        ),
        CustomPaint(
          painter: _DotGridPainter(
            color: colors.brandPrimary.withValues(alpha: isDark ? 0.045 : 0.06),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(painter: _HorizonSheenPainter(isDark: isDark)),
        ),
      ],
    );
  }
}

class _StaticAmbientOrbs extends StatelessWidget {
  const _StaticAmbientOrbs();

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SoftOrb(
            top: -40,
            right: -30,
            size: 180,
            color: colors.brandSecondary.withValues(alpha: 0.10),
          ),
          _SoftOrb(
            bottom: -50,
            left: 40,
            size: 160,
            color: colors.brandPrimary.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }
}

class _HorizonSheenPainter extends CustomPainter {
  const _HorizonSheenPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x00FFFFFF),
          Colors.white.withValues(alpha: isDark ? 0.025 : 0.04),
          const Color(0x00FFFFFF),
        ],
        stops: const [0.18, 0.52, 0.86],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _HorizonSheenPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _AuthSplitDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final border = context.elixBorder;
    if (highContrast) {
      return Container(width: 1, color: context.elixColors.borderStrong);
    }
    return IgnorePointer(
      child: Container(
        width: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              border.withValues(alpha: 0),
              border.withValues(alpha: 0.7),
              border.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.fadeAnimation,
    required this.slideAnimation,
    required this.child,
    this.formTitle,
    this.formSubtitle,
    this.compact = false,
    this.verticalCompact = false,
    this.verticalTight = false,
    this.wideSplit = false,
  });

  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final Widget child;
  final String? formTitle;
  final String? formSubtitle;
  final bool compact;
  final bool verticalCompact;
  final bool verticalTight;
  final bool wideSplit;

  double get _headerGap {
    if (verticalTight) return AppSpacing.sm;
    if (verticalCompact) return AppSpacing.md;
    return AppSpacing.md;
  }

  EdgeInsets get _cardPadding {
    if (verticalTight || compact) {
      return const EdgeInsets.fromLTRB(18, 16, 18, 16);
    }
    if (verticalCompact) {
      return const EdgeInsets.fromLTRB(20, 18, 20, 18);
    }
    return const EdgeInsets.fromLTRB(28, 26, 28, 24);
  }

  EdgeInsets get _panelPadding {
    if (verticalTight) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      );
    }
    if (verticalCompact) {
      return EdgeInsets.symmetric(
        horizontal: wideSplit ? AppSpacing.xxl : AppSpacing.xl,
        vertical: AppSpacing.sm,
      );
    }
    return EdgeInsets.symmetric(
      horizontal: wideSplit ? 56 : AppSpacing.xxl,
      vertical: AppSpacing.lg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final form = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 420 : 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (formTitle != null) ...[
            ElixEditorialHeader(
              heading: formTitle!,
              subtitle: formSubtitle,
              variant: ElixEditorialHeaderVariant.compact,
            ),
            SizedBox(height: _headerGap),
          ],
          child,
        ],
      ),
    );

    final animatedForm = reduceMotion
        ? form
        : FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(position: slideAnimation, child: form),
          );

    if (compact) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AuthFormCard(
          padding: _cardPadding,
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : 420,
              ),
              child: _AuthFitScrollView(child: animatedForm),
            ),
          ),
        ),
      );
    }

    final formCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: AuthFormCard(padding: _cardPadding, child: animatedForm),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: context.isHighContrast
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  context.elixColors.canvas.withValues(alpha: 0),
                  context.elixColors.canvas.withValues(alpha: 0.55),
                ],
              ),
      ),
      child: Padding(
        padding: _panelPadding,
        child: _AuthFitScrollView(child: formCard),
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final flatten = context.elixWorkspaceVisuals.flattenDenseSurfaces;

    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highContrast ? colors.surfaceRaised : null,
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    colors.brandPrimary.withValues(alpha: isDark ? 0.07 : 0.04),
                    colors.surfaceRaised,
                  ),
                  colors.surfaceRaised,
                  Color.alphaBlend(
                    colors.brandSecondary.withValues(
                      alpha: isDark ? 0.05 : 0.03,
                    ),
                    colors.surfaceRaised,
                  ),
                ],
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highContrast
              ? colors.borderStrong
              : Color.alphaBlend(
                  Colors.white.withValues(alpha: isDark ? 0.08 : 0.65),
                  colors.borderSubtle,
                ),
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast || flatten
            ? const []
            : [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: isDark ? 0.55 : 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: colors.glowPrimary.withValues(
                    alpha: isDark ? 0.10 : 0.06,
                  ),
                  blurRadius: 36,
                  spreadRadius: -10,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

class AuthFormHeader extends StatelessWidget {
  const AuthFormHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ElixEditorialHeader(
      heading: title,
      subtitle: subtitle,
      variant: ElixEditorialHeaderVariant.compact,
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final error = context.elixColors.error;
    final highContrast = context.isHighContrast;
    return AnimatedSwitcher(
      duration: ElixMotion.duration(context, ElixMotion.micro),
      child: Container(
        key: ValueKey(message),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: highContrast
              ? context.elixCardSurface
              : error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highContrast ? error : error.withValues(alpha: 0.38),
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                FluentIcons.status_circle_error_x,
                color: error,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTheme.body.copyWith(
                  color: error,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthErrorSlot extends StatelessWidget {
  const AuthErrorSlot({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: ElixMotion.duration(context, ElixMotion.standard),
      switchInCurve: ElixMotion.standardCurve,
      switchOutCurve: ElixMotion.standardCurve,
      child: message == null
          ? const SizedBox(
              key: ValueKey('auth-error-empty'),
              width: double.infinity,
            )
          : Padding(
              key: ValueKey(message),
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: AuthErrorBanner(message: message!),
            ),
    );
  }
}

class AuthFooterLink extends StatefulWidget {
  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
    this.muted = false,
    this.dense = false,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;
  final bool muted;
  final bool dense;

  @override
  State<AuthFooterLink> createState() => _AuthFooterLinkState();
}

class _AuthFooterLinkState extends State<AuthFooterLink> {
  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return HoverButton(
      onPressed: widget.onTap,
      cursor: SystemMouseCursors.click,
      builder: (context, states) {
        final hovered = states.isHovered || states.isPressed;
        final focused = states.isFocused;
        final actionColor = widget.muted
            ? (hovered ? colors.brandHover : colors.textSecondary)
            : (hovered ? colors.brandHover : colors.brandPrimary);
        return FocusBorder(
          focused: focused,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: widget.dense ? AppSpacing.xs : AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                  fontSize: widget.muted ? 12.5 : 14,
                ),
                children: [
                  if (widget.prompt.isNotEmpty)
                    TextSpan(text: '${widget.prompt} '),
                  TextSpan(
                    text: widget.action,
                    style: TextStyle(
                      color: actionColor,
                      fontWeight: FontWeight.w600,
                      decoration: hovered
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: actionColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrandContent extends StatelessWidget {
  const _BrandContent({
    required this.ambientController,
    this.title,
    this.accentTitle,
    this.subtitle,
    this.compact = false,
    this.compactHero = false,
    this.showFeatures = true,
    this.features = const [],
  });

  final AnimationController ambientController;
  final String? title;
  final String? accentTitle;
  final String? subtitle;
  final bool compact;
  final bool compactHero;
  final bool showFeatures;
  final List<AuthHeroFeature> features;

  @override
  Widget build(BuildContext context) {
    final brandColor = context.elixColors.brandPrimary;
    final parts = title == null
        ? null
        : (accentTitle != null
              ? (heading: title!, accentHeading: accentTitle)
              : _brandTitleParts(title!));
    final heroIsCompact = compact || compactHero;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LogoSignature(
          size: heroIsCompact ? 72 : 120,
          ambientController: ambientController,
        ),
        SizedBox(height: heroIsCompact ? AppSpacing.sm : AppSpacing.md),
        Text(
          AppConstants.appName,
          style: AppTheme.brandTitle(
            fontSize: heroIsCompact ? 32 : 44,
            color: brandColor,
          ).copyWith(letterSpacing: heroIsCompact ? 4 : 7),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppConstants.appTagline,
          style: AppTheme.supporting(color: context.elixTextSecondary).copyWith(
            fontSize: heroIsCompact ? 11 : 13,
            letterSpacing: heroIsCompact ? 0.3 : 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        if (title != null && !compact) ...[
          SizedBox(height: compactHero ? AppSpacing.md : AppSpacing.xl),
          ElixEditorialHeader(
            heading: parts!.heading,
            accentHeading: parts.accentHeading,
            subtitle: subtitle,
            variant: compactHero
                ? ElixEditorialHeaderVariant.compact
                : ElixEditorialHeaderVariant.standard,
            textAlign: TextAlign.center,
          ),
        ] else if (subtitle != null && !compact) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTheme.supporting(color: context.elixTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (showFeatures && !compact && features.isNotEmpty) ...[
          SizedBox(height: compactHero ? AppSpacing.lg : AppSpacing.xl),
          _FeatureIndicators(features: features, compact: compactHero),
        ],
      ],
    );

    if (!compactHero) return content;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: content,
    );
  }
}

class _LogoSignature extends StatelessWidget {
  const _LogoSignature({required this.size, required this.ambientController});

  final double size;
  final AnimationController ambientController;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final logo = ElixAppLogo(size: size);
    if (highContrast) return logo;

    final frame = size * 1.72;
    return SizedBox(
      width: frame,
      height: frame,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: reduceMotion
                ? _GlowHalo(size: size * 1.35, intensity: 0.32)
                : AnimatedBuilder(
                    animation: ambientController,
                    builder: (context, _) {
                      final breath =
                          0.5 +
                          0.5 * math.sin(ambientController.value * 2 * math.pi);
                      return _GlowHalo(
                        size: size * (1.22 + breath * 0.16),
                        intensity: 0.22 + breath * 0.16,
                      );
                    },
                  ),
          ),
          IgnorePointer(
            child: reduceMotion
                ? CustomPaint(
                    size: Size.square(size * 1.38),
                    painter: _OrbitRingPainter(
                      primary: colors.brandPrimary,
                      secondary: colors.brandSecondary,
                    ),
                  )
                : AnimatedBuilder(
                    animation: ambientController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: ambientController.value * 2 * math.pi,
                        child: child,
                      );
                    },
                    child: CustomPaint(
                      size: Size.square(size * 1.38),
                      painter: _OrbitRingPainter(
                        primary: colors.brandPrimary,
                        secondary: colors.brandSecondary,
                      ),
                    ),
                  ),
          ),
          logo,
        ],
      ),
    );
  }
}

class _GlowHalo extends StatelessWidget {
  const _GlowHalo({required this.size, required this.intensity});

  final double size;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            colors.brandPrimary.withValues(alpha: intensity),
            colors.brandSecondary.withValues(alpha: intensity * 0.45),
            colors.brandPrimary.withValues(alpha: 0),
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  const _OrbitRingPainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = primary.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          const Color(0x00FFFFFF),
          primary.withValues(alpha: 0),
          primary.withValues(alpha: 0.72),
          secondary.withValues(alpha: 0.28),
          const Color(0x00FFFFFF),
        ],
        stops: const [0, 0.52, 0.7, 0.84, 1],
      ).createShader(rect);
    canvas.drawArc(rect, 0, math.pi * 2, false, sweep);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

class _FeatureIndicators extends StatelessWidget {
  const _FeatureIndicators({required this.features, required this.compact});

  final List<AuthHeroFeature> features;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: compact ? AppSpacing.sm : AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        for (final feature in features)
          _FeatureIndicator(feature: feature, compact: compact),
      ],
    );
  }
}

class _FeatureIndicator extends StatelessWidget {
  const _FeatureIndicator({required this.feature, required this.compact});

  final AuthHeroFeature feature;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    return Semantics(
      label: feature.label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: highContrast
              ? colors.canvas
              : colors.surfaceRaised.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highContrast
                ? colors.borderStrong
                : colors.borderSubtle.withValues(alpha: 0.9),
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(feature.icon, size: 14, color: colors.brandPrimary),
            const SizedBox(width: 8),
            Text(
              feature.label,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({String heading, String? accentHeading}) _brandTitleParts(String title) {
  final text = title.trim();
  final space = text.lastIndexOf(' ');
  if (space <= 0) {
    return (heading: text, accentHeading: null);
  }
  return (
    heading: text.substring(0, space + 1),
    accentHeading: text.substring(space + 1),
  );
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 32.0;
    const radius = 0.9;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Hides the default desktop scrollbar on auth forms; wheel/trackpad scroll still works.
class _AuthScrollBehavior extends ScrollBehavior {
  const _AuthScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Centers auth form content when it fits; scrolls only when the viewport is too short.
class _AuthFitScrollView extends StatelessWidget {
  const _AuthFitScrollView({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return ScrollConfiguration(
          behavior: const _AuthScrollBehavior(),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.color,
  });

  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
