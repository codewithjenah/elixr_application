import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';
import 'elix_app_logo.dart';
import 'elix_editorial_header.dart';
import 'elix_scaffold_page.dart';

class AuthScaffold extends StatefulWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.formTitle,
    this.formSubtitle,
    this.formOnLeft = false,
    this.formVerticalCompact = false,
    this.formVerticalTight = false,
    this.noScrollForm = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final String? formTitle;
  final String? formSubtitle;
  final bool formOnLeft;
  final bool formVerticalCompact;
  final bool formVerticalTight;
  final bool noScrollForm;

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold>
    with TickerProviderStateMixin {
  late final AnimationController _orbController;
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: ElixMotion.ambient,
    );

    _entryController = AnimationController(
      vsync: this,
      duration: ElixMotion.intro,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation =
        Tween<Offset>(
          begin: Offset(widget.formOnLeft ? -0.04 : 0.04, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _orbController.stop();
      _entryController.value = 1;
      return;
    }
    if (!_orbController.isAnimating) _orbController.repeat();
    if (_entryController.value == 0) _entryController.forward();
  }

  @override
  void dispose() {
    _orbController.dispose();
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

          if (useSplit) {
            final brandPanel = Expanded(
              flex: 46,
              child: _BrandPanel(
                orbController: _orbController,
                title: widget.title,
                subtitle: widget.subtitle,
              ),
            );
            final divider = Container(
              width: 1,
              color: context.elixBorder.withValues(alpha: 0.35),
            );
            final formPanel = Expanded(
              flex: 54,
              child: _FormPanel(
                fadeAnimation: _fadeAnimation,
                slideAnimation: _slideAnimation,
                formTitle: widget.formTitle,
                formSubtitle: widget.formSubtitle,
                verticalCompact: widget.formVerticalCompact,
                verticalTight: widget.formVerticalTight,
                noScroll: widget.noScrollForm,
                child: widget.child,
              ),
            );

            return Row(
              children: widget.formOnLeft
                  ? [formPanel, divider, brandPanel]
                  : [brandPanel, divider, formPanel],
            );
          }

          return _BrandPanel(
            orbController: _orbController,
            title: widget.title,
            subtitle: widget.subtitle,
            overlayOnly:
                constraints.maxHeight < 680 ||
                (widget.noScrollForm && constraints.maxHeight < 760),
            overlay: _FormPanel(
              fadeAnimation: _fadeAnimation,
              slideAnimation: _slideAnimation,
              formTitle: widget.formTitle,
              formSubtitle: widget.formSubtitle,
              compact: true,
              verticalCompact: widget.formVerticalCompact,
              verticalTight: widget.formVerticalTight,
              noScroll: widget.noScrollForm,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.orbController,
    this.title,
    this.subtitle,
    this.overlay,
    this.overlayOnly = false,
  });

  final AnimationController orbController;
  final String? title;
  final String? subtitle;
  final Widget? overlay;
  final bool overlayOnly;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: reducedMotion
          ? const AlwaysStoppedAnimation(0)
          : orbController,
      builder: (context, _) {
        final t = orbController.value * 2 * math.pi;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (!highContrast)
              CustomPaint(
                painter: _DotGridPainter(
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.035 : 0.05,
                  ),
                ),
              ),
            if (!highContrast)
              _Orb(
                top: 40 + math.sin(t) * 20,
                left: -60,
                size: 220,
                color: AppColors.primary.withValues(alpha: 0.20),
              ),
            if (!highContrast)
              _Orb(
                bottom: 80 + math.cos(t) * 16,
                right: -40,
                size: 200,
                color: AppColors.accent.withValues(alpha: 0.18),
              ),
            if (overlay == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: _BrandContent(title: title, subtitle: subtitle),
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
                    const SizedBox(height: AppSpacing.xl),
                    _BrandContent(
                      title: title,
                      subtitle: subtitle,
                      compact: true,
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: overlay!,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
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
    this.noScroll = false,
  });

  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final Widget child;
  final String? formTitle;
  final String? formSubtitle;
  final bool compact;
  final bool verticalCompact;
  final bool verticalTight;
  final bool noScroll;

  double get _headerGap {
    if (verticalTight) return AppSpacing.sm;
    if (verticalCompact) return AppSpacing.md;
    return compact ? AppSpacing.lg : AppSpacing.md;
  }

  EdgeInsets get _cardPadding {
    if (verticalTight) {
      return const EdgeInsets.all(AppSpacing.sm);
    }
    if (verticalCompact) {
      return const EdgeInsets.all(AppSpacing.sm + 4);
    }
    return const EdgeInsets.all(AppSpacing.md);
  }

  EdgeInsets get _panelPadding {
    if (verticalTight) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xs,
      );
    }
    if (verticalCompact) {
      return const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.sm,
      );
    }
    return const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxl,
      vertical: AppSpacing.md,
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: ConstrainedBox(
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
        ),
      ),
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
              child: noScroll
                  ? Center(child: form)
                  : _AuthFitScrollView(child: form),
            ),
          ),
        ),
      );
    }

    final formCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: AuthFormCard(padding: _cardPadding, child: form),
    );
    return Padding(
      padding: _panelPadding,
      child: noScroll
          ? Center(child: formCard)
          : _AuthFitScrollView(child: formCard),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.cardDecoration(context),
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
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: highContrast
              ? context.elixCardSurface
              : error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highContrast ? error : error.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Icon(FluentIcons.status_circle_error_x, color: error, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTheme.body.copyWith(color: error, fontSize: 13),
              ),
            ),
          ],
        ),
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
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  State<AuthFooterLink> createState() => _AuthFooterLinkState();
}

