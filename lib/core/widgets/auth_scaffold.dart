import 'dart:math' as math;
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';

class AuthScaffold extends StatefulWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.formTitle,
    this.formSubtitle,
    this.formOnLeft = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final String? formTitle;
  final String? formSubtitle;
  final bool formOnLeft;

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
    return ScaffoldPage(
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

    return AnimatedBuilder(
      animation: orbController,
      builder: (context, _) {
        final t = orbController.value * 2 * math.pi;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF06060A),
                      context.elixBackground,
                      AppColors.primary.withValues(alpha: 0.12),
                    ]
                  : [
                      const Color(0xFFF8F8FC),
                      context.elixBackground,
                      AppColors.primary.withValues(alpha: 0.06),
                    ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DotGridPainter(
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.035 : 0.05,
                  ),
                ),
              ),
              _Orb(
                top: 40 + math.sin(t) * 20,
                left: -60,
                size: 220,
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
              _Orb(
                bottom: 80 + math.cos(t) * 16,
                right: -40,
                size: 180,
                color: AppColors.primarySoft.withValues(alpha: 0.12),
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
          ),
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
  });

  final Animation<double> fadeAnimation;
  final Animation<Offset> slideAnimation;
  final Widget child;
  final String? formTitle;
  final String? formSubtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    final form = FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 420 : 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (formTitle != null) ...[
                Text(
                  formTitle!,
                  style: AppTheme.headingMedium.copyWith(
                    color: context.elixTextPrimary,
                    fontSize: compact ? 24 : 28,
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
                SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
              ],
              child,
            ],
          ),
        ),
      ),
    );

    if (compact) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: context.elixCardSurface.withValues(
                alpha: isDark ? 0.82 : 0.9,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: context.elixBorder.withValues(alpha: 0.5),
              ),
            ),
            child: form,
          ),
        ),
      );
    }

    return Container(
      color: isDark ? const Color(0xFF0C0C10) : const Color(0xFFFCFCFE),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: form,
        ),
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
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
        Container(
          width: compact ? 52 : 64,
          height: compact ? 52 : 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primarySoft],
            ),
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'E',
              style: AppTheme.headingLarge.copyWith(
                color: Colors.white,
                fontSize: compact ? 26 : 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
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
