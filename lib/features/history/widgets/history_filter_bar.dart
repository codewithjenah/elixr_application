import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../history_format.dart';

class HistoryFilterBar extends StatelessWidget {
  const HistoryFilterBar({
    super.key,
    required this.difficultyFilter,
    required this.searchQuery,
    required this.sortMode,
    required this.hasActiveFilters,
    required this.onDifficultyChanged,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onClearFilters,
    this.dateFilterLabel,
    this.onDateFilterCleared,
  });

  final String? difficultyFilter;
  final String searchQuery;
  final HistorySortMode sortMode;
  final String? dateFilterLabel;
  final bool hasActiveFilters;
  final ValueChanged<String?> onDifficultyChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<HistorySortMode> onSortChanged;
  final VoidCallback onClearFilters;
  final VoidCallback? onDateFilterCleared;

  static const _difficulties = ['All', 'Easy', 'Medium', 'Hard'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final difficultyRow = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (dateFilterLabel != null)
              _DifficultyChip(
                label: dateFilterLabel!,
                selected: true,
                color: AppColors.accent,
                onTap: onDateFilterCleared ?? onClearFilters,
              ),
            for (final opt in _difficulties)
              _DifficultyChip(
                label: opt,
                selected: opt == 'All'
                    ? difficultyFilter == null
                    : difficultyFilter == opt,
                color: opt == 'All' ? AppColors.accent : difficultyColor(opt),
                onTap: () => onDifficultyChanged(opt == 'All' ? null : opt),
              ),
          ],
        );

        final sortAndClear = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ComboBox<HistorySortMode>(
              value: sortMode,
              items: [
                for (final mode in HistorySortMode.values)
                  ComboBoxItem<HistorySortMode>(
                    value: mode,
                    child: _SortModeOptionRow(mode: mode),
                  ),
              ],
              selectedItemBuilder: (context) {
                return [
                  for (final mode in HistorySortMode.values)
                    _SortModeOptionRow(mode: mode),
                ];
              },
              onChanged: (mode) {
                if (mode != null) onSortChanged(mode);
              },
            ),
            if (hasActiveFilters) ...[
              const SizedBox(width: AppSpacing.sm),
              HyperlinkButton(
                onPressed: onClearFilters,
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              difficultyRow,
              const SizedBox(height: AppSpacing.sm),
              _SyncedSearchField(
                query: searchQuery,
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              sortAndClear,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: difficultyRow),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 220,
                  child: _SyncedSearchField(
                    query: searchQuery,
                    onChanged: onSearchChanged,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                sortAndClear,
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SortModeOptionRow extends StatelessWidget {
  const _SortModeOptionRow({required this.mode});

  final HistorySortMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(mode.icon, size: 13, color: context.elixTextSecondary),
        ),
        const SizedBox(width: 8),
        Text(mode.label),
      ],
    );
  }
}

/// TextBox that mirrors [query] when Clear Filters empties the parent string.
class _SyncedSearchField extends StatefulWidget {
  const _SyncedSearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<_SyncedSearchField> createState() => _SyncedSearchFieldState();
}

class _SyncedSearchFieldState extends State<_SyncedSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _SyncedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection = TextSelection.collapsed(
        offset: widget.query.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextBox(
      controller: _controller,
      placeholder: 'Search movements',
      prefix: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(
          FluentIcons.search,
          size: 14,
          color: context.elixTextSecondary,
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _DifficultyChip extends StatefulWidget {
  const _DifficultyChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_DifficultyChip> createState() => _DifficultyChipState();
}

class _DifficultyChipState extends State<_DifficultyChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? widget.color.withValues(
                    alpha: context.isDarkTheme ? 0.22 : 0.16,
                  )
                : (_hovered ? context.elixCardSurface : context.elixBackground),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? widget.color.withValues(alpha: 0.55)
                  : context.elixBorder,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? widget.color : context.elixTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
