import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movements.dart';
import '../../../core/progression/practice_variant.dart';
import '../../../core/progression/progression_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/training_plan.dart';
import '../../../data/models/training_prop.dart';
import '../../../services/trainee_progression_service.dart';
import '../../../services/tutorial_progress_service.dart';

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
  Movement? _movement;
  TrainingProp? _prop;
  late int _duration;
  var _initialized = false;

  bool _isPersonalReady(Movement movement, TrainingProp prop) {
    final progression = context.read<TraineeProgressionService>();
    final tutorials = context.read<TutorialProgressService>();
    final access = evaluatePersonal(
      variant: PracticeVariant(
        movementName: movement.name,
        trainingProp: prop,
      ),
      currentLevel: progression.currentLevelOrNull,
      tutorialCompleted: tutorials.isInitialized
          ? tutorials.hasCompletedLesson(movement.name, prop)
          : null,
    );
    return access == ProgressionAccessResult.personalReady;
  }

  List<Movement> get _readyMovements {
    return [
      for (final movement in movementCatalog)
        if (movement.enabled)
          if (movement.supportedProps.any(
            (prop) => _isPersonalReady(movement, prop),
          ))
            movement,
    ];
  }

  List<TrainingProp> _readyPropsFor(Movement movement) {
    return [
      for (final prop in movement.supportedProps)
        if (_isPersonalReady(movement, prop)) prop,
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final ready = _readyMovements;
    final initial = widget.initialPlan;
    final named = initial?.movementName;
    final selected = ready.cast<Movement?>().firstWhere(
      (movement) => movement?.name == named,
      orElse: () => ready.isEmpty ? null : ready.first,
    );
    _movement = selected;
    if (selected != null) {
      final props = _readyPropsFor(selected);
      _prop =
          initial?.propType != null && props.contains(initial!.propType)
          ? initial.propType
          : (props.isEmpty ? null : props.first);
    }
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
      final props = _readyPropsFor(movement);
      if (_prop == null || !props.contains(_prop)) {
        _prop = props.isEmpty ? null : props.first;
      }
    });
  }

  void _submit() {
    final movement = _movement;
    final prop = _prop;
    if (movement == null || prop == null) return;
    widget.onSave(
      TrainingPlan.training(
        userId: widget.userId,
        dayKey: widget.dayKey,
        movementName: movement.name,
        difficulty: movement.difficulty,
        propType: prop,
        targetDurationMinutes: _duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _readyMovements;
    final movement = _movement;
    final props = movement == null ? const <TrainingProp>[] : _readyPropsFor(movement);
    final prop = _prop;

    if (ready.isEmpty || movement == null || prop == null) {
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
          Text(
            'No personally unlocked movements are ready to schedule yet. '
            'Complete a lesson first, then try again.',
            style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Button(
            onPressed: widget.isSaving ? null : widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      );
    }

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
            value: movement.name,
            items: [
              for (final item in ready)
                ComboBoxItem<String>(
                  value: item.name,
                  child: Text(item.name),
                ),
            ],
            onChanged: widget.isSaving
                ? null
                : (name) {
                    if (name == null) return;
                    final next = ready.firstWhere(
                      (item) => item.name == name,
                    );
                    _onMovementChanged(next);
                  },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${movement.difficulty} · ${prop.displayLabel}',
          style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
        ),
        if (props.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          InfoLabel(
            label: 'Training prop',
            child: ComboBox<TrainingProp>(
              isExpanded: true,
              value: prop,
              items: [
                for (final item in props)
                  ComboBoxItem<TrainingProp>(
                    value: item,
                    child: Text(item.displayLabel),
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
