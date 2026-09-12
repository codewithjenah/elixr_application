import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

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
      variant: PracticeVariant(movementName: movement.name, trainingProp: prop),
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
      _prop = initial?.propType != null && props.contains(initial!.propType)
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
    final props = movement == null
        ? const <TrainingProp>[]
        : _readyPropsFor(movement);
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
          _EditorOutlineButton(
            onPressed: widget.isSaving ? null : widget.onCancel,
            label: 'Cancel',
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
        _EditorField(
          label: 'Movement',
          child: _EditorSelect<String>(
            key: ValueKey('training_plan_movement_${movement.name}'),
            value: movement.name,
            enabled: !widget.isSaving,
            options: [
              for (final item in ready)
                shad.ShadOption<String>(
                  value: item.name,
                  child: Text(item.name),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              _onMovementChanged(ready.firstWhere((item) => item.name == name));
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
          _EditorField(
            label: 'Training prop',
            child: _EditorSelect<TrainingProp>(
              key: ValueKey('training_plan_prop_${prop.name}'),
              value: prop,
              enabled: !widget.isSaving,
              options: [
                for (final item in props)
                  shad.ShadOption<TrainingProp>(
                    value: item,
                    child: Text(item.displayLabel),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _prop = value);
              },
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _EditorField(
          label: 'Target duration',
          child: _EditorSelect<int>(
            key: ValueKey('training_plan_duration_$_duration'),
            value: _duration,
            enabled: !widget.isSaving,
            options: [
              for (final minutes in TrainingPlan.allowedTargetDurations)
                shad.ShadOption<int>(
                  value: minutes,
                  child: Text('$minutes min'),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _duration = value);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            _EditorPrimaryButton(
              onPressed: widget.isSaving ? null : _submit,
              label: widget.isSaving ? 'Saving…' : 'Save Plan',
            ),
            const SizedBox(width: AppSpacing.sm),
            _EditorOutlineButton(
              onPressed: widget.isSaving ? null : widget.onCancel,
              label: 'Cancel',
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
      ),
      const SizedBox(height: 4),
      child,
    ],
  );
}

class _EditorSelect<T> extends StatelessWidget {
  const _EditorSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.enabled,
  });

  final T value;
  final List<shad.ShadOption<T>> options;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast) {
      return ComboBox<T>(
        isExpanded: true,
        value: value,
        items: [
          for (final option in options)
            ComboBoxItem<T>(value: option.value, child: option.child),
        ],
        onChanged: enabled ? onChanged : null,
      );
    }
    return shad.ShadSelect<T>(
      initialValue: value,
      enabled: enabled,
      options: options,
      selectedOptionBuilder: (context, selected) =>
          options.firstWhere((option) => option.value == selected).child,
      onChanged: onChanged,
    );
  }
}

class _EditorPrimaryButton extends StatelessWidget {
  const _EditorPrimaryButton({required this.onPressed, required this.label});
  final VoidCallback? onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => context.isHighContrast
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : shad.ShadButton(onPressed: onPressed, child: Text(label));
}

class _EditorOutlineButton extends StatelessWidget {
  const _EditorOutlineButton({required this.onPressed, required this.label});
  final VoidCallback? onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => context.isHighContrast
      ? Button(onPressed: onPressed, child: Text(label))
      : shad.ShadButton.outline(onPressed: onPressed, child: Text(label));
}
