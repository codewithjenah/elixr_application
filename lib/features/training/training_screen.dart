import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../calendar/calendar_screen.dart';
import '../history/history_screen.dart';
import 'training_view.dart';

const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;

/// Top-level Training shell. Planner and History stay distinct internal views.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({
    super.key,
    required this.view,
    this.date,
    this.planner,
    this.history,
  });

  final TrainingView view;
  final String? date;

  /// Optional test override for the Planner pane.
  final Widget? planner;

  /// Optional test override for the History pane.
  final Widget? history;

  void _selectView(BuildContext context, TrainingView next) {
    if (next == view) return;
    context.go(trainingLocation(view: next));
  }

  @override
  Widget build(BuildContext context) {
    final plannerView =
        planner ?? CalendarScreen(embedded: true, initialDate: date);
    final historyView =
        history ?? HistoryScreen(embedded: true, initialDate: date);

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.pageTopInset,
                AppSpacing.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TrainingHeader(),
                  const SizedBox(height: AppSpacing.md),
                  _TrainingViewSelector(
                    view: view,
                    onChanged: (next) => _selectView(context, next),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: view.isHistory ? 1 : 0,
                sizing: StackFit.expand,
                children: [plannerView, historyView],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingHeader extends StatelessWidget {
  const _TrainingHeader();

  @override
  Widget build(BuildContext context) {
    return ElixEditorialHeader(
      heading: 'Sessions',
      eyebrow: 'TRAINING',
      subtitle: 'Plan your practice and review completed sessions.',
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(
            alpha: context.isDarkTheme ? 0.18 : 0.10,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.26)),
        ),
        child: const Icon(
          FluentIcons.calendar_agenda,
          size: 20,
          color: _violet,
        ),
      ),
    );
  }
}

class _TrainingViewSelector extends StatelessWidget {
  const _TrainingViewSelector({required this.view, required this.onChanged});

  final TrainingView view;
  final ValueChanged<TrainingView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.elixCardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.elixBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TrainingViewTab(
                key: const ValueKey('training-view-planner'),
                label: 'Planner',
                selected: view.isPlanner,
                onTap: () => onChanged(TrainingView.planner),
              ),
              _TrainingViewTab(
                key: const ValueKey('training-view-history'),
                label: 'History',
                selected: view.isHistory,
                onTap: () => onChanged(TrainingView.history),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingViewTab extends StatefulWidget {
  const _TrainingViewTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TrainingViewTab> createState() => _TrainingViewTabState();
}

class _TrainingViewTabState extends State<_TrainingViewTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? _pink.withValues(alpha: context.isDarkTheme ? 0.20 : 0.14)
                  : (_hovered
                        ? context.elixBorder.withValues(alpha: 0.18)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? _pink
                    : (_hovered
                          ? context.elixTextPrimary
                          : context.elixTextSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
