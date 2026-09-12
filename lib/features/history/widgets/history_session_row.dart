import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/feedback.dart' as models;
import '../../../data/models/session.dart';
import '../../../data/repositories/session_repository.dart';
import '../history_format.dart';
import 'history_session_details.dart';

/// Shared History row geometry. Every visible session uses these widths so
/// difficulty, time, duration, score, and the expand control stay aligned.
abstract final class HistorySessionColumns {
  static const wideBreakpoint = 720.0;
  static const difficulty = 84.0;
  static const time = 104.0;
  static const duration = 96.0;
  static const score = 160.0;
  static const expand = 28.0;
  static const avatar = 44.0;
  static const gap = 8.0;

  static const difficultyKey = ValueKey<String>('history-col-difficulty');
  static const timeKey = ValueKey<String>('history-col-time');
  static const durationKey = ValueKey<String>('history-col-duration');
  static const scoreKey = ValueKey<String>('history-col-score');
  static const expandKey = ValueKey<String>('history-col-expand');
}

class HistorySessionRow extends StatefulWidget {
  const HistorySessionRow({super.key, required this.session});

  final Session session;

  @override
  State<HistorySessionRow> createState() => _HistorySessionRowState();
}

class _HistorySessionRowState extends State<HistorySessionRow> {
  SessionRepository? _repo;

  bool _expanded = false;
  bool _hovered = false;
  bool _focused = false;
  bool _feedbackLoading = false;
  bool _feedbackLoaded = false;
  List<models.Feedback>? _feedbacks;
  String? _feedbackError;

