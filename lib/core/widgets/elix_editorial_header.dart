import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

enum ElixEditorialHeaderVariant { hero, standard, compact, document }

/// A Fluent [PageHeader] with ELIXR's editorial title hierarchy.
///
/// It keeps Fluent's command bar and back-button behavior available to screen
/// call sites while avoiding a second page-header visual language.
class ElixEditorialPageHeader extends StatelessWidget {
  const ElixEditorialPageHeader({
    super.key,
    required this.heading,
    this.eyebrow,
    this.subtitle,
    this.variant = ElixEditorialHeaderVariant.standard,
    this.commandBar,
    this.leading,
  });

  final String heading;
  final String? eyebrow;
  final String? subtitle;
  final ElixEditorialHeaderVariant variant;
  final CommandBar? commandBar;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => PageHeader(
    title: ElixEditorialHeader(
      heading: heading,
      eyebrow: eyebrow,
      subtitle: subtitle,
      variant: variant,
      leading: leading,
    ),
    commandBar: commandBar,
  );
}

/// Content for use inside a Fluent [PageHeader] or page body.
///
/// This widget deliberately does not replace Fluent's page or scaffold APIs.
/// It only provides a consistent editorial hierarchy within them.
class ElixEditorialHeader extends StatelessWidget {
  const ElixEditorialHeader({
    super.key,
    required this.heading,
    this.variant = ElixEditorialHeaderVariant.standard,
    this.eyebrow,
    this.accentHeading,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String heading;
  final ElixEditorialHeaderVariant variant;
  final String? eyebrow;
  final String? accentHeading;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final copy = _HeaderCopy(
      heading: heading,
      accentHeading: accentHeading,
      eyebrow: eyebrow,
      subtitle: subtitle,
      headingStyle: _headingStyle(context),
      headingMaxLines: _headingMaxLines(context),
      leading: leading,
    );
    if (actions.isEmpty) return copy;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 720;
        final actionWrap = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: stackActions ? WrapAlignment.start : WrapAlignment.end,
          children: actions,
        );
        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              actionWrap,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.lg),
            Flexible(child: actionWrap),
          ],
        );
      },
    );
  }

  TextStyle _headingStyle(BuildContext context) {
    final color = context.elixTextPrimary;
    return switch (variant) {
      ElixEditorialHeaderVariant.hero => AppTheme.displayHero(
        context,
        color: color,
      ),
      ElixEditorialHeaderVariant.standard => AppTheme.pageTitle(
        context,
        color: color,
      ),
      ElixEditorialHeaderVariant.compact => AppTheme.sectionTitle(
        context,
        color: color,
      ),
      ElixEditorialHeaderVariant.document => AppTheme.pageTitle(
        context,
        color: color,
      ),
    };
  }

  int _headingMaxLines(BuildContext context) => switch (variant) {
    ElixEditorialHeaderVariant.hero =>
      ElixTypography.isCompact(context) ? 3 : 2,
    ElixEditorialHeaderVariant.document => 3,
    ElixEditorialHeaderVariant.standard ||
    ElixEditorialHeaderVariant.compact => 2,
  };
}

/// A smaller editorial heading for a section inside a page or panel.
class ElixSectionHeader extends StatelessWidget {
  const ElixSectionHeader({
    super.key,
    required this.heading,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
  });

  final String heading;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => ElixEditorialHeader(
    heading: heading,
    variant: ElixEditorialHeaderVariant.compact,
    eyebrow: eyebrow,
    subtitle: subtitle,
    actions: actions,
  );
}

class _HeaderCopy extends StatelessWidget {
  const _HeaderCopy({
    required this.heading,
    required this.accentHeading,
    required this.eyebrow,
    required this.subtitle,
    required this.headingStyle,
    required this.headingMaxLines,
    required this.leading,
  });

  final String heading;
  final String? accentHeading;
  final String? eyebrow;
  final String? subtitle;
  final TextStyle headingStyle;
  final int headingMaxLines;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: AppTheme.eyebrow(color: context.elixColors.brandPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Semantics(
          header: true,
          label: '$heading${accentHeading ?? ''}',
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                style: headingStyle,
                children: [
                  TextSpan(text: heading),
                  if (accentHeading != null)
                    TextSpan(
                      text: accentHeading,
                      style: headingStyle.copyWith(
                        color: context.elixColors.brandPrimary,
                      ),
                    ),
                ],
              ),
              maxLines: headingMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: AppTheme.supporting(color: context.elixTextSecondary),
          ),
        ],
      ],
    );
    if (leading == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading!,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: text),
      ],
    );
  }
}
