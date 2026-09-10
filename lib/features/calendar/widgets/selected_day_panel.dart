import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../data/models/training_plan.dart';
import '../models/calendar_classroom_assignment.dart';
import '../models/training_day_snapshot.dart';
import '../models/training_day_status.dart';
import '../utils/training_day_status_style.dart';
import '../utils/training_plan_progress.dart';
import 'calendar_agenda_panel.dart';
import 'classroom_day_section.dart';
import 'training_plan_editor.dart';

class SelectedDayPanel extends StatelessWidget {
  const SelectedDayPanel({
    super.key,
    required this.snapshot,
    required this.todayKey,
    required this.userId,
    required this.isEditing,
    required this.isSaving,
    required this.onStartEditing,
    required this.onCancelEditing,
    required this.onSavePlan,
    required this.onMarkRest,
    required this.onRemovePlan,
    required this.onStartPractice,
    required this.onViewHistory,
    this.classroomItems = const [],
    this.onOpenClassroomAssignment,
    this.actionError,
  });

  final TrainingDaySnapshot snapshot;
  final String todayKey;
  final String userId;
  final bool isEditing;
  final bool isSaving;
  final String? actionError;
  final VoidCallback onStartEditing;
  final VoidCallback onCancelEditing;
  final ValueChanged<TrainingPlan> onSavePlan;
  final VoidCallback onMarkRest;
  final VoidCallback onRemovePlan;
  final VoidCallback onStartPractice;
  final VoidCallback onViewHistory;
  final List<CalendarClassroomAssignment> classroomItems;
  final ValueChanged<CalendarClassroomAssignment>? onOpenClassroomAssignment;

  bool get _isActionable => snapshot.dayKey.compareTo(todayKey) >= 0;
  bool get _isToday => snapshot.dayKey == todayKey;
  bool get _isPast => snapshot.dayKey.compareTo(todayKey) < 0;

