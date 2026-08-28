import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(
                  alpha: context.isDarkTheme ? 0.2 : 0.12,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FluentIcons.history,
                size: 36,
                color: AppColors.accentSoft,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No training sessions yet',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Sessions appear here after you complete practice.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => context.go('/movements'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.grid_view_medium, size: 14),
                  SizedBox(width: 8),
                  Text('Browse Movements'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryNoResultsState extends StatelessWidget {
  const HistoryNoResultsState({super.key, required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.filter,
              size: 32,
              color: context.elixTextSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No sessions found',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Try a different difficulty, search term, or sort order.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Button(
              onPressed: onClearFilters,
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryLoadingSkeleton extends StatelessWidget {
  const HistoryLoadingSkeleton({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding ?? const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: List.generate(
            4,
            (_) => _SkeletonBox(width: 200, height: 72, borderRadius: 18),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SkeletonBox(
          width: double.infinity,
          height: 40,
          borderRadius: 12,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < 6; i++) ...[
          const _SkeletonBox(
            width: double.infinity,
            height: 56,
            borderRadius: 12,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.6)),
      ),
    );
  }
}
