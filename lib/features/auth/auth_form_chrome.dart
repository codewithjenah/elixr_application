import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';

/// Visual stepper for multi-step authentication flows.
class AuthFlowStepper extends StatelessWidget {
  const AuthFlowStepper({
    super.key,
    required this.step,
    required this.labels,
    this.compact = false,
  });

  /// Zero-based index of the active step.
  final int step;
  final List<String> labels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final total = labels.length;
    final clamped = step.clamp(0, total - 1);
    final motion = ElixMotion.duration(context, ElixMotion.standard);

    return Semantics(
      container: true,
      label: 'Step ${clamped + 1} of $total: ${labels[clamped]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${clamped + 1} of $total',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: compact ? 6 : AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: _StepperConnector(
                        complete: i <= clamped,
                        motion: motion,
                        highContrast: highContrast,
                        colors: colors,
                      ),
                    ),
                  ),
                _StepperNode(
                  index: i,
                  label: labels[i],
                  state: i < clamped
                      ? _StepperNodeState.complete
                      : i == clamped
                      ? _StepperNodeState.active
                      : _StepperNodeState.upcoming,
                  compact: compact || total > 2,
                  motion: motion,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _StepperNodeState { complete, active, upcoming }

class _StepperNode extends StatelessWidget {
  const _StepperNode({
    required this.index,
    required this.label,
    required this.state,
    required this.compact,
    required this.motion,
  });

  final int index;
  final String label;
  final _StepperNodeState state;
  final bool compact;
  final Duration motion;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final active = state != _StepperNodeState.upcoming;
    final isActive = state == _StepperNodeState.active;
    final markerColor = switch (state) {
      _StepperNodeState.complete || _StepperNodeState.active =>
        highContrast ? colors.textPrimary : colors.brandPrimary,
      _StepperNodeState.upcoming => colors.borderStrong.withValues(
        alpha: highContrast ? 1 : 0.55,
      ),
    };
    final fill = switch (state) {
      _StepperNodeState.complete || _StepperNodeState.active =>
        highContrast
            ? colors.textPrimary
            : colors.brandPrimary.withValues(alpha: isActive ? 0.18 : 0.14),
      _StepperNodeState.upcoming => colors.surfaceInteractive.withValues(
        alpha: highContrast ? 0 : 0.65,
      ),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 88 : 132),
      child: Column(
        children: [
          AnimatedContainer(
            duration: motion,
            curve: ElixMotion.standardCurve,
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highContrast && state == _StepperNodeState.upcoming
                  ? colors.canvas
                  : fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: markerColor,
                width: highContrast
                    ? (isActive ? 2.5 : 2)
                    : (isActive ? 1.6 : 1),
              ),
              boxShadow: highContrast || !isActive
                  ? const []
                  : [
                      BoxShadow(
                        color: colors.glowPrimary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
            ),
            child: state == _StepperNodeState.complete
                ? Icon(
                    FluentIcons.check_mark,
                    size: 10,
                    color: highContrast ? colors.onBrand : colors.brandPrimary,
                  )
                : Text(
                    '${index + 1}',
                    style: AppTheme.caption.copyWith(
                      color: active
                          ? (highContrast && state == _StepperNodeState.complete
                                ? colors.onBrand
                                : colors.textPrimary)
                          : colors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(
              color: active ? colors.textPrimary : colors.textSecondary,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperConnector extends StatelessWidget {
  const _StepperConnector({
    required this.complete,
    required this.motion,
    required this.highContrast,
    required this.colors,
  });

  final bool complete;
  final Duration motion;
  final bool highContrast;
  final ElixSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motion,
      curve: ElixMotion.standardCurve,
      height: highContrast ? 2 : 1.5,
      decoration: BoxDecoration(
        color: complete
            ? (highContrast ? colors.textPrimary : colors.brandPrimary)
            : colors.borderSubtle,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Keeps auth step bodies the same width and animates incoming content only.
///
/// Outgoing fields are dropped immediately so [TextEditingController]s are
/// never attached to two [TextBox]es at once.
class AuthStepSwitcher extends StatelessWidget {
  const AuthStepSwitcher({
    super.key,
    required this.step,
    required this.forward,
    required this.child,
  });

  final int step;
  final bool forward;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = ElixMotion.duration(context, ElixMotion.route);
    final begin = Offset(forward ? 0.045 : -0.045, 0);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: ElixMotion.routeCurve,
      layoutBuilder: (currentChild, _) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return child;
        }
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(step), child: child),
    );
  }
}

class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: HoverButton(
        onPressed: onPressed,
        semanticLabel: label,
        cursor: onPressed == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        builder: (context, states) {
          final hovered = states.isHovered && onPressed != null;
          final pressed = states.isPressed && onPressed != null;
          final focused = states.isFocused;
          final disabled = onPressed == null;
          return AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            constraints: BoxConstraints(minHeight: dense ? 40 : 44),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: dense ? AppSpacing.sm : 10,
            ),
            decoration: BoxDecoration(
              color: disabled
                  ? colors.disabledSurface
                  : pressed
                  ? colors.interactivePressed
                  : hovered
                  ? colors.interactiveHover
                  : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused
                    ? colors.focusRing
                    : disabled
                    ? colors.disabledBorder
                    : highContrast
                    ? colors.borderStrong
                    : colors.borderSubtle,
                width: focused || highContrast ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: AppTheme.body.copyWith(
                  color: disabled ? colors.disabledText : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AuthLegalConsent extends StatefulWidget {
  const AuthLegalConsent({
    super.key,
    required this.agreed,
    required this.onChanged,
    required this.checkboxKey,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;
  final Key checkboxKey;

  @override
  State<AuthLegalConsent> createState() => _AuthLegalConsentState();
}

class _AuthLegalConsentState extends State<AuthLegalConsent> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final linkStyle = AppTheme.caption.copyWith(
      color: colors.brandPrimary,
      height: 1.35,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: colors.brandPrimary,
    );
    final plainStyle = AppTheme.caption.copyWith(
      color: context.elixTextSecondary,
      height: 1.35,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: ElixMotion.duration(context, ElixMotion.micro),
        curve: ElixMotion.microCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _hovered && !highContrast
              ? colors.surfaceInteractive.withValues(alpha: 0.55)
              : colors.surfaceInteractive.withValues(
                  alpha: highContrast ? 0 : 0.28,
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.agreed
                ? (highContrast
                      ? colors.borderStrong
                      : colors.brandPrimary.withValues(alpha: 0.45))
                : colors.borderSubtle,
            width: highContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Checkbox(
                key: widget.checkboxKey,
                checked: widget.agreed,
                onChanged: (value) => widget.onChanged(value == true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => widget.onChanged(!widget.agreed),
                      child: Text('I agree to the ', style: plainStyle),
                    ),
                  ),
                  _AuthLegalTextLink(
                    label: 'Privacy Policy',
                    style: linkStyle,
                    route: AppRoutePaths.privacyPolicy,
                  ),
                  Text(' and ', style: plainStyle),
                  _AuthLegalTextLink(
                    label: 'Terms of Service',
                    style: linkStyle,
                    route: AppRoutePaths.termsOfService,
                  ),
                  Text('.', style: plainStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthLegalTextLink extends StatefulWidget {
  const _AuthLegalTextLink({
    required this.label,
    required this.style,
    required this.route,
  });

  final String label;
  final TextStyle style;
  final String route;

  @override
  State<_AuthLegalTextLink> createState() => _AuthLegalTextLinkState();
}

class _AuthLegalTextLinkState extends State<_AuthLegalTextLink> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (focused) {
          setState(() => _focused = focused);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              context.push(widget.route);
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: () => context.push(widget.route),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _focused ? colors.focusRing : const Color(0x00000000),
                width: _focused
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : 1,
              ),
            ),
            child: Text(widget.label, style: widget.style),
          ),
        ),
      ),
    );
  }
}
