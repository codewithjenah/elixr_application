import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import 'rubric_guide.dart';

class LearningCenterScreen extends StatelessWidget {
  const LearningCenterScreen({super.key});
  @override
  Widget build(BuildContext context) => ElixScaffoldPage(
    header: const PageHeader(title: Text('Help & Tutorials')),
    content: ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Learn at your own pace. Tutorials never open over your camera session.',
          style: AppTheme.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Camera setup', style: AppTheme.headingMedium),
                const SizedBox(height: 8),
                const Text(
                  'Camera setup checks that your camera, prop, and required body parts are visible. It is not scored. After the visibility check and countdown, guided practice begins.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'If setup cannot start, check the selected camera in Settings and make sure no other app is using it.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const RubricGuide(),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guided Practice and Live Practice',
                  style: AppTheme.headingMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Guided Practice records a scored session. Live Practice is unscored freestyle practice and is best after you know a movement.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Movement lessons', style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final movement in movementCatalog.where((m) => m.enabled))
          ListTile(
            title: Text(movement.name),
            subtitle: Text(movement.difficulty),
            trailing: const Icon(FluentIcons.chevron_right),
            onPressed: () => context.go(
              '/learn/movement/${Uri.encodeComponent(movement.name)}?difficulty=${movement.difficulty}&prop=${movement.supportedProps.first.protocolValue}',
            ),
          ),
      ],
    ),
  );
}
