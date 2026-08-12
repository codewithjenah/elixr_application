import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movement_visuals.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/feedback.dart' as models;
import '../../../data/models/session.dart';
import '../../../data/repositories/session_repository.dart';
import '../history_format.dart';
import 'history_session_details.dart';

class HistorySessionRow extends StatefulWidget {
  const HistorySessionRow({super.key, required this.session});

  final Session session;

  @override
  State<HistorySessionRow> createState() => _HistorySessionRowState();
}

class _HistorySessionRowState extends State<HistorySessionRow> {
  final _repo = SessionRepository();

  bool _expanded = false;
  bool _hovered = false;
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
      final feedbacks = await _repo.getFeedbacksForSession(id);
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
        ? DateFormat.jm().format(DateTime.parse(s.createdAt!).toLocal())
        : '—';
    final duration = formatTrainingDuration(s.durationSeconds);
    final emoji = MovementVisuals.emojiFor(s.movementName);
    final diffColor = difficultyColor(s.difficulty);
    final active = _expanded || _hovered;

    // Assessment V2 shows the rubric total and performance level; legacy
    // sessions keep the 0..100 percentage. The two scales never mix.
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
      resultValue = legacy == null ? '—' : '$legacy';
      resultLabel = legacy == null ? 'Not scored' : scoreQualityLabel(legacy);
      resultColor = legacy == null
          ? context.elixTextSecondary
          : scoreQualityColor(legacy);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleExpanded,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: active
                ? context.elixCardSurface
                : context.elixCardSurface.withValues(
                    alpha: context.isDarkTheme ? 0.85 : 1,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(
                      alpha: context.isDarkTheme ? 0.45 : 0.35,
                    )
                  : context.elixBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  if (wide) {
                    return _WideRow(
                      emoji: emoji,
                      name: s.movementName,
                      difficulty: s.difficulty,
                      difficultyColor: diffColor,
                      time: time,
                      duration: duration,
                      resultValue: resultValue,
                      resultLabel: resultLabel,
                      resultColor: resultColor,
                      expanded: _expanded,
                      active: active,
                    );
                  }
                  return _NarrowRow(
                    emoji: emoji,
                    name: s.movementName,
                    difficulty: s.difficulty,
                    time: time,
                    duration: duration,
                    resultValue: resultValue,
                    resultColor: resultColor,
                    expanded: _expanded,
                    active: active,
                  );
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? HistorySessionDetails(
                        session: s,
                        loading: _feedbackLoading,
                        feedbacks: _feedbacks,
                        errorMessage: _feedbackError,
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({
    required this.emoji,
    required this.name,
    required this.difficulty,
    required this.difficultyColor,
    required this.time,
    required this.duration,
    required this.resultValue,
    required this.resultLabel,
    required this.resultColor,
    required this.expanded,
    required this.active,
  });

  final String emoji;
  final String name;
  final String difficulty;
  final Color difficultyColor;
  final String time;
  final String duration;
  final String resultValue;
  final String resultLabel;
  final Color resultColor;
  final bool expanded;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EmojiAvatar(emoji: emoji),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _DifficultyBadge(label: difficulty, color: difficultyColor),
        const SizedBox(width: AppSpacing.md),
        Text(
          time,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          duration,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(width: AppSpacing.md),
        _ResultBadge(
          value: resultValue,
          label: resultLabel,
          color: resultColor,
        ),
        const SizedBox(width: AppSpacing.sm),
        AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            FluentIcons.chevron_down,
            size: 12,
            color: active ? context.elixTextPrimary : context.elixTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _NarrowRow extends StatelessWidget {
  const _NarrowRow({
    required this.emoji,
    required this.name,
    required this.difficulty,
    required this.time,
    required this.duration,
    required this.resultValue,
    required this.resultColor,
    required this.expanded,
    required this.active,
  });

  final String emoji;
  final String name;
  final String difficulty;
  final String time;
  final String duration;
  final String resultValue;
  final Color resultColor;
  final bool expanded;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EmojiAvatar(emoji: emoji, size: 40),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.elixTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    resultValue,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: resultColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$difficulty • $time • $duration',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      FluentIcons.chevron_down,
                      size: 12,
                      color: active
                          ? context.elixTextPrimary
                          : context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmojiAvatar extends StatelessWidget {
  const _EmojiAvatar({required this.emoji, this.size = 42});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.accent.withValues(
          alpha: context.isDarkTheme ? 0.18 : 0.1,
        ),
        border: Border.all(color: context.elixBorder),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.45)),
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
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDarkTheme ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