class _AuthFooterLinkState extends State<AuthFooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
              children: [
                if (widget.prompt.isNotEmpty)
                  TextSpan(text: '${widget.prompt} '),
                TextSpan(
                  text: widget.action,
                  style: TextStyle(
                    color: _hovered ? colors.brandHover : colors.brandPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: _hovered
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: colors.brandPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandContent extends StatelessWidget {
  const _BrandContent({this.title, this.subtitle, this.compact = false});

  final String? title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brandColor = context.elixColors.brandPrimary;
    final parts = title == null ? null : _brandTitleParts(title!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElixAppLogo(size: compact ? 72 : 112),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        Text(
          AppConstants.appName,
          style: AppTheme.brandTitle(
            fontSize: compact ? 32 : 42,
            color: brandColor,
          ).copyWith(letterSpacing: compact ? 4 : 6),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppConstants.appTagline,
          style: AppTheme.supporting(color: context.elixTextSecondary).copyWith(
            fontSize: compact ? 11 : 13,
            letterSpacing: compact ? 0.3 : 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        if (title != null && !compact) ...[
          const SizedBox(height: AppSpacing.lg),
          ElixEditorialHeader(
            heading: parts!.heading,
            accentHeading: parts.accentHeading,
            subtitle: subtitle,
            variant: ElixEditorialHeaderVariant.hero,
          ),
        ] else if (subtitle != null && !compact) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTheme.supporting(color: context.elixTextSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (!compact) ...[
          const SizedBox(height: AppSpacing.xxl),
          _FeatureRow(
            icon: FluentIcons.video_solid,
            label: 'Real-time movement feedback',
          ),
          const SizedBox(height: AppSpacing.md),
          _FeatureRow(
            icon: FluentIcons.chart,
            label: 'Track your progress over time',
          ),
          const SizedBox(height: AppSpacing.md),
          _FeatureRow(
            icon: FluentIcons.trophy,
            label: 'Master flair bartending skills',
          ),
        ],
      ],
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

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: context.elixColors.brandPrimary),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 28.0;
    const radius = 1.0;

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

class _Orb extends StatelessWidget {
  const _Orb({
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
