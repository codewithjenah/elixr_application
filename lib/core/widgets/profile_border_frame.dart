import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/profile_border.dart';
import '../theme/app_theme.dart';
import 'profile_border_painter.dart';

/// Renders a cosmetic profile border around [child] without clipping the
/// avatar content. Unknown / null borders fall back to a neutral ring when
/// [fallbackNeutral] is true, or no chrome when false.
///
/// When [animate] is true and platform animations are allowed, ornamental
/// highlights and particles loop slowly. Static mode paints a fixed pose and
/// never creates an [AnimationController].
class ProfileBorderFrame extends StatefulWidget {
  const ProfileBorderFrame({
    super.key,
    required this.size,
    required this.child,
    this.equippedBorderId,
    this.showBorder = true,
    this.fallbackNeutral = true,
    this.highlightAccent,
    this.animate = false,
  });

  /// Diameter of the circular avatar content in logical pixels.
  final double size;
  final Widget child;
  final String? equippedBorderId;
  final bool showBorder;
  final bool fallbackNeutral;

  /// Optional outer accent (e.g. current-user / medal ring) drawn outside
  /// the cosmetic border so ranking semantics stay visible.
  final Color? highlightAccent;

  /// Enables continuous frame animation when the platform allows it.
  final bool animate;

  /// Layout padding outside the avatar for a known border (or neutral ring).
  static double ornamentPaddingFor(String? borderId, {bool showBorder = true}) {
    if (!showBorder) return 0;
    final definition = borderId == null ? null : profileBorderById(borderId);
    if (definition != null) return definition.ornamentExtent;
    return 6;
  }

  @override
  State<ProfileBorderFrame> createState() => ProfileBorderFrameState();
}

@visibleForTesting
class ProfileBorderFrameState extends State<ProfileBorderFrame>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @visibleForTesting
  AnimationController? get debugAnimationController => _controller;

  @visibleForTesting
  bool get debugIsAnimating => _controller != null && _controller!.isAnimating;

  ProfileBorderDefinition? get _definition {
    final id = widget.equippedBorderId;
    if (id == null || id.isEmpty) return null;
    return profileBorderById(id);
  }

  bool _platformAllowsAnimation(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && mq.disableAnimations) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    return true;
  }

  bool _shouldRunController(BuildContext context) {
    if (!widget.showBorder || !widget.animate) return false;
    if (_definition == null) return false;
    return _platformAllowsAnimation(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ProfileBorderFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate ||
        oldWidget.equippedBorderId != widget.equippedBorderId ||
        oldWidget.showBorder != widget.showBorder) {
      _syncController();
    } else if (_definition != null && _controller != null) {
      final duration = Duration(milliseconds: _definition!.animationDurationMs);
      if (_controller!.duration != duration) {
        _controller!.duration = duration;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _syncController() {
    if (!mounted) return;
    final shouldRun = _shouldRunController(context);
    if (!shouldRun) {
      if (_controller != null) {
        _controller!.dispose();
        _controller = null;
      }
      return;
    }

    final duration = Duration(milliseconds: _definition!.animationDurationMs);
    if (_controller == null) {
      _controller = AnimationController(vsync: this, duration: duration)
        ..repeat();
    } else {
      _controller!.duration = duration;
      if (!_controller!.isAnimating) {
        _controller!.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showBorder) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: widget.child,
      );
    }

    final definition = _definition;
    final padding =
        definition?.ornamentExtent ??
        (widget.fallbackNeutral || widget.highlightAccent != null ? 6.0 : 0.0);

    if (definition == null &&
        !widget.fallbackNeutral &&
        widget.highlightAccent == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: widget.child,
      );
    }

    final outer = widget.size + padding * 2;
    final animatePaint = _controller != null && definition != null;
    final isDark = context.isDarkTheme;

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (definition != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: animatePaint
                      ? _controller!
                      : const AlwaysStoppedAnimation<double>(0.18),
                  builder: (context, _) {
                    final progress = animatePaint ? _controller!.value : 0.18;
                    return CustomPaint(
                      painter: ProfileBorderPainter(
                        definition: definition,
                        avatarSize: widget.size,
                        progress: progress,
                        animate: animatePaint,
                        highlightAccent: widget.highlightAccent,
                        isDark: isDark,
                      ),
                    );
                  },
                ),
              ),
            )
          else
            Positioned.fill(
              child: CustomPaint(
                painter: NeutralProfileBorderPainter(
                  avatarSize: widget.size,
                  highlightAccent: widget.highlightAccent,
                  strokeWidth: widget.highlightAccent != null ? 2 : 1.5,
                ),
              ),
            ),
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: ClipOval(child: widget.child),
          ),
        ],
      ),
    );
  }
}
