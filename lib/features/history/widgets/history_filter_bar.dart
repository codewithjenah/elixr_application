import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../history_format.dart';
import 'history_header.dart';

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
    this.loading = false,
    this.onRefresh,
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
  final bool loading;
  final VoidCallback? onRefresh;

  static const _difficulties = ['All', 'Easy', 'Medium', 'Hard'];
  static const _stackBreakpoint = 780.0;
  static const _controlHeight = 34.0;
  static const _controlRadius = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < _stackBreakpoint;
        final chips = Wrap(
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
                dismissible: true,
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

        final search = SizedBox(
          width: stacked ? double.infinity : 220,
          child: _SyncedSearchField(
            query: searchQuery,
            onChanged: onSearchChanged,
          ),
        );

        final tools = Row(
          mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (stacked) Expanded(child: search) else search,
            const SizedBox(width: AppSpacing.sm),
            _SortControl(sortMode: sortMode, onSortChanged: onSortChanged),
            if (hasActiveFilters) ...[
              const SizedBox(width: AppSpacing.sm),
              HyperlinkButton(
                onPressed: onClearFilters,
                child: const Text('Clear Filters'),
              ),
            ],
            if (onRefresh != null) ...[
              const SizedBox(width: AppSpacing.sm),
              HistoryRefreshButton(loading: loading, onPressed: onRefresh!),
            ],
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chips,
              const SizedBox(height: AppSpacing.sm),
              tools,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: chips),
            const SizedBox(width: AppSpacing.md),
            tools,
          ],
        );
      },
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.sortMode, required this.onSortChanged});

  final HistorySortMode sortMode;
  final ValueChanged<HistorySortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return ComboBox<HistorySortMode>(
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
    this.dismissible = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool dismissible;

  @override
  State<_DifficultyChip> createState() => _DifficultyChipState();
}

class _DifficultyChipState extends State<_DifficultyChip> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final highContrast = context.isHighContrast;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.dismissible
          ? 'Clear ${widget.label} date filter'
          : widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            height: HistoryFilterBar._controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? widget.color.withValues(
                      alpha: context.isDarkTheme ? 0.22 : 0.16,
                    )
                  : (_hovered
                        ? context.elixCardSurface
                        : context.elixBackground),
              borderRadius: BorderRadius.circular(
                HistoryFilterBar._controlRadius,
              ),
              border: Border.all(
                color: _focused
                    ? context.elixColors.focusRing
                    : selected
                    ? widget.color.withValues(alpha: 0.55)
                    : (_hovered && !highContrast
                          ? widget.color.withValues(alpha: 0.35)
                          : context.elixBorder),
                width: _focused
                    ? (highContrast
                          ? ElixFocus.ringWidthHighContrast
                          : ElixFocus.ringWidth)
                    : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? widget.color : context.elixTextSecondary,
                  ),
                ),
                if (widget.dismissible) ...[
                  const SizedBox(width: 6),
                  Icon(
                    FluentIcons.chrome_close,
                    size: 8,
                    color: selected ? widget.color : context.elixTextSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