  Future<void> _toggleExpanded() async {
    final willExpand = !_expanded;
    setState(() => _expanded = willExpand);

    if (!willExpand || _feedbackLoaded || _feedbackLoading) return;
    await _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    final id = widget.session.id;
    if (id == null) {
      setState(() {
        _feedbackLoaded = true;
        _feedbacks = const [];
        _feedbackError = null;
      });
      return;
    }

    setState(() {
      _feedbackLoading = true;
      _feedbackError = null;
    });

    try {
      final feedbacks = await (_repo ??= SessionRepository())
          .getFeedbacksForSession(id);
      if (!mounted) return;
      setState(() {
        _feedbacks = feedbacks;
        _feedbackLoaded = true;
        _feedbackLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedbackError = 'Could not load feedback';
        _feedbackLoaded = true;
        _feedbackLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final time = s.createdAt != null
        ? formatElixrTime(DateTime.parse(s.createdAt!).toLocal())
        : '—';
    final duration = formatTrainingDuration(s.durationSeconds);
    final diffColor = difficultyColor(s.difficulty);
    final active = _expanded || _hovered || _focused;
    final highContrast = context.isHighContrast;
    final subtitle = historyMovementSubtitle(
      movementName: s.movementName,
      propType: s.propType,
    );

    final String resultValue;
    final String resultLabel;
    final Color resultColor;
    if (s.isRubricAssessed) {
      final total = s.rubricTotal!;
      final level = rubricPerformanceLevel(total);
      resultValue = rubricTotalLabel(total);
      resultLabel = level.label;
      resultColor = performanceLevelColor(level);
    } else {
      final legacy = s.legacyScore;
      resultValue = legacy == null ? '—' : '$legacy/100';
      resultLabel = legacy == null ? 'Not scored' : scoreQualityLabel(legacy);
      resultColor = legacy == null
          ? context.elixTextSecondary
          : scoreQualityColor(legacy);
    }

    final colors = context.elixColors;
    final fill = highContrast
        ? context.elixCardSurface
        : _expanded
        ? Color.alphaBlend(
            AppColors.accent.withValues(alpha: 0.10),
            context.elixCardSurface,
          )
        : active
        ? colors.interactiveHover
        : context.elixCardSurface.withValues(
            alpha: context.isDarkTheme ? 0.88 : 1,
          );
    final borderColor = _focused
        ? colors.focusRing
        : _expanded
        ? AppColors.accent.withValues(alpha: highContrast ? 1 : 0.58)
        : active
        ? AppColors.accent.withValues(alpha: highContrast ? 1 : 0.42)
        : context.elixBorder;
    final borderWidth = _focused
        ? (highContrast ? ElixFocus.ringWidthHighContrast : ElixFocus.ringWidth)
        : 1.0;

    return Semantics(
      button: true,
      expanded: _expanded,
      label:
          '${s.movementName}, ${s.difficulty}, $time, $duration, '
          '$resultValue $resultLabel',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggleExpanded();
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
        child: AnimatedContainer(
          duration: ElixMotion.duration(context, ElixMotion.standard),
          curve: ElixMotion.standardCurve,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
            // Borders and the selected state provide enough hierarchy here;
            // a glow on every hovered row made dense history feel noisy.
            boxShadow: const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleExpanded,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md - 2,
                          10,
                          AppSpacing.sm,
                          10,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide =
                                constraints.maxWidth >=
                                HistorySessionColumns.wideBreakpoint;
                            return _SessionSummaryRow(
                              movementName: s.movementName,
                              subtitle: subtitle,
                              difficulty: s.difficulty,
                              difficultyColor: diffColor,
                              time: time,
                              duration: duration,
                              resultValue: resultValue,
                              resultLabel: resultLabel,
                              resultColor: resultColor,
                              expanded: _expanded,
                              active: active,
                              wide: wide,
                            );
                          },
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: ElixMotion.duration(
                        context,
                        ElixMotion.standard,
                      ),
                      curve: ElixMotion.standardCurve,
                      alignment: Alignment.topCenter,
                      child: _expanded
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(
                                  alpha: highContrast
                                      ? 0
                                      : (context.isDarkTheme ? 0.07 : 0.04),
                                ),
                                border: Border(
                                  top: BorderSide(color: context.elixBorder),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md - 2,
                                  AppSpacing.sm,
                                  AppSpacing.md - 2,
                                  AppSpacing.sm,
                                ),
                                child: HistorySessionDetails(
                                  session: s,
                                  loading: _feedbackLoading,
                                  feedbacks: _feedbacks,
                                  errorMessage: _feedbackError,
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
                if (_expanded)
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppColors.accent,
                        child: SizedBox(width: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionSummaryRow extends StatelessWidget {
  const _SessionSummaryRow({
    required this.movementName,
    required this.subtitle,
    required this.difficulty,
    required this.difficultyColor,
    required this.time,
    required this.duration,
    required this.resultValue,
    required this.resultLabel,
    required this.resultColor,
    required this.expanded,
    required this.active,
    required this.wide,
  });

  final String movementName;
  final String? subtitle;
  final String difficulty;
  final Color difficultyColor;
  final String time;
  final String duration;
  final String resultValue;
  final String resultLabel;
  final Color resultColor;
  final bool expanded;
  final bool active;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final identity = _MovementIdentity(
      movementName: movementName,
      subtitle: subtitle,
    );
    final score = _ResultTicket(
      value: resultValue,
      label: resultLabel,
      color: resultColor,
    );
    final chevron = _ExpandChevron(expanded: expanded, active: active);

    if (!wide) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: identity),
              _HistoryMetaCell(
                width: HistorySessionColumns.score,
                columnKey: HistorySessionColumns.scoreKey,
                child: score,
              ),
              _HistoryMetaCell(
                width: HistorySessionColumns.expand,
                columnKey: HistorySessionColumns.expandKey,
                alignment: Alignment.center,
                child: chevron,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: HistorySessionColumns.avatar + 10),
              _DifficultyBadge(label: difficulty, color: difficultyColor),
              const SizedBox(width: 10),
              Flexible(
                child: _MetaValue(
                  icon: FluentIcons.clock,
                  value: time,
                  tooltip: 'Session time',
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _MetaValue(
                  icon: FluentIcons.timer,
                  value: duration,
                  tooltip: 'Duration',
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: identity),
        _HistoryMetaCell(
          width: HistorySessionColumns.difficulty,
          columnKey: HistorySessionColumns.difficultyKey,
          child: _DifficultyBadge(label: difficulty, color: difficultyColor),
        ),
        _HistoryMetaCell(
          width: HistorySessionColumns.time,
          columnKey: HistorySessionColumns.timeKey,
          child: _MetaValue(
            icon: FluentIcons.clock,
            value: time,
            tooltip: 'Session time',
          ),
        ),
        _HistoryMetaCell(
          width: HistorySessionColumns.duration,
          columnKey: HistorySessionColumns.durationKey,
          child: _MetaValue(
            icon: FluentIcons.timer,
            value: duration,
            tooltip: 'Duration',
          ),
        ),
        _HistoryMetaCell(
          width: HistorySessionColumns.score,
          columnKey: HistorySessionColumns.scoreKey,
          child: score,
        ),
        _HistoryMetaCell(
          width: HistorySessionColumns.expand,
          columnKey: HistorySessionColumns.expandKey,
          alignment: Alignment.center,
          child: chevron,
        ),
      ],
    );
  }
}

class _HistoryMetaCell extends StatelessWidget {
  const _HistoryMetaCell({
    required this.width,
    required this.columnKey,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final double width;
  final Key columnKey;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: HistorySessionColumns.gap),
      child: SizedBox(
        key: columnKey,
        width: width,
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}

class _MovementIdentity extends StatelessWidget {
  const _MovementIdentity({required this.movementName, required this.subtitle});

  final String movementName;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MovementAvatar(movementName: movementName),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                movementName,
                style: TextStyle(
                  fontFamily: ElixTypography.fontFamily,
                  fontFamilyFallback: ElixTypography.fontFallbacks,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaValue extends StatelessWidget {
  const _MetaValue({
    required this.icon,
    required this.value,
    required this.tooltip,
  });

  final IconData icon;
  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        children: [
          Icon(icon, size: 12, color: context.elixTextSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({required this.expanded, required this.active});

  final bool expanded;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: ElixMotion.duration(context, ElixMotion.standard),
      child: Icon(
        FluentIcons.chevron_down,
        size: 12,
        color: active ? context.elixTextPrimary : context.elixTextSecondary,
      ),
    );
  }
}

class _MovementAvatar extends StatelessWidget {
  const _MovementAvatar({required this.movementName});

  final String movementName;

  @override
  Widget build(BuildContext context) {
    const size = HistorySessionColumns.avatar;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.accent.withValues(
          alpha: context.isDarkTheme ? 0.16 : 0.1,
        ),
        border: Border.all(color: context.elixBorder),
      ),
      child: MovementImage(movementName: movementName, size: size),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ResultTicket extends StatelessWidget {
  const _ResultTicket({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ElixTypography.fontFamily,
              fontFamilyFallback: ElixTypography.fontFallbacks,
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ElixTypography.fontFamily,
              fontFamilyFallback: ElixTypography.fontFallbacks,
              fontSize: 11,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
