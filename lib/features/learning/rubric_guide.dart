import 'package:fluent_ui/fluent_ui.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class RubricGuide extends StatelessWidget {
  const RubricGuide({super.key, this.compact = false});
  final bool compact;
  static const criteria = <(String, String)>[
    (
      'Technique',
      'Whether the movement-specific body and hand form is correct.',
    ),
    ('Stability', 'Whether the prop remains controlled and steady.'),
    ('Completion', 'Progress toward and completion of the confirmed hold.'),
    (
      'Prop Positioning',
      'Whether the prop is aligned with the correct grip or stall point.',
    ),
  ];
  static String scoreMeaning(int score) => switch (score) {
    0 => 'Not demonstrated or not enough valid evidence.',
    1 => 'Demonstrated briefly.',
    2 => 'Demonstrated partially or inconsistently.',
    _ => 'Demonstrated consistently with enough observation.',
  };
  static String performanceBand(int total) => switch (total) {
    <= 3 => 'Beginning',
    <= 6 => 'Developing',
    <= 9 => 'Competent',
    <= 11 => 'Proficient',
    _ => 'Mastered',
  };
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How scoring works', style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Visibility problems do not lower scores; they prevent ELIXR from collecting valid evidence.',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final c in criteria)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('${c.$1}: ${c.$2}'),
            ),
          if (!compact) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '0 not demonstrated • 1 briefly • 2 partly/inconsistently • 3 consistently',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '0–3 Beginning • 4–6 Developing • 7–9 Competent • 10–11 Proficient • 12 Mastered',
            ),
          ],
        ],
      ),
    ),
  );
}
