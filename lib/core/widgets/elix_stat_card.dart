import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'elix_card.dart';

class ElixStatCard extends StatelessWidget {
  const ElixStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.smallValue = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool smallValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      variant: ElixCardVariant.metric,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.elixColors.brandPrimary, size: 24),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: smallValue
                ? AppTheme.cardTitle(
                    color: valueColor ?? context.elixTextPrimary,
                  )
                : AppTheme.metric(
                    context,
                    color: valueColor ?? context.elixTextPrimary,
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTheme.supporting(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }
}
