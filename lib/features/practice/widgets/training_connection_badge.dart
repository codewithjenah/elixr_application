import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/websocket_service.dart';

class TrainingConnectionBadge extends StatelessWidget {
  const TrainingConnectionBadge({
    super.key,
    required this.state,
    this.connecting = false,
  });

  final WebSocketConnectionState state;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final showSpinner =
        connecting || state == WebSocketConnectionState.connecting;

    final (label, color, bgAlpha, borderAlpha) = switch (state) {
      WebSocketConnectionState.connected => (
        'Backend Connected',
        AppColors.success,
        0.12,
        0.28,
      ),
      WebSocketConnectionState.connecting => (
        'Connecting',
        AppColors.warning,
        0.1,
        0.26,
      ),
      WebSocketConnectionState.error => (
        'Connection Error',
        AppColors.error,
        0.1,
        0.3,
      ),
      WebSocketConnectionState.disconnected => (
        'Disconnected',
        context.elixTextSecondary,
        0.08,
        0.22,
      ),
    };

    return Semantics(
      label: 'Connection status: $label',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: bgAlpha),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: borderAlpha)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey<String>(label),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: showSpinner
                    ? ProgressRing(strokeWidth: 2, activeColor: color)
                    : Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow:
                                state == WebSocketConnectionState.connected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.45),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTheme.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
