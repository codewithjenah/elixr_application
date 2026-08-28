import 'dart:math' as math;

import 'package:elixr_core/legal/legal_documents.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_scaffold_page.dart';

const _kWideReaderBreakpoint = 900.0;
const _kReaderMaxWidth = 1320.0;

/// Responsive, one-section-at-a-time reader for a legal document.
class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.lastUpdated,
    required this.version,
  });

  final String title;
  final String subtitle;
  final List<ElixrLegalSection> sections;
  final String lastUpdated;
  final String version;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  late List<FocusNode> _sectionFocusNodes;
  var _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _sectionFocusNodes = _createFocusNodes(widget.sections);
  }

  @override
  void didUpdateWidget(covariant LegalDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections.length != widget.sections.length) {
      _disposeFocusNodes();
      _sectionFocusNodes = _createFocusNodes(widget.sections);
    }
    if (widget.sections.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.sections.length) {
      _selectedIndex = widget.sections.length - 1;
    }
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    super.dispose();
  }

  List<FocusNode> _createFocusNodes(List<ElixrLegalSection> sections) {
    return [
      for (var i = 0; i < sections.length; i++)
        FocusNode(debugLabel: 'Legal section ${i + 1}'),
    ];
  }

  void _disposeFocusNodes() {
    for (final node in _sectionFocusNodes) {
      node.dispose();
    }
  }

  void _selectSection(int index) {
    if (index < 0 || index >= widget.sections.length) return;
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
    _sectionFocusNodes[index].requestFocus();
  }

  void _moveSection(int delta) {
    if (widget.sections.isEmpty) return;
    final nextIndex = (_selectedIndex + delta).clamp(
      0,
      widget.sections.length - 1,
    );
    _selectSection(nextIndex);
  }

  KeyEventResult _handleDocumentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveSection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveSection(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSectionKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _selectSection(index);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _selectSection((index + 1).clamp(0, widget.sections.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _selectSection((index - 1).clamp(0, widget.sections.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutePaths.register);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.elixReaderHorizontalPadding,
            context.elixReaderVerticalPadding,
            context.elixReaderHorizontalPadding,
            AppSpacing.xs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(constraints.maxWidth, _kReaderMaxWidth);
              return Center(
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LegalDocumentHeader(
                        title: widget.title,
                        subtitle: widget.subtitle,
                        lastUpdated: widget.lastUpdated,
                        version: widget.version,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        child: Focus(
                          onKeyEvent: _handleDocumentKey,
                          child: _LegalReaderBody(
                            sections: widget.sections,
                            selectedIndex: _selectedIndex,
                            sectionFocusNodes: _sectionFocusNodes,
                            onSelectSection: _selectSection,
                            onSectionKey: _handleSectionKey,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Center(child: _LegalDocumentFooter(onTap: _goBack)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LegalDocumentFooter extends StatelessWidget {
  const _LegalDocumentFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Done reading? Go back',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Done reading?',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          HyperlinkButton(onPressed: onTap, child: const Text('Go back')),
        ],
      ),
    );
  }
}

extension on BuildContext {
  double get elixReaderHorizontalPadding {
    final width = MediaQuery.sizeOf(this).width;
    return width < 680 ? AppSpacing.md : AppSpacing.xl;
  }

  double get elixReaderVerticalPadding {
    final height = MediaQuery.sizeOf(this).height;
    return height < 700 ? AppSpacing.sm : AppSpacing.lg;
  }
}

class _LegalDocumentHeader extends StatelessWidget {
  const _LegalDocumentHeader({
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.version,
  });

  final String title;
  final String subtitle;
  final String lastUpdated;
  final String version;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final heading = ElixEditorialHeader(
          heading: title,
          subtitle: subtitle,
          variant: ElixEditorialHeaderVariant.document,
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? context.elixCardSurface
                  : context.elixColors.brandPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: context.isHighContrast
                    ? context.elixBorder
                    : context.elixColors.brandPrimary.withValues(alpha: 0.32),
                width: context.isHighContrast ? 2 : 1,
              ),
            ),
            child: Icon(
              FluentIcons.shield,
              size: 21,
              color: context.elixColors.brandPrimary,
            ),
          ),
        );
        final badges = Wrap(
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            ElixPill(
              text: 'Last updated $lastUpdated',
              color: context.elixColors.brandPrimary,
              compact: true,
            ),
            ElixPill(
              text: 'Version $version',
              color: context.elixColors.brandSecondary,
              compact: true,
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: AppSpacing.sm),
              badges,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.lg),
            badges,
          ],
        );
      },
    );
  }
}

class _LegalReaderBody extends StatelessWidget {
  const _LegalReaderBody({
    required this.sections,
    required this.selectedIndex,
    required this.sectionFocusNodes,
    required this.onSelectSection,
    required this.onSectionKey,
  });

