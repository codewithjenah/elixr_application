import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';

/// Progress is the stable entry point for the two existing Teacher reports.
///
/// Analytics and Leaderboard keep their original routes and controllers so
/// existing bookmarks remain valid while new Teachers get one clear place to
/// find class progress and student rankings.
class TeacherProgressScreen extends StatelessWidget {
  const TeacherProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TeacherScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: 'Progress',
        eyebrow: 'TEACHER WORKSPACE',
        subtitle: 'Track class practice and celebrate student growth.',
      ),
      content: _ProgressChoices(),
    );
  }
}

class _ProgressChoices extends StatelessWidget {
  const _ProgressChoices();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final cardWidth = wide
            ? (constraints.maxWidth - AppSpacing.lg) / 2
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a progress view',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start with class trends or look closer at individual student rankings.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _ProgressChoiceCard(
                    key: const Key('teacher_progress_class_progress'),
                    icon: FluentIcons.analytics_view,
                    title: 'Class progress',
                    message:
                        'See practice trends, completion, scores, and comparisons across your classrooms.',
                    actionLabel: 'View class progress',
                    onPressed: () => context.go(AppRoutePaths.teacherAnalytics),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _ProgressChoiceCard(
                    key: const Key('teacher_progress_student_rankings'),
                    icon: FluentIcons.trophy2_solid,
                    title: 'Student rankings',
                    message:
                        'Celebrate steady training progress with global, student, and classroom rankings.',
                    actionLabel: 'View student rankings',
                    onPressed: () =>
                        context.go(AppRoutePaths.teacherLeaderboard),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProgressChoiceCard extends StatelessWidget {
  const _ProgressChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      accent: context.elixColors.brandPrimary,
      showAccentBar: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: context.elixColors.brandPrimary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: AppTheme.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
