import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// Status copy that always includes an icon so warning/selected/milestone
/// states never rely on colour alone.
class ElixToneLabel extends StatelessWidget {
  const ElixToneLabel({super.key, required this.tone, required this.label});

  final ElixTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ElixToneCues.color(context.elixColors, tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ElixToneCues.icon(tone), size: 14, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTheme.supporting(color: color)),
      ],
    );
  }
}
