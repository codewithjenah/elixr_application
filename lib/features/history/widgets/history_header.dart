import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

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
          borderRadius: BorderRadius.circular(ElixRadius.card),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
        ),
        child: Icon(FluentIcons.history, size: 20, color: AppColors.accentSoft),
      ),
      actions: [HistoryRefreshButton(loading: loading, onPressed: onRefresh)],
    );
  }
}

class HistoryRefreshButton extends StatelessWidget {
  const HistoryRefreshButton({
    super.key,
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = AnimatedRotation(
      turns: loading ? 1 : 0,
      duration: ElixMotion.duration(context, ElixMotion.micro),
      child: Icon(
        FluentIcons.refresh,
        size: 16,
        color: loading ? context.elixTextSecondary : AppColors.accentSoft,
      ),
    );
    final enabled = !loading;
    final button =
        context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
        ? IconButton(icon: icon, onPressed: enabled ? onPressed : null)
        : shad.ShadIconButton.ghost(
            icon: icon,
            onPressed: enabled ? onPressed : null,
          );
    final tooltip =
        context.isHighContrast || shad.ShadTheme.maybeOf(context) == null
        ? Tooltip(message: 'Refresh sessions', child: button)
        : shad.ShadTooltip(
            builder: (context) => const Text('Refresh sessions'),
            child: button,
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Refresh sessions',
      child: tooltip,
    );
  }
}
