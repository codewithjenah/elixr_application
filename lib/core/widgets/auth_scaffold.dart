import 'dart:math' as math;
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
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
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final String? formTitle;
  final String? formSubtitle;
  final bool formOnLeft;
  final bool formVerticalCompact;
  final bool formVerticalTight;

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold>
    with TickerProviderStateMixin {
  late final AnimationController _orbController;
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
    _entryController.forward();
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
            overlay: _FormPanel(
              fadeAnimation: _fadeAnimation,
              slideAnimation: _slideAnimation,
              formTitle: widget.formTitle,
              formSubtitle: widget.formSubtitle,
              compact: true,
              verticalCompact: widget.formVerticalCompact,
              verticalTight: widget.formVerticalTight,
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
  });

  final AnimationController orbController;
  final String? title;
  final String? subtitle;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;

    return AnimatedBuilder(
      animation: orbController,
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
  });

  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final Widget child;
  final String? formTitle;
  final String? formSubtitle;
  final bool compact;
  final bool verticalCompact;
  final bool verticalTight;

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
    final isDark = context.isDarkTheme;

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
                Text(
                  formTitle!,
                  style: AppTheme.headingMedium.copyWith(
                    color: context.elixTextPrimary,
                    fontSize: 24,
                  ),
                ),
                if (formSubtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formSubtitle!,
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
                SizedBox(height: _headerGap),
              ],
              child,
            ],
          ),
        ),
      ),
    );

    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 24,
              spreadRadius: -4,
            ),
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.10),
              blurRadius: 32,
              spreadRadius: -6,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: double.infinity,
              padding: _cardPadding,
              decoration: BoxDecoration(
                color: context.elixCardSurface.withValues(
                  alpha: isDark ? 0.82 : 0.9,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: context.elixBorder.withValues(alpha: 0.5),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : 420,
                    ),
                    child: _AuthFitScrollView(child: form),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: _panelPadding,
      child: _AuthFitScrollView(
        child: AuthFormCard(padding: _cardPadding, child: form),
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
    final isDark = context.isDarkTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14),
            blurRadius: 24,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.elixCardSurface.withValues(
                alpha: isDark ? 0.82 : 0.9,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: context.elixBorder.withValues(alpha: isDark ? 0.5 : 0.7),
              ),
            ),
            child: child,
          ),
        ),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
            fontSize: 22,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(message),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const Icon(
              FluentIcons.status_circle_error_x,
              color: AppColors.error,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTheme.body.copyWith(
                  color: AppColors.error,
                  fontSize: 13,
                ),
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
                    color: _hovered ? AppColors.primarySoft : AppColors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: _hovered
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: AppColors.primary,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BottleFlairMark(size: compact ? 64 : 88),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        Text(
          AppConstants.appName,
          style: AppTheme.headingLarge.copyWith(
            fontSize: compact ? 32 : 42,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 4 : 6,
            color: AppColors.primary,
          ),
        ),
        if (title != null && !compact) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            title!,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
              fontSize: 26,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (subtitle != null && !compact) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
              fontSize: 15,
            ),
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

/// Code-drawn bottle silhouette used across entry points without an image asset.
class BottleFlairMark extends StatelessWidget {
  const BottleFlairMark({super.key, this.size = 88, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BottleFlairPainter(
          bottleColor: highContrast
              ? context.elixTextPrimary
              : AppColors.primary,
          trailColor: highContrast ? context.elixTextPrimary : AppColors.accent,
          glow: glow && !highContrast,
        ),
      ),
    );
  }
}

class _BottleFlairPainter extends CustomPainter {
  const _BottleFlairPainter({
    required this.bottleColor,
    required this.trailColor,
    required this.glow,
  });

  final Color bottleColor;
  final Color trailColor;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .53, size.height * .54);
    final scale = size.shortestSide / 88;
    final trail = Paint()
      ..color = trailColor.withValues(alpha: .62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round;
    final trailPath = Path()
      ..moveTo(size.width * .12, size.height * .68)
      ..cubicTo(
        size.width * .05,
        size.height * .18,
        size.width * .78,
        size.height * .06,
        size.width * .88,
        size.height * .35,
      )
      ..cubicTo(
        size.width * .96,
        size.height * .56,
        size.width * .78,
        size.height * .76,
        size.width * .66,
        size.height * .8,
      );
    canvas.drawPath(trailPath, trail);
    final bottle = Path()
      ..moveTo(center.dx - 7 * scale, center.dy - 29 * scale)
      ..lineTo(center.dx + 7 * scale, center.dy - 29 * scale)
      ..lineTo(center.dx + 6 * scale, center.dy - 17 * scale)
      ..cubicTo(
        center.dx + 17 * scale,
        center.dy - 10 * scale,
        center.dx + 19 * scale,
        center.dy + 4 * scale,
        center.dx + 13 * scale,
        center.dy + 20 * scale,
      )
      ..cubicTo(
        center.dx + 8 * scale,
        center.dy + 31 * scale,
        center.dx - 10 * scale,
        center.dy + 31 * scale,
        center.dx - 15 * scale,
        center.dy + 20 * scale,
      )
      ..cubicTo(
        center.dx - 21 * scale,
        center.dy + 4 * scale,
        center.dx - 18 * scale,
        center.dy - 10 * scale,
        center.dx - 6 * scale,
        center.dy - 17 * scale,
      )
      ..close();
    if (glow) {
      canvas.drawPath(
        bottle,
        Paint()
          ..color = bottleColor.withValues(alpha: .25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawPath(bottle, Paint()..color = bottleColor);
    canvas.drawLine(
      Offset(center.dx - 7 * scale, center.dy - 25 * scale),
      Offset(center.dx + 7 * scale, center.dy - 25 * scale),
      Paint()
        ..color = Colors.white.withValues(alpha: .8)
        ..strokeWidth = 1.2 * scale,
    );
  }

  @override
  bool shouldRepaint(covariant _BottleFlairPainter oldDelegate) =>
      oldDelegate.bottleColor != bottleColor ||
      oldDelegate.trailColor != trailColor ||
      oldDelegate.glow != glow;
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
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
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
