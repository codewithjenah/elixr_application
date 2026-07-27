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
    final (label, color) = switch (state) {
      WebSocketConnectionState.connected => (
        'Camera Connected',
        AppColors.success,
      ),
      WebSocketConnectionState.connecting => ('Connecting', AppColors.warning),
      WebSocketConnectionState.error => ('Connection Error', AppColors.error),
      WebSocketConnectionState.disconnected => (
        'Disconnected',
        context.elixTextSecondary,
      ),
    };

    final showSpinner =
        connecting || state == WebSocketConnectionState.connecting;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: showSpinner
                ? const ProgressRing(strokeWidth: 2)
                : Center(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTheme.body.copyWith(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
