import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextSecondary,
                ),
              ),
              const Spacer(),
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
        Container(
          height: 1,
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          color: context.elixBorder.withValues(alpha: 0.7),
        ),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: HistorySessionRow(session: session),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
