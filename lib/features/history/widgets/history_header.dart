import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_editorial_header.dart';

class HistoryHeader extends StatelessWidget {
  const HistoryHeader({
    super.key,
    required this.loading,
    required this.onRefresh,
    this.showTitle = true,
  });

  final bool loading;
  final VoidCallback onRefresh;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final refresh = HistoryRefreshButton(
      loading: loading,
      onPressed: onRefresh,
    );
    if (!showTitle) {
      return Align(alignment: Alignment.centerRight, child: refresh);
    }

    return ElixEditorialHeader(
      heading: 'History',
      eyebrow: 'TRAINING',
      subtitle: 'Review and compare your previous training sessions.',
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(
            alpha: context.isDarkTheme ? 0.2 : 0.12,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
        ),
        child: Icon(FluentIcons.history, size: 20, color: AppColors.accentSoft),
      ),
      actions: [HistoryRefreshButton(loading: loading, onPressed: onRefresh)],
    );
  }
}

class HistoryRefreshButton extends StatefulWidget {
  const HistoryRefreshButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  State<HistoryRefreshButton> createState() => _HistoryRefreshButtonState();
}

class _HistoryRefreshButtonState extends State<HistoryRefreshButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Tooltip(
      message: 'Refresh sessions',
      child: FocusableActionDetector(
        enabled: !widget.loading,
        mouseCursor: widget.loading
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!widget.loading) widget.onPressed();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: GestureDetector(
          onTap: widget.loading ? null : widget.onPressed,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.elixCardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused
                    ? context.elixColors.focusRing
                    : (_hovered
                          ? AppColors.accent.withValues(alpha: 0.55)
                          : context.elixBorder),
                width: _focused
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : 1,
              ),
            ),
            child: AnimatedRotation(
              turns: widget.loading ? 1 : 0,
              duration: ElixMotion.duration(context, ElixMotion.intro),
              child: Icon(
                FluentIcons.refresh,
                size: 16,
                color: widget.loading
                    ? context.elixTextSecondary
                    : AppColors.accentSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
