import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../data/models/assessment_mode.dart';
import '../../../data/models/assessment_spec.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/teacher_reviewed_movement_spec.dart';
import '../../../data/models/training_prop.dart';
import 'teacher_movement_builder_draft.dart';

typedef TeacherReviewedSaveCallback =
    Future<void> Function({
      required String title,
      required String instructions,
      required TrainingProp requiredProp,
      String? safetyGuidance,
    });

class TeacherMovementBuilderDialog extends StatefulWidget {
  const TeacherMovementBuilderDialog({
    super.key,
    required this.onCreateTeacherReviewed,
    this.existing,
    this.existingRevision,
    this.onEditTeacherReviewed,
    this.onOpenLiveTest,
  });

  final TeacherMovement? existing;
  final TeacherMovementRevision? existingRevision;
  final TeacherReviewedSaveCallback onCreateTeacherReviewed;
  final TeacherReviewedSaveCallback? onEditTeacherReviewed;
  final ValueChanged<TeacherLiveTestDraft>? onOpenLiveTest;

  @override
  State<TeacherMovementBuilderDialog> createState() =>
      _TeacherMovementBuilderDialogState();
}

class _TeacherMovementBuilderDialogState
    extends State<TeacherMovementBuilderDialog> {
  late final TeacherMovementBuilderDraft _draft;
  late final TextEditingController _title;
  late final TextEditingController _instructions;
  late final TextEditingController _safety;
  String? _validationMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final revision = widget.existingRevision;
    if (existing != null) {
      _draft = TeacherMovementBuilderDraft.editingExisting(
        title: existing.title,
        instructions: revision?.spec.instructions ?? '',
        requiredProp: revision?.spec.requiredProp ?? TrainingProp.bottle,
        safetyGuidance: revision?.spec.safetyGuidance,
      );
    } else {
      _draft = TeacherMovementBuilderDraft();
    }
    _title = TextEditingController(text: _draft.title);
    _instructions = TextEditingController(text: _draft.instructions);
    _safety = TextEditingController(text: _draft.safetyGuidance);
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _safety.dispose();
    super.dispose();
  }

  void _syncDraftText() {
    _draft.title = _title.text;
    _draft.instructions = _instructions.text;
    _draft.safetyGuidance = _safety.text;
  }

  Future<void> _saveTeacherReviewed() async {
    _syncDraftText();
    final titleError = TeacherReviewedMovementSpec.validateTitle(_draft.title);
    final instructionsError = TeacherReviewedMovementSpec.validateInstructions(
      _draft.instructions,
    );
    final safetyError = TeacherReviewedMovementSpec.validateSafetyGuidance(
      _draft.safetyGuidance,
    );
    if (titleError != null ||
        instructionsError != null ||
        safetyError != null) {
      setState(() {
        _validationMessage = titleError ?? instructionsError ?? safetyError;
      });
      return;
    }
    if (_isEditing) {
      await widget.onEditTeacherReviewed?.call(
        title: _draft.title,
        instructions: _draft.instructions,
        requiredProp: _draft.requiredProp,
        safetyGuidance: _draft.safetyGuidance,
      );
    } else {
      await widget.onCreateTeacherReviewed(
        title: _draft.title,
        instructions: _draft.instructions,
        requiredProp: _draft.requiredProp,
        safetyGuidance: _draft.safetyGuidance,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  void _openLiveTest() {
    _syncDraftText();
    widget.onOpenLiveTest?.call(_draft.toLiveTestDraft());
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text(_isEditing ? 'Edit movement' : 'Create movement'),
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_draft.locksAssessmentMode) ...[
              Text(
                'Assessment method',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _AssessmentMethodCard(
                key: const ValueKey('assessment-method-teacher-reviewed'),
                selected: !_draft.isTemplateScored,
                title: 'Teacher reviewed',
                explanation:
                    'Teacher reviews the trainee\'s submitted recording. '
                    'No automatic ELIXR score.',
                onSelected: () {
                  setState(() {
                    _draft.assessmentMode = AssessmentMode.teacherReviewed;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _AssessmentMethodCard(
                key: const ValueKey('assessment-method-template-scored'),
                selected: _draft.isTemplateScored,
                title: 'Template scored',
                explanation:
                    'ELIXR automatically evaluates a supported movement template. '
                    'Template results are classroom assessment data and do not '
                    'award global XP.',
                onSelected: () {
                  setState(() {
                    _draft.assessmentMode = AssessmentMode.templateScored;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: InfoBar(
                  title: Text('Teacher reviewed'),
                  content: Text(
                    'No automatic ELIXR score. Editing publishes a new revision '
                    'and keeps old assignments pinned.',
                  ),
                  severity: InfoBarSeverity.info,
                ),
              ),
            if (_draft.isTemplateScored) ...[
              const InfoBar(
                title: Text('Template scored'),
                content: Text(
                  'Preview and Live Test are available. Persistent template '
                  'publishing will be enabled after classroom scoring storage '
                  'is installed.',
                ),
                severity: InfoBarSeverity.info,
              ),
              const SizedBox(height: AppSpacing.md),
              _LockedField(label: 'Template family', value: 'Balance / Stall'),
              const SizedBox(height: AppSpacing.md),
              _LockedField(label: 'Template', value: 'Wrist Stall'),
              const SizedBox(height: AppSpacing.md),
              _LockedField(label: 'Prop', value: 'Bottle'),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Laterality',
                style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Left and right refer to the performer\'s own body, not '
                'screen position.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final laterality in AssessmentLaterality.values)
                    ToggleButton(
                      key: ValueKey('laterality-${laterality.wireValue}'),
                      checked: _draft.laterality == laterality,
                      onChanged: (_) {
                        setState(() => _draft.laterality = laterality);
                      },
                      child: Text(lateralityTeacherLabel(laterality)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            InfoLabel(
              label: 'Title',
              child: TextBox(
                key: const ValueKey('builder-title'),
                controller: _title,
                placeholder: 'Movement title',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Instructions',
              child: TextBox(
                key: const ValueKey('builder-instructions'),
                controller: _instructions,
                maxLines: 6,
                placeholder: 'What the trainee should practice',
              ),
            ),
            if (!_draft.isTemplateScored) ...[
              const SizedBox(height: AppSpacing.md),
              InfoLabel(
                label: 'Required prop',
                child: ComboBox<TrainingProp>(
                  value: _draft.requiredProp,
                  items: [
                    for (final value in TrainingProp.values)
                      ComboBoxItem(
                        value: value,
                        child: Text(value.displayLabel),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _draft.requiredProp = value);
                  },
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            InfoLabel(
              label: 'Safety guidance (optional)',
              child: TextBox(
                key: const ValueKey('builder-safety'),
                controller: _safety,
                maxLines: 3,
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBar(
                title: const Text('Check the movement details'),
                content: Text(_validationMessage!),
                severity: InfoBarSeverity.warning,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_draft.canOpenLiveTest)
          Button(
            key: const ValueKey('template-live-test'),
            onPressed: widget.onOpenLiveTest == null ? null : _openLiveTest,
            child: const Text('Live Test'),
          ),
        if (_draft.canPersistTeacherReviewed)
          ElixPrimaryButton(
            key: const ValueKey('teacher-reviewed-save'),
            label: _isEditing ? 'Save revision' : 'Create',
            expanded: false,
            dense: true,
            onPressed: _saveTeacherReviewed,
          ),
      ],
    );
  }
}

class _AssessmentMethodCard extends StatelessWidget {
  const _AssessmentMethodCard({
    super.key,
    required this.selected,
    required this.title,
    required this.explanation,
    required this.onSelected,
  });

  final bool selected;
  final String title;
  final String explanation;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onSelected,
      builder: (context, states) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? context.elixCardSurface
                : context.elixPanelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? FluentTheme.of(context).accentColor
                  : context.elixBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioButton(
                checked: selected,
                onChanged: (_) => onSelected(),
                content: Text(
                  title,
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                explanation,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(value, style: AppTheme.body),
      ),
    );
  }
}
