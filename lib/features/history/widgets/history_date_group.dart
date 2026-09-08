import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../data/models/session.dart';
import 'history_session_row.dart';

class HistoryDateGroup extends StatelessWidget {
  const HistoryDateGroup({
    super.key,
    required this.label,
    required this.sessions,
  });

  final String label;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final countLabel =
        '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: ElixTypography.fontFamily,
                    fontFamilyFallback: ElixTypography.fontFallbacks,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Container(
                    height: 1,
                    color: context.elixBorder.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  countLabel,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < sessions.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == sessions.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: HistorySessionRow(session: sessions[i]),
            ),
        ],
      ),
    );
  }
}
