import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/profile_border.dart';

/// Paints ornamental Elixr avatar frames around a centered circular avatar.
///
/// Pure presentation — no repository or business logic.
class ProfileBorderPainter extends CustomPainter {
  ProfileBorderPainter({
    required this.definition,
    required this.avatarSize,
    required this.progress,
    required this.animate,
    this.highlightAccent,
    this.isDark = true,
  });

  final ProfileBorderDefinition definition;
  final double avatarSize;
  final double progress;
  final bool animate;
  final Color? highlightAccent;
  final bool isDark;

  Color get _primary => Color(definition.primaryColorValue);
  Color get _secondary => Color(definition.secondaryColorValue);
  Color get _tertiary =>
      Color(definition.tertiaryColorValue ?? definition.secondaryColorValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final avatarRadius = avatarSize / 2;
    final ringRadius = avatarRadius + definition.strokeWidth * 0.55;
    final t = animate ? progress : 0.18;

    _paintOuterGlow(canvas, center, ringRadius, t);
    _paintBaseRings(canvas, center, ringRadius, t);
    _paintStyleOrnaments(canvas, center, ringRadius, t);
    _paintHighlightArc(canvas, center, ringRadius, t);
    _paintParticles(canvas, center, ringRadius, t);

    if (highlightAccent != null) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = highlightAccent!.withValues(alpha: 0.75);
      canvas.drawCircle(
        center,
        ringRadius + definition.ornamentExtent * 0.35,
        paint,
      );
    }
  }

  void _paintOuterGlow(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    if (definition.glowStrength <= 0) return;
    final pulse = animate ? (0.75 + 0.25 * math.sin(t * math.pi * 2)) : 0.85;
    final glowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        definition.glowStrength * pulse,
      )
      ..color = _primary.withValues(alpha: isDark ? 0.32 : 0.22);
    canvas.drawCircle(center, ringRadius + 2, glowPaint);
  }

  void _paintBaseRings(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = definition.strokeWidth
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(t * math.pi * 2 * 0.15),
        colors: [_primary, _secondary, _tertiary, _primary],
      ).createShader(Rect.fromCircle(center: center, radius: ringRadius));
    canvas.drawCircle(center, ringRadius, outer);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, definition.strokeWidth * 0.35)
      ..color = _secondary.withValues(alpha: isDark ? 0.55 : 0.7);
    canvas.drawCircle(center, ringRadius - definition.strokeWidth * 0.7, inner);
  }

  void _paintStyleOrnaments(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    switch (definition.visualStyle) {
      case ProfileBorderVisualStyle.beginnerCrest:
        _paintCrest(canvas, center, ringRadius, intensity: 0.7);
      case ProfileBorderVisualStyle.bronzeMetal:
        _paintSegmentedMetal(canvas, center, ringRadius, segments: 8, t: t);
        _paintBottomBadge(canvas, center, ringRadius);
      case ProfileBorderVisualStyle.violetLiquid:
        _paintSideFins(canvas, center, ringRadius, curved: true);
        _paintFlowTrails(canvas, center, ringRadius, t);
      case ProfileBorderVisualStyle.royalGold:
        _paintCrest(canvas, center, ringRadius, intensity: 1.15, jeweled: true);
        _paintSegmentedMetal(canvas, center, ringRadius, segments: 6, t: t);
      case ProfileBorderVisualStyle.cyanSegments:
        _paintSegmentedMetal(canvas, center, ringRadius, segments: 10, t: t);
      case ProfileBorderVisualStyle.crystalPulse:
        _paintCrystalPoints(canvas, center, ringRadius, t);
      case ProfileBorderVisualStyle.spectrumArc:
        _paintSpectrumArc(canvas, center, ringRadius, t);
      case ProfileBorderVisualStyle.triadSegments:
        _paintTriadOrnaments(canvas, center, ringRadius, t);
      case ProfileBorderVisualStyle.streakShield:
        _paintCrest(canvas, center, ringRadius, intensity: 0.85);
        _paintBottomBadge(canvas, center, ringRadius);
        _paintSideFins(canvas, center, ringRadius, curved: false);
      case ProfileBorderVisualStyle.tinArmor:
        _paintSegmentedMetal(canvas, center, ringRadius, segments: 12, t: t);
        _paintCrest(canvas, center, ringRadius, intensity: 1.2, jeweled: true);
        _paintBottomBadge(canvas, center, ringRadius);
        _paintSideFins(canvas, center, ringRadius, curved: false);
    }
  }

  void _paintCrest(
    Canvas canvas,
    Offset center,
    double ringRadius, {
    required double intensity,
    bool jeweled = false,
  }) {
    final tipY =
        center.dy - ringRadius - 4 * intensity * definition.ornamentIntensity;
    final path = Path()
      ..moveTo(center.dx, tipY)
      ..quadraticBezierTo(
        center.dx - 8 * intensity,
        tipY + 10 * intensity,
        center.dx - 5 * intensity,
        tipY + 14 * intensity,
      )
      ..lineTo(center.dx, tipY + 10 * intensity)
      ..lineTo(center.dx + 5 * intensity, tipY + 14 * intensity)
      ..quadraticBezierTo(
        center.dx + 8 * intensity,
        tipY + 10 * intensity,
        center.dx,
        tipY,
      )
      ..close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_secondary, _primary],
      ).createShader(path.getBounds());
    canvas.drawPath(path, fill);

    if (jeweled) {
      canvas.drawCircle(
        Offset(center.dx, tipY + 6 * intensity),
        2.2,
        Paint()..color = _tertiary.withValues(alpha: 0.95),
      );
    }
  }

  void _paintBottomBadge(Canvas canvas, Offset center, double ringRadius) {
    final y = center.dy + ringRadius + 2;
    final path = Path()
      ..moveTo(center.dx - 7, y)
      ..lineTo(center.dx + 7, y)
      ..lineTo(center.dx + 5, y + 7)
      ..lineTo(center.dx, y + 10)
      ..lineTo(center.dx - 5, y + 7)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [_primary, _secondary],
        ).createShader(path.getBounds()),
    );
  }

  void _paintSideFins(
    Canvas canvas,
    Offset center,
    double ringRadius, {
    required bool curved,
  }) {
    for (final sign in [-1.0, 1.0]) {
      final base = Offset(center.dx + sign * ringRadius, center.dy);
      final path = Path();
      if (curved) {
        path
          ..moveTo(base.dx, base.dy - 10)
          ..quadraticBezierTo(
            base.dx + sign * 12 * definition.ornamentIntensity,
            base.dy,
            base.dx,
            base.dy + 10,
          )
          ..quadraticBezierTo(
            base.dx + sign * 4,
            base.dy,
            base.dx,
            base.dy - 10,
          );
      } else {
        path
          ..moveTo(base.dx, base.dy - 8)
          ..lineTo(base.dx + sign * 9 * definition.ornamentIntensity, base.dy)
          ..lineTo(base.dx, base.dy + 8)
          ..close();
      }
      canvas.drawPath(path, Paint()..color = _primary.withValues(alpha: 0.75));
    }
  }

  void _paintSegmentedMetal(
    Canvas canvas,
    Offset center,
    double ringRadius, {
    required int segments,
    required double t,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = definition.strokeWidth * 0.85
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < segments; i++) {
      final start = (i / segments) * math.pi * 2 + t * 0.2;
      final sweep = (math.pi * 2 / segments) * 0.62;
      paint.color = (i.isEven ? _primary : _secondary).withValues(alpha: 0.9);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius + 1.5),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  void _paintFlowTrails(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = _tertiary.withValues(alpha: 0.55);
    for (var i = 0; i < 3; i++) {
      final phase = t * math.pi * 2 + i * 1.8;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius + 3 + i.toDouble()),
        phase,
        0.9,
        false,
        paint,
      );
    }
  }

  void _paintCrystalPoints(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final pulse = animate ? (0.7 + 0.3 * math.sin(t * math.pi * 2)) : 0.85;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final tip = Offset(
        center.dx + math.cos(angle) * (ringRadius + 6 * pulse),
        center.dy + math.sin(angle) * (ringRadius + 6 * pulse),
      );
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - math.cos(angle) * 7 - math.sin(angle) * 3,
          tip.dy - math.sin(angle) * 7 + math.cos(angle) * 3,
        )
        ..lineTo(
          tip.dx - math.cos(angle) * 7 + math.sin(angle) * 3,
          tip.dy - math.sin(angle) * 7 - math.cos(angle) * 3,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              _tertiary.withValues(alpha: 0.95),
              _primary.withValues(alpha: 0.8),
            ],
          ).createShader(path.getBounds()),
      );
    }
  }

  void _paintSpectrumArc(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final rect = Rect.fromCircle(center: center, radius: ringRadius + 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = definition.strokeWidth + 1
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(t * math.pi * 2 * 0.35),
        colors: const [
          Color(0xFFE91E63),
          Color(0xFFFFC107),
          Color(0xFF26C6DA),
          Color(0xFF7C4DFF),
          Color(0xFFE91E63),
        ],
      ).createShader(rect);
    canvas.drawArc(rect, t * math.pi * 2, math.pi * 1.15, false, paint);
  }

  void _paintTriadOrnaments(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final colors = [_primary, _secondary, _tertiary];
    for (var i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * (math.pi * 2 / 3) + t * 0.08;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = definition.strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i].withValues(alpha: 0.95);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius + 2),
        angle - 0.55,
        1.1,
        false,
        paint,
      );

      final tip = Offset(
        center.dx + math.cos(angle) * (ringRadius + 8),
        center.dy + math.sin(angle) * (ringRadius + 8),
      );
      canvas.drawCircle(tip, 3.2, Paint()..color = colors[i]);
    }
  }

  void _paintHighlightArc(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, definition.strokeWidth * 0.55)
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(center.dx - ringRadius, center.dy),
        Offset(center.dx + ringRadius, center.dy),
        [
          _secondary.withValues(alpha: 0.0),
          _secondary.withValues(alpha: 0.95),
          _tertiary.withValues(alpha: 0.0),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      t * math.pi * 2 - 0.6,
      1.2,
      false,
      paint,
    );
  }

  void _paintParticles(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final count = definition.particleCount;
    if (count <= 0) return;
    for (var i = 0; i < count; i++) {
      final orbit = ringRadius + 5 + (i % 2) * 3.0;
      final speed = switch (definition.motionStyle) {
        ProfileBorderMotionStyle.orbitalDots ||
        ProfileBorderMotionStyle.armoredOrbit => 1.0,
        ProfileBorderMotionStyle.emberDrift => 0.55,
        _ => 0.7,
      };
      final angle =
          t * math.pi * 2 * speed + (i * math.pi * 2 / count) + i * 0.4;
      final pos = Offset(
        center.dx + math.cos(angle) * orbit,
        center.dy + math.sin(angle) * orbit,
      );
      final radius =
          definition.motionStyle == ProfileBorderMotionStyle.emberDrift
          ? 1.4 + (i % 2) * 0.6
          : 1.8;
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = (i.isEven ? _tertiary : _secondary).withValues(
            alpha: animate ? 0.9 : 0.55,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ProfileBorderPainter oldDelegate) {
    return oldDelegate.definition.id != definition.id ||
        oldDelegate.avatarSize != avatarSize ||
        oldDelegate.progress != progress ||
        oldDelegate.animate != animate ||
        oldDelegate.highlightAccent != highlightAccent ||
        oldDelegate.isDark != isDark ||
        oldDelegate.definition.primaryColorValue !=
            definition.primaryColorValue ||
        oldDelegate.definition.secondaryColorValue !=
            definition.secondaryColorValue ||
        oldDelegate.definition.tertiaryColorValue !=
            definition.tertiaryColorValue ||
        oldDelegate.definition.visualStyle != definition.visualStyle ||
        oldDelegate.definition.motionStyle != definition.motionStyle;
  }
}

/// Neutral fallback ring when no known border is equipped.
class NeutralProfileBorderPainter extends CustomPainter {
  NeutralProfileBorderPainter({
    required this.avatarSize,
    this.highlightAccent,
    this.strokeWidth = 1.5,
  });

  final double avatarSize;
  final Color? highlightAccent;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = avatarSize / 2 + strokeWidth * 0.5;
    final accent = highlightAccent ?? const Color(0xFFFF4D8D);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.55),
          const Color(0xFFFF4D8D).withValues(alpha: 0.25),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);

    if (highlightAccent != null) {
      canvas.drawCircle(
        center,
        radius + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = highlightAccent!.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeutralProfileBorderPainter oldDelegate) {
    return oldDelegate.avatarSize != avatarSize ||
        oldDelegate.highlightAccent != highlightAccent ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