  @override
  Widget build(BuildContext context) {
    final subtitle = _isToday
        ? 'Today'
        : _isPast
        ? 'Past day'
        : 'Upcoming day';

    return CalendarAgendaPanel(
      date: snapshot.civilDate,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actionError != null) ...[
            InfoBar(
              title: const Text('Could not update the training plan.'),
              content: Text(actionError!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (isEditing)
            TrainingPlanEditor(
              userId: userId,
              dayKey: snapshot.dayKey,
              initialPlan: snapshot.plan?.isTraining == true
                  ? snapshot.plan
                  : null,
              isSaving: isSaving,
              onCancel: onCancelEditing,
              onSave: onSavePlan,
            )
          else ...[
            CalendarAgendaSection(
              title: 'TRAINING',
              topSpacing: false,
              child: _buildBody(context),
            ),
            if (onOpenClassroomAssignment != null)
              ClassroomDaySection(
                items: classroomItems,
                onOpen: onOpenClassroomAssignment!,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final plan = snapshot.plan;
    if (plan == null) {
      return _isPast
          ? const CalendarAgendaInset(
              child: _CopyText(
                title: 'No training was scheduled.',
                body:
                    'Historical days stay as they were so adherence stays honest.',
              ),
            )
          : _UnplannedActionable(
              isSaving: isSaving,
              onPlanPractice: onStartEditing,
              onMarkRest: onMarkRest,
            );
    }

    if (plan.isRest) {
      return _RestDayBody(
        isActionable: _isActionable,
        isSaving: isSaving,
        onRemove: onRemovePlan,
      );
    }

    return _TrainingPlanBody(
      snapshot: snapshot,
      isToday: _isToday,
      isActionable: _isActionable,
      isSaving: isSaving,
      onEdit: onStartEditing,
      onRemove: onRemovePlan,
      onStartPractice: onStartPractice,
      onViewHistory: onViewHistory,
    );
  }
}

class _CopyText extends StatelessWidget {
  const _CopyText({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ElixTypography.label(
            color: context.elixTextPrimary,
          ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _UnplannedActionable extends StatelessWidget {
  const _UnplannedActionable({
    required this.isSaving,
    required this.onPlanPractice,
    required this.onMarkRest,
  });

  final bool isSaving;
  final VoidCallback onPlanPractice;
  final VoidCallback onMarkRest;

  @override
  Widget build(BuildContext context) {
    return CalendarAgendaInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No training planned',
            style: ElixTypography.label(
              color: context.elixTextPrimary,
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Use this day to schedule a focused practice session or recovery day.',
            style: ElixTypography.supporting(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: isSaving ? null : onPlanPractice,
                child: const Text('Plan Practice'),
              ),
              Button(
                onPressed: isSaving ? null : onMarkRest,
                child: const Text('Mark Rest Day'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RestDayBody extends StatelessWidget {
  const _RestDayBody({
    required this.isActionable,
    required this.isSaving,
    required this.onRemove,
  });

  final bool isActionable;
  final bool isSaving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusChip(status: TrainingDayStatus.rest),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Rest day',
          style: ElixTypography.cardTitle(color: context.elixTextPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Recovery is part of the plan. This day does not count against adherence.',
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
        if (isActionable) ...[
          const SizedBox(height: AppSpacing.md),
          Button(
            onPressed: isSaving ? null : onRemove,
            child: const Text('Remove Plan'),
          ),
        ],
      ],
    );
  }
}

class _TrainingPlanBody extends StatelessWidget {
  const _TrainingPlanBody({
    required this.snapshot,
    required this.isToday,
    required this.isActionable,
    required this.isSaving,
    required this.onEdit,
    required this.onRemove,
    required this.onStartPractice,
    required this.onViewHistory,
  });

  final TrainingDaySnapshot snapshot;
  final bool isToday;
  final bool isActionable;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onStartPractice;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final plan = snapshot.plan!;
    final target = plan.targetDurationMinutes ?? 0;
    final practiced = practicedMinutesFromSeconds(
      snapshot.matchedDurationSeconds,
    );
    final completed = snapshot.status == TrainingDayStatus.completed;
    final showStart = isToday && !completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Training Plan',
          style: ElixTypography.eyebrow(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          plan.movementName ?? '',
          style: ElixTypography.sectionTitle(
            context,
            color: context.elixTextPrimary,
          ).copyWith(fontSize: 20, height: 1.15),
        ),
        const SizedBox(height: 4),
        Text(
          '${plan.difficulty} · ${plan.propType?.displayLabel ?? ''}',
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(label: 'Target', value: formatPlanMinutes(target)),
            _MetricChip(
              label: completed ? 'Completed' : 'Progress',
              value: completed
                  ? '$practiced min practiced'
                  : '$practiced / $target min',
            ),
            _MetricChip(label: 'Status', value: snapshot.status.label),
            if (snapshot.bestMatchingRubricTotal != null)
              _MetricChip(
                label: 'Best rubric',
                value: '${snapshot.bestMatchingRubricTotal} / 12',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _StatusChip(status: snapshot.status),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (showStart)
              FilledButton(
                onPressed: isSaving ? null : onStartPractice,
                child: const Text('Start Practice'),
              ),
            if (completed)
              FilledButton(
                onPressed: onViewHistory,
                child: const Text('View History'),
              ),
            if (isActionable) ...[
              Button(
                onPressed: isSaving ? null : onEdit,
                child: const Text('Edit Plan'),
              ),
              Button(
                onPressed: isSaving ? null : onRemove,
                child: const Text('Remove Plan'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceTinted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ElixTypography.label(
              color: context.elixTextSecondary,
            ).copyWith(fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: ElixTypography.label(
              color: context.elixTextPrimary,
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TrainingDayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = trainingDayStatusColor(status, context.elixColors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isHighContrast ? 0 : 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trainingDayStatusIcon(status), size: 11, color: color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: ElixTypography.label(color: color).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
