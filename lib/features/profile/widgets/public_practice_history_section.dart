import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/public_profile_session.dart';
import '../../../data/models/training_prop.dart';
import '../../history/history_format.dart';

class PublicPracticeHistorySection extends StatelessWidget {
  const PublicPracticeHistorySection({
    super.key,
    required this.sessions,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final List<PublicProfileSession> sessions;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? AppColors.panelSurface
            : context.elixCardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Practice History',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (sessions.isEmpty)
            Text(
              'No practice sessions to show yet.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            )
          else ...[
            for (var i = 0; i < sessions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _HistoryRow(session: sessions[i]),
            ],
            if (hasMore) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: isLoadingMore
                    ? const ProgressRing(activeColor: AppColors.primary)
                    : Button(
                        onPressed: onLoadMore,
                        child: const Text('Load More'),
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.session});

  final PublicProfileSession session;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(session.createdAt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.movementName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session.difficulty} • '
                  '${session.score} pts • '
                  '${formatTrainingDuration(session.durationSeconds)} • '
                  '${_propLabel(session.propType)}'
                  '${dateLabel != null ? ' • $dateLabel' : ''}',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateFormat.yMMMd().add_jm().format(parsed.toLocal());
  }

  String _propLabel(TrainingProp prop) {
    return switch (prop) {
      TrainingProp.bottle => 'Bottle',
      TrainingProp.shaker => 'Cocktail Shaker',
      TrainingProp.bottleAndShaker => 'Bottle + Shaker',
    };
  }
}