  final List<ElixrLegalSection> sections;
  final int selectedIndex;
  final List<FocusNode> sectionFocusNodes;
  final ValueChanged<int> onSelectSection;
  final KeyEventResult Function(int index, KeyEvent event) onSectionKey;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return AuthFormCard(
        child: Center(
          child: Text(
            'This document is not available.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _kWideReaderBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _LegalSectionRail(
                  sections: sections,
                  selectedIndex: selectedIndex,
                  focusNodes: sectionFocusNodes,
                  onSelectSection: onSelectSection,
                  onSectionKey: onSectionKey,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _LegalSectionCard(
                  section: sections[selectedIndex],
                  index: selectedIndex,
                  total: sections.length,
                  onPrevious: selectedIndex == 0
                      ? null
                      : () => onSelectSection(selectedIndex - 1),
                  onNext: selectedIndex == sections.length - 1
                      ? null
                      : () => onSelectSection(selectedIndex + 1),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 50,
              child: _LegalSectionChips(
                sections: sections,
                selectedIndex: selectedIndex,
                focusNodes: sectionFocusNodes,
                onSelectSection: onSelectSection,
                onSectionKey: onSectionKey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _LegalSectionCard(
                section: sections[selectedIndex],
                index: selectedIndex,
                total: sections.length,
                onPrevious: selectedIndex == 0
                    ? null
                    : () => onSelectSection(selectedIndex - 1),
                onNext: selectedIndex == sections.length - 1
                    ? null
                    : () => onSelectSection(selectedIndex + 1),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LegalSectionRail extends StatelessWidget {
  const _LegalSectionRail({
    required this.sections,
    required this.selectedIndex,
    required this.focusNodes,
    required this.onSelectSection,
    required this.onSectionKey,
  });

  final List<ElixrLegalSection> sections;
  final int selectedIndex;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onSelectSection;
  final KeyEventResult Function(int index, KeyEvent event) onSectionKey;

  @override
  Widget build(BuildContext context) {
    return AuthFormCard(
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IN THIS DOCUMENT',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < sections.length; i++) ...[
            _LegalSectionSelector(
              section: sections[i],
              index: i,
              selected: i == selectedIndex,
              dense: true,
              focusNode: focusNodes[i],
              onPressed: () => onSelectSection(i),
              onKeyEvent: (node, event) => onSectionKey(i, event),
            ),
            if (i < sections.length - 1)
              const SizedBox(height: AppSpacing.xs - 2),
          ],
        ],
      ),
    );
  }
}

class _LegalSectionChips extends StatelessWidget {
  const _LegalSectionChips({
    required this.sections,
    required this.selectedIndex,
    required this.focusNodes,
    required this.onSelectSection,
    required this.onSectionKey,
  });

  final List<ElixrLegalSection> sections;
  final int selectedIndex;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onSelectSection;
  final KeyEventResult Function(int index, KeyEvent event) onSectionKey;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _LegalChipScrollBehavior(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              _LegalSectionSelector(
                section: sections[i],
                index: i,
                selected: i == selectedIndex,
                compact: true,
                focusNode: focusNodes[i],
                onPressed: () => onSelectSection(i),
                onKeyEvent: (node, event) => onSectionKey(i, event),
              ),
              if (i < sections.length - 1) const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegalChipScrollBehavior extends ScrollBehavior {
  const _LegalChipScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _LegalSectionSelector extends StatefulWidget {
  const _LegalSectionSelector({
    required this.section,
    required this.index,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    required this.onKeyEvent,
    this.compact = false,
    this.dense = false,
  });

  final ElixrLegalSection section;
  final int index;
  final bool selected;
  final bool compact;
  final bool dense;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKeyEvent;

  @override
  State<_LegalSectionSelector> createState() => _LegalSectionSelectorState();
}

class _LegalSectionSelectorState extends State<_LegalSectionSelector> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered || _focused;
    final highContrast = context.isHighContrast;
    final borderColor = widget.selected
        ? (highContrast ? context.elixBorder : context.elixColors.brandPrimary)
        : active
        ? (highContrast
              ? context.elixBorder
              : context.elixBorder.withValues(alpha: 0.8))
        : (highContrast ? context.elixBackground : Colors.transparent);
    final backgroundColor = widget.selected
        ? (highContrast
              ? context.elixCardSurface
              : context.elixColors.brandPrimary.withValues(
                  alpha: context.isDarkTheme ? 0.15 : 0.10,
                ))
        : _hovered
        ? (highContrast
              ? context.elixCardSurface
              : context.elixBorder.withValues(alpha: 0.08))
        : (highContrast ? context.elixBackground : Colors.transparent);

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: 'Section ${widget.index + 1}: ${widget.section.title}',
      hint: widget.selected
          ? 'Currently selected'
          : 'Activate to read this section',
      child: Focus(
        key: ValueKey('legal_toc_${widget.section.id}'),
        focusNode: widget.focusNode,
        autofocus: widget.index == 0,
        onFocusChange: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        onKeyEvent: widget.onKeyEvent,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: ElixMotion.duration(context, ElixMotion.micro),
              curve: Curves.easeOutCubic,
              width: widget.compact ? null : double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense
                    ? AppSpacing.xs + 2
                    : widget.compact
                    ? AppSpacing.sm + 2
                    : AppSpacing.sm,
                vertical: widget.dense
                    ? AppSpacing.xs - 1
                    : widget.compact
                    ? AppSpacing.sm
                    : AppSpacing.sm - 1,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: borderColor,
                  width: highContrast && active ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: widget.compact
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                children: [
                  _SectionNumber(
                    number: widget.index + 1,
                    selected: widget.selected,
                    compact: widget.compact,
                    dense: widget.dense,
                  ),
                  SizedBox(width: widget.dense ? AppSpacing.xs : AppSpacing.sm),
                  if (widget.compact)
                    Text(
                      widget.section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySecondary.copyWith(
                        color: context.elixTextPrimary,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        widget.section.title,
                        maxLines: widget.dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySecondary.copyWith(
                          color: context.elixTextPrimary,
                          fontSize: widget.dense ? 13 : null,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          height: widget.dense ? 1.1 : 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionNumber extends StatelessWidget {
  const _SectionNumber({
    required this.number,
    required this.selected,
    required this.compact,
    required this.dense,
  });

  final int number;
  final bool selected;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final color = selected
        ? (highContrast
              ? context.elixTextPrimary
              : context.elixColors.brandPrimary)
        : (highContrast
              ? context.elixTextPrimary
              : context.elixColors.brandSecondary);
    return Container(
      width: dense
          ? 22
          : compact
          ? 25
          : 28,
      height: dense
          ? 22
          : compact
          ? 25
          : 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : selected
            ? color.withValues(alpha: 0.14)
            : context.elixBorder.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? color : context.elixBorder,
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Text(
        '$number',
        style: AppTheme.caption.copyWith(
          color: selected ? context.elixTextPrimary : color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LegalSectionCard extends StatelessWidget {
  const _LegalSectionCard({
    required this.section,
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final ElixrLegalSection section;
  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;
    return AuthFormCard(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        compact ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.lg,
        compact ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _iconForLegalSection(section.id),
                size: 17,
                color: context.isHighContrast
                    ? context.elixTextPrimary
                    : context.elixColors.brandSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'LEGAL SECTION',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: ElixMotion.duration(context, ElixMotion.route),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(0.025, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: Align(
                key: ValueKey(section.id),
                alignment: Alignment.topLeft,
                child: _LegalSectionContent(section: section, compact: compact),
              ),
            ),
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
          Container(
            height: 1,
            color: context.isHighContrast
                ? context.elixBorder
                : context.elixBorder.withValues(alpha: 0.45),
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
          Text(
            'Section ${index + 1} of $total',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Button(
                  onPressed: onPrevious,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.chevron_left, size: 13),
                      SizedBox(width: AppSpacing.xs),
                      Text('Previous'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onNext,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next'),
                      SizedBox(width: AppSpacing.xs),
                      Icon(FluentIcons.chevron_right, size: 13),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegalSectionContent extends StatelessWidget {
  const _LegalSectionContent({required this.section, required this.compact});

  final ElixrLegalSection section;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: _LegalSectionCopy(section: section, compact: compact),
          ),
        );
      },
    );
  }
}

class _LegalSectionCopy extends StatelessWidget {
  const _LegalSectionCopy({required this.section, required this.compact});

  final ElixrLegalSection section;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: AppTheme.headingMedium.copyWith(
              color: context.elixTextPrimary,
              fontSize: compact ? 26 : 24,
              height: 1.15,
            ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          for (var i = 0; i < section.paragraphs.length; i++) ...[
            Text(
              section.paragraphs[i],
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
                fontSize: compact ? 15 : null,
                height: compact ? 1.35 : 1.45,
              ),
            ),
            if (i < section.paragraphs.length - 1)
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

IconData _iconForLegalSection(String id) {
  if (id.contains('camera') || id.contains('vision')) {
    return FluentIcons.camera;
  }
  if (id.contains('photo') || id.contains('image')) {
    return FluentIcons.camera;
  }
  if (id.contains('message') || id.contains('conduct')) {
    return FluentIcons.mail;
  }
  if (id.contains('profile')) return FluentIcons.contact;
  if (id.contains('teacher') || id.contains('people')) {
    return FluentIcons.people;
  }
  if (id.contains('account')) return FluentIcons.contact;
  if (id.contains('security') || id.contains('delet')) {
    return FluentIcons.lock;
  }
  if (id.contains('training') || id.contains('session')) {
    return FluentIcons.history;
  }
  if (id.contains('assignment') || id.contains('clip')) {
    return FluentIcons.video;
  }
  if (id.contains('rights') || id.contains('privacy')) {
    return FluentIcons.shield;
  }
  if (id.contains('change') || id.contains('limit')) {
    return FluentIcons.info;
  }
  return FluentIcons.info;
}
