import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/training_plan.dart';
import '../../../data/models/training_prop.dart';

class TrainingPlanEditor extends StatefulWidget {
  const TrainingPlanEditor({
    super.key,
    required this.userId,
    required this.dayKey,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
    this.initialPlan,
  });

  final String userId;
  final String dayKey;
  final bool isSaving;
  final VoidCallback onCancel;
  final ValueChanged<TrainingPlan> onSave;
  final TrainingPlan? initialPlan;

  @override
  State<TrainingPlanEditor> createState() => _TrainingPlanEditorState();
}

class _TrainingPlanEditorState extends State<TrainingPlanEditor> {
  late Movement _movement;
  late TrainingProp _prop;
  late int _duration;

  List<Movement> get _enabledMovements =>
      movementCatalog.where((movement) => movement.enabled).toList();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPlan;
    final named = initial?.movementName;
    _movement = _enabledMovements.firstWhere(
      (movement) => movement.name == named,
      orElse: () => _enabledMovements.first,
    );
    final supported = _movement.supportedProps;
    _prop = initial?.propType != null && supported.contains(initial!.propType)
        ? initial.propType!
        : supported.first;
    _duration =
        initial?.targetDurationMinutes != null &&
            TrainingPlan.allowedTargetDurations.contains(
              initial!.targetDurationMinutes,
            )
        ? initial.targetDurationMinutes!
        : 10;
  }

  void _onMovementChanged(Movement? movement) {
    if (movement == null) return;
    setState(() {
      _movement = movement;
      if (!movement.supportedProps.contains(_prop)) {
        _prop = movement.supportedProps.first;
      }
    });
  }

  void _submit() {
    widget.onSave(
      TrainingPlan.training(
        userId: widget.userId,
        dayKey: widget.dayKey,
        movementName: _movement.name,
        difficulty: _movement.difficulty,
        propType: _prop,
        targetDurationMinutes: _duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final props = _movement.supportedProps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.initialPlan == null ? 'Plan Practice' : 'Edit Plan',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InfoLabel(
          label: 'Movement',
          child: ComboBox<String>(
            isExpanded: true,
            value: _movement.name,
            items: [
              for (final movement in _enabledMovements)
                ComboBoxItem<String>(
                  value: movement.name,
                  child: Text(movement.name),
                ),
            ],
            onChanged: widget.isSaving
                ? null
                : (name) {
                    if (name == null) return;
                    final next = _enabledMovements.firstWhere(
                      (movement) => movement.name == name,
                    );
                    _onMovementChanged(next);
                  },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${_movement.difficulty} · ${_prop.displayLabel}',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
        ),
        if (props.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          InfoLabel(
            label: 'Training prop',
            child: ComboBox<TrainingProp>(
              isExpanded: true,
              value: _prop,
              items: [
                for (final prop in props)
                  ComboBoxItem<TrainingProp>(
                    value: prop,
                    child: Text(prop.displayLabel),
                  ),
              ],
              onChanged: widget.isSaving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _prop = value);
                    },
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        InfoLabel(
          label: 'Target duration',
          child: ComboBox<int>(
            isExpanded: true,
            value: _duration,
            items: [
              for (final minutes in TrainingPlan.allowedTargetDurations)
                ComboBoxItem<int>(value: minutes, child: Text('$minutes min')),
            ],
            onChanged: widget.isSaving
                ? null
                : (value) {
                    if (value != null) setState(() => _duration = value);
                  },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            FilledButton(
              onPressed: widget.isSaving ? null : _submit,
              child: Text(widget.isSaving ? 'Saving…' : 'Save Plan'),
            ),
            const SizedBox(width: AppSpacing.sm),
            Button(
              onPressed: widget.isSaving ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
