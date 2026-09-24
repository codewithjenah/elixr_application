import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../freestyle/freestyle_models.dart';

class FreestyleSummarySheet {
  const FreestyleSummarySheet._();

  static Future<bool?> show(
    BuildContext context, {
    required FreestyleSessionStats stats,
    required int durationSeconds,
    required VoidCallback onDone,
  }) {
    return ElixDialog.show<bool>(
      context,
      title: 'Endless Run Summary',
      barrierDismissible: true,
      maxWidth: 520,
      scrollableContent: true,
      content: _SummaryBody(stats: stats, durationSeconds: durationSeconds),
      actions: [
        Button(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: const Text('Play Again'),
        ),
        ElixPrimaryButton(
          label: 'Done',
          expanded: true,
          onPressed: () {
            Navigator.of(context, rootNavigator: true).pop(false);
            onDone();
          },
        ),
      ],
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.stats, required this.durationSeconds});

  final FreestyleSessionStats stats;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    final props = stats.props.isEmpty
        ? 'None detected'
        : stats.props.map((prop) => prop.displayLabel).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Session stats stay on this device. Nothing was saved to mastery or XP.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final row in [
          ('Successful targets', '${stats.movementsRecognized + stats.flips}'),
          ('Missed targets', '${stats.missed}'),
          ('Run score', '${stats.runScore}'),
          ('Unique movements', '${stats.uniqueUnlockedMovements}'),
          ('Perfect', '${stats.perfect}'),
          ('Great', '${stats.great}'),
          ('Nice', '${stats.nice}'),
          ('Best combo', '${stats.bestCombo}'),
          if (stats.advancedTechniques > 0)
            ('Advanced technique', '${stats.advancedTechniques}'),
          ('Props', props),
          ('Duration', '$minutes:$seconds'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.right,
                    style: AppTheme.body.copyWith(
                      color: context.elixTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
