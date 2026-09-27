import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';

/// `mm:ss.hh` label for reference clip positions.
String formatClipTime(int ms) {
  final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
  final seconds = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
  final hundredths = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$minutes:$seconds.$hundredths';
}

/// Three-stage progress indicator for the custom movement wizard.
class AuthoringStepper extends StatelessWidget {
  const AuthoringStepper({
    super.key,
    required this.step,
    required this.labels,
    this.dense = false,
  });

  final int step;
  final List<String> labels;

  /// Omits the secondary "Step N" caption to save vertical space.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final current = step.clamp(0, labels.length - 1);
    return Semantics(
      container: true,
      label: 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showStepCaption = !dense && constraints.maxWidth >= 640;
            final showAllLabels = constraints.maxWidth >= 520;
            return Row(
              children: [
                for (var index = 0; index < labels.length; index++) ...[
                  if (index > 0)
                    Expanded(
                      child: AnimatedContainer(
                        duration: ElixMotion.duration(
                          context,
                          ElixMotion.standard,
                        ),
                        height: context.isHighContrast ? 2 : 1.5,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.smPlus,
                        ),
                        color: index <= current
                            ? colors.brandPrimary
                            : colors.borderSubtle,
                      ),
                    ),
                  _StepNode(
                    index: index,
                    label: labels[index],
                    complete: index < current,
                    active: index == current,
                    showStepCaption: showStepCaption,
                    showLabel: showAllLabels || index == current,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.label,
    required this.complete,
    required this.active,
    required this.showStepCaption,
    required this.showLabel,
  });

  final int index;
  final String label;
  final bool complete;
  final bool active;
  final bool showStepCaption;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final upcoming = !complete && !active;
    final markerFill = active
        ? colors.brandPrimary
        : complete
        ? colors.brandPrimary.withValues(alpha: highContrast ? 0 : 0.14)
        : Colors.transparent;
    final markerBorder = upcoming ? colors.borderStrong : colors.brandPrimary;
    return AnimatedContainer(
      key: ValueKey('authoring-step-$index'),
      duration: ElixMotion.duration(context, ElixMotion.standard),
      curve: ElixMotion.standardCurve,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.smPlus,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: active && !highContrast
            ? colors.surfaceSelected
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ElixRadius.pill),
        border: Border.all(
          color: active ? colors.borderInteractive : Colors.transparent,
          width: active && highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: markerFill,
              shape: BoxShape.circle,
              border: Border.all(
                color: markerBorder,
                width: active || highContrast ? 2 : 1.2,
              ),
            ),
            child: complete
                ? Icon(
                    FluentIcons.check_mark,
                    size: 11,
                    color: colors.brandPrimary,
                  )
                : Text(
                    '${index + 1}',
                    style: ElixTypography.caption(
                      color: active
                          ? colors.onBrand
                          : upcoming
                          ? colors.textMuted
                          : colors.textPrimary,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
          ),
          if (showLabel) ...[
            const SizedBox(width: AppSpacing.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showStepCaption)
                  Text(
                    complete ? 'Step ${index + 1} · Done' : 'Step ${index + 1}',
                    style: ElixTypography.caption(color: colors.textMuted),
                  ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.label(
                    color: upcoming ? colors.textSecondary : colors.textPrimary,
                  ).copyWith(fontWeight: active ? FontWeight.w700 : null),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

enum AuthoringCheckState { ok, missing, pending }

/// Compact camera-check or learned-capability status with an icon cue.
class AuthoringStatusPill extends StatelessWidget {
  const AuthoringStatusPill({
    super.key,
    required this.label,
    required this.state,
    this.detail,
  });

  final String label;
  final AuthoringCheckState state;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final (icon, color) = switch (state) {
      AuthoringCheckState.ok => (FluentIcons.check_mark, colors.success),
      AuthoringCheckState.missing => (FluentIcons.warning, colors.warning),
      AuthoringCheckState.pending => (
        FluentIcons.circle_ring,
        colors.textSecondary,
      ),
    };
    final text = detail == null ? label : '$label · $detail';
    return Semantics(
      label:
          '$label: ${switch (state) {
            AuthoringCheckState.ok => 'ready',
            AuthoringCheckState.missing => 'needs attention',
            AuthoringCheckState.pending => 'waiting',
          }}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: highContrast
                ? Colors.transparent
                : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ElixRadius.pill),
            border: Border.all(
              color: highContrast ? color : color.withValues(alpha: 0.35),
              width: highContrast ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.caption(
                    color: state == AuthoringCheckState.pending
                        ? colors.textSecondary
                        : colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Radio-style choice card with a plain-language explanation.
class AuthoringChoiceCard extends StatelessWidget {
  const AuthoringChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final disabled = onPressed == null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: !disabled,
      child: HoverButton(
        onPressed: onPressed,
        semanticLabel: '$title. $description',
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        builder: (context, states) {
          final focused = states.isFocused;
          final hovered = states.isHovered && !disabled;
          return AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: selected && !highContrast
                  ? colors.surfaceSelected
                  : hovered
                  ? colors.interactiveHover
                  : colors.surfaceInteractive.withValues(
                      alpha: highContrast ? 0 : 0.6,
                    ),
              borderRadius: BorderRadius.circular(ElixRadius.card),
              border: Border.all(
                color: focused
                    ? colors.focusRing
                    : selected
                    ? colors.borderInteractive
                    : colors.borderSubtle,
                width: focused
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : selected
                    ? (highContrast ? 3 : 1.5)
                    : 1,
              ),
            ),
            child: Opacity(
              opacity: disabled && !selected ? 0.6 : 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? colors.brandPrimary
                            : colors.borderStrong,
                        width: selected ? 2 : 1.2,
                      ),
                    ),
                    child: selected
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors.brandPrimary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.smPlus),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 14, color: colors.textSecondary),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: Text(
                                title,
                                style: ElixTypography.label(
                                  color: colors.textPrimary,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: ElixTypography.caption(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Temporal two-handle trim editor for one reference clip.
///
/// The kept range is `[startMs, endMs]`. Handles cannot cross: the start stays
/// within `0..endMs - 1` and the end within `startMs + 1..durationMs`, matching
/// the bounds the previous per-edge sliders enforced.
class ReferenceTrimTimeline extends StatefulWidget {
  const ReferenceTrimTimeline({
    super.key,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.onChanged,
    this.enabled = true,
  });

  static const keyboardStepMs = 100;
  static const largeKeyboardStepMs = 1000;

  final int durationMs;
  final int startMs;
  final int endMs;
  final bool enabled;
  final void Function(int startMs, int endMs) onChanged;

  @override
  State<ReferenceTrimTimeline> createState() => _ReferenceTrimTimelineState();
}

class _ReferenceTrimTimelineState extends State<ReferenceTrimTimeline> {
  static const _handleWidth = 16.0;
  static const _height = 48.0;

  final FocusNode _startFocus = FocusNode(debugLabel: 'trim-start');
  final FocusNode _endFocus = FocusNode(debugLabel: 'trim-end');
  // Latest requested range. Key repeats and drag updates can arrive before
  // the parent rebuilds with the new range, so bounds use these values.
  late int _startMs = widget.startMs;
  late int _endMs = widget.endMs;
  int _dragOriginMs = 0;
  double _dragDx = 0;

  @override
  void didUpdateWidget(ReferenceTrimTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startMs = widget.startMs;
    _endMs = widget.endMs;
  }

  @override
  void dispose() {
    _startFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  void _setStart(int value) {
    final next = value.clamp(0, _endMs - 1);
    if (next == _startMs) return;
    _startMs = next;
    widget.onChanged(next, _endMs);
  }

  void _setEnd(int value) {
    final next = value.clamp(_startMs + 1, widget.durationMs);
    if (next == _endMs) return;
    _endMs = next;
    widget.onChanged(_startMs, next);
  }

  void _nudge({required bool start, required int deltaMs}) {
    if (start) {
      _setStart(_startMs + deltaMs);
    } else {
      _setEnd(_endMs + deltaMs);
    }
  }

  KeyEventResult _onKey(bool start, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final step = HardwareKeyboard.instance.isShiftPressed
        ? ReferenceTrimTimeline.largeKeyboardStepMs
        : ReferenceTrimTimeline.keyboardStepMs;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _nudge(start: start, deltaMs: -step);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nudge(start: start, deltaMs: step);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final duration = math.max(1, widget.durationMs);
    return SizedBox(
      key: const ValueKey('reference-trim-timeline'),
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = math.max(
            1.0,
            constraints.maxWidth - _handleWidth * 2,
          );
          double xFor(int ms) => _handleWidth + ms / duration * trackWidth;
          final startX = xFor(widget.startMs);
          final endX = xFor(widget.endMs);
          final dim = highContrast
              ? colors.canvas
              : colors.canvasDeep.withValues(alpha: 0.72);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _handleWidth,
                right: _handleWidth,
                top: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceInteractive,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                ),
              ),
              Positioned(
                left: _handleWidth,
                width: math.max(0, startX - _handleWidth),
                top: 8,
                bottom: 8,
                child: ColoredBox(color: dim),
              ),
              Positioned(
                left: endX,
                right: _handleWidth,
                top: 8,
                bottom: 8,
                child: ColoredBox(color: dim),
              ),
              Positioned(
                left: startX,
                width: math.max(1, endX - startX),
                top: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: highContrast
                        ? Colors.transparent
                        : colors.brandPrimary.withValues(alpha: 0.2),
                    border: Border.symmetric(
                      horizontal: BorderSide(
                        color: colors.brandPrimary,
                        width: highContrast ? 3 : 2,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: startX - _handleWidth,
                width: _handleWidth,
                top: 0,
                bottom: 0,
                child: _handle(start: true, trackWidth: trackWidth),
              ),
              Positioned(
                left: endX,
                width: _handleWidth,
                top: 0,
                bottom: 0,
                child: _handle(start: false, trackWidth: trackWidth),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _handle({required bool start, required double trackWidth}) {
    final colors = context.elixColors;
    final focusNode = start ? _startFocus : _endFocus;
    final value = start ? widget.startMs : widget.endMs;
    final enabled = widget.enabled;
    final label = start ? 'Trim start' : 'Trim end';
    const step = ReferenceTrimTimeline.keyboardStepMs;
    final (low, high) = start
        ? (0, widget.endMs - 1)
        : (widget.startMs + 1, widget.durationMs);
    return Semantics(
      slider: true,
      label: label,
      value: formatClipTime(value),
      increasedValue: formatClipTime((value + step).clamp(low, high)),
      decreasedValue: formatClipTime((value - step).clamp(low, high)),
      onIncrease: enabled
          ? () => _nudge(
              start: start,
              deltaMs: ReferenceTrimTimeline.keyboardStepMs,
            )
          : null,
      onDecrease: enabled
          ? () => _nudge(
              start: start,
              deltaMs: -ReferenceTrimTimeline.keyboardStepMs,
            )
          : null,
      child: Focus(
        focusNode: focusNode,
        canRequestFocus: enabled,
        onKeyEvent: (_, event) => _onKey(start, event),
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.resizeColumn
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                key: ValueKey(start ? 'trim-start-handle' : 'trim-end-handle'),
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (_) => focusNode.requestFocus() : null,
                onHorizontalDragStart: enabled
                    ? (_) {
                        focusNode.requestFocus();
                        _dragOriginMs = value;
                        _dragDx = 0;
                      }
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (details) {
                        _dragDx += details.delta.dx;
                        final ms =
                            (_dragOriginMs +
                                    _dragDx /
                                        trackWidth *
                                        math.max(1, widget.durationMs))
                                .round();
                        if (start) {
                          _setStart(ms);
                        } else {
                          _setEnd(ms);
                        }
                      }
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: enabled
                        ? colors.brandPrimary
                        : colors.disabledSurface,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(start ? 6 : 0),
                      right: Radius.circular(start ? 0 : 6),
                    ),
                    border: Border.all(
                      color: focused ? colors.focusRing : Colors.transparent,
                      width: focused
                          ? (context.isHighContrast
                                ? ElixFocus.ringWidthHighContrast
                                : ElixFocus.ringWidth)
                          : 1,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 16,
                      decoration: BoxDecoration(
                        color: enabled ? colors.onBrand : colors.disabledText,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
