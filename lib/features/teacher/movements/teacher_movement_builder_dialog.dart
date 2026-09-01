import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player_win/video_player_win.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_scaffold_page.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/teacher_reviewed_movement_spec.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/models/assignment_attempt_policy.dart';
import '../../../data/models/group_assignment.dart';
import 'teacher_movement_builder_draft.dart';
import 'teacher_demo_recording_dialog.dart';

typedef TeacherReviewedSaveCallback =
    Future<void> Function({
      required String title,
      required String instructions,
      required TrainingProp requiredProp,
      String? safetyGuidance,
    });

typedef TeacherActivitySaveCallback =
    Future<void> Function({
      required String title,
      required String instructions,
      required TrainingProp requiredProp,
      required TeacherActivityAssessmentConfig assessment,
      String? safetyGuidance,
    });

typedef TeacherActivityDemoUploadCallback =
    Future<TeacherActivityVideoMetadata> Function({
      required File localFile,
      required Duration duration,
      required TeacherActivityDemoSource source,
    });

typedef TeacherAssignmentActivitySaveCallback =
    Future<void> Function({
      required String title,
      required String instructions,
      required TrainingProp requiredProp,
      required TeacherActivityAssessmentConfig assessment,
      required AssignmentAttemptPolicy attemptPolicy,
      required AssignmentAudience audience,
      DateTime? dueAt,
      String? safetyGuidance,
    });

/// Builder for the only writable Teacher-created assessment mode.
class TeacherMovementBuilderDialog extends StatefulWidget {
  const TeacherMovementBuilderDialog({
    super.key,
    required this.onCreateTeacherReviewed,
    this.existing,
    this.existingRevision,
    this.onEditTeacherReviewed,
    this.onCreateActivity,
    this.onEditActivity,
    this.onUploadDemonstration,
    this.assignment,
    this.approvedMemberships = const [],
    this.onEditAssignment,
  }) : assert(assignment == null || onEditAssignment != null);

  final TeacherMovement? existing;
  final TeacherMovementRevision? existingRevision;
  final TeacherReviewedSaveCallback onCreateTeacherReviewed;
  final TeacherReviewedSaveCallback? onEditTeacherReviewed;
  final TeacherActivitySaveCallback? onCreateActivity;
  final TeacherActivitySaveCallback? onEditActivity;
  final TeacherActivityDemoUploadCallback? onUploadDemonstration;
  final GroupAssignment? assignment;
  final List<GroupMembership> approvedMemberships;
  final TeacherAssignmentActivitySaveCallback? onEditAssignment;

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
  late final TextEditingController _customMaximumScore;
  late final List<_CustomCriterionControllers> _customCriteria;
  var _nextCustomCriterionId = 1;
  String? _validationMessage;
  bool _saving = false;
  bool _uploadingDemo = false;
  File? _demoFile;
  final ElixrPlaybackSession _demoPlayback = ElixrPlaybackSession();
  late DateTime? _dueAt;
  late bool _hasDueDate;
  late AssignmentAttemptPolicy _attemptPolicy;
  late AssignmentAudienceType _audienceType;
  late Set<String> _recipientIds;

  bool get _isEditing => widget.existing != null || widget.assignment != null;
  bool get _isAssignmentEditor => widget.assignment != null;
  bool get _isRetiredTemplate =>
      widget.existingRevision?.isRetiredTemplate == true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final revision = widget.existingRevision;
    final assignment = widget.assignment;
    final revisionAssessment = revision?.spec is TeacherReviewedMovementSpec
        ? (revision!.spec as TeacherReviewedMovementSpec).effectiveAssessment
        : null;
    final existingAssessment =
        assignment?.activityAssessment ?? revisionAssessment;
    final savedScore = assignment?.maxScore;
    final fallbackMaximumScore =
        savedScore != null && savedScore >= 1 && savedScore <= 100
        ? savedScore
        : TeacherActivityAssessmentContract.defaultMaximumScore;
    final fallbackAssessment = TeacherActivityAssessmentConfig(
      readiness: const TeacherActivityReadinessSpec(),
      rubric: TeacherActivityRubric.builtIn(
        TeacherActivityRubricTemplate.standardTechnique,
        fallbackMaximumScore,
      ),
      recordingDurationSeconds:
          TeacherActivityAssessmentContract.defaultRecordingDurationSeconds,
    );
    _draft = existing == null && assignment == null
        ? TeacherMovementBuilderDraft()
        : TeacherMovementBuilderDraft.editingExisting(
            title: assignment?.displayTitle ?? existing!.title,
            instructions:
                assignment?.displayInstructions ??
                revision?.spec.instructions ??
                '',
            requiredProp:
                assignment?.allowedProp ??
                revision?.spec.requiredProp ??
                TrainingProp.bottle,
            safetyGuidance:
                assignment?.displaySafetyGuidance ??
                revision?.spec.safetyGuidance,
            assessment: existingAssessment ?? fallbackAssessment,
          );
    _dueAt = assignment?.dueAt;
    _hasDueDate = _dueAt != null;
    _attemptPolicy =
        assignment?.attemptPolicy ??
        AssignmentAttemptPolicy.teacherActivityDefault;
    _audienceType =
        assignment?.audience.type ?? AssignmentAudienceType.entireClass;
    _recipientIds = {...?assignment?.audience.targetTraineeIds};
    _title = TextEditingController(text: _draft.title);
    _instructions = TextEditingController(text: _draft.instructions);
    _safety = TextEditingController(text: _draft.safetyGuidance);
    _customMaximumScore = TextEditingController(
      text: _draft.usesCustomMaximumScore ? '${_draft.maximumScore}' : '',
    );
    final existingRubric = existingAssessment?.rubric;
    final seedCriteria =
        existingRubric?.template == TeacherActivityRubricTemplate.custom
        ? existingRubric!.criteria
        : TeacherActivityRubric.builtIn(
            _draft.rubricTemplate == TeacherActivityRubricTemplate.custom
                ? TeacherActivityRubricTemplate.standardTechnique
                : _draft.rubricTemplate,
            _draft.hasValidMaximumScore
                ? _draft.maximumScore
                : TeacherActivityAssessmentContract.defaultMaximumScore,
          ).criteria;
    _customCriteria = [
      for (final criterion in seedCriteria)
        _CustomCriterionControllers.fromCriterion(criterion),
    ];
    _nextCustomCriterionId = _customCriteria.length + 1;
  }

  @override
  void dispose() {
    unawaited(_demoPlayback.release());
    _title.dispose();
    _instructions.dispose();
    _safety.dispose();
    _customMaximumScore.dispose();
    for (final criterion in _customCriteria) {
      criterion.dispose();
    }
    super.dispose();
  }

  TeacherActivityAssessmentConfig? _buildAssessment() {
    TeacherActivityRubric rubric;
    if (_draft.rubricTemplate == TeacherActivityRubricTemplate.custom) {
      final criteria = _customCriteria
          .map((item) => item.toCriterion())
          .whereType<TeacherActivityRubricCriterion>()
          .toList(growable: false);
      final total = criteria.fold<int>(
        0,
        (sum, criterion) => sum + criterion.maximumPoints,
      );
      _draft.maximumScore = total;
      rubric = TeacherActivityRubric(
        template: TeacherActivityRubricTemplate.custom,
        maximumScore: total,
        criteria: criteria,
      );
      if (criteria.length != _customCriteria.length || !rubric.isValid) {
        return null;
      }
    } else {
      if (!_draft.hasValidMaximumScore) return null;
      rubric = TeacherActivityRubric.builtIn(
        _draft.rubricTemplate,
        _draft.maximumScore,
      );
    }
    return TeacherActivityAssessmentConfig(
      readiness: _draft.readiness,
      rubric: rubric,
      recordingDurationSeconds: _draft.recordingDurationSeconds,
      demonstrationVideo: _draft.demonstrationVideo,
    );
  }

  void _addCustomCriterion() {
    if (_customCriteria.length >= 5) return;
    setState(() {
      _customCriteria.add(
        _CustomCriterionControllers.empty(_nextCustomCriterionId++),
      );
    });
  }

  void _removeCustomCriterion(int index) {
    if (_customCriteria.length <= 3) return;
    setState(() => _customCriteria.removeAt(index).dispose());
  }

  Future<void> _pickAndUploadDemo() async {
    if (_uploadingDemo || _saving) return;
    final upload = widget.onUploadDemonstration;
    if (upload == null) {
      setState(() {
        _validationMessage = 'Demonstration upload is unavailable right now.';
      });
      return;
    }
    final selected = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (selected == null || !mounted) return;
    final file = File(selected.path);
    try {
      if (!selected.name.toLowerCase().endsWith('.mp4')) {
        throw const FormatException('Choose an MP4 video file.');
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size < 1) {
        throw const FormatException('Choose a non-empty MP4 file.');
      }
      if (stat.size > 50 * 1024 * 1024) {
        throw const FormatException(
          'Demonstration videos must be 50 MiB or smaller.',
        );
      }

      // Media Foundation is the same player used for in-app playback. Opening
      // it here verifies the selected file is playable and gives us a trusted
      // duration before anything is uploaded.
      final player = WinVideoPlayerController.file(file);
      Duration duration;
      try {
        await player.initialize();
        duration = player.value.duration;
      } finally {
        await player.dispose();
      }
      if (duration.inMilliseconds < 1 || duration.inMilliseconds > 60000) {
        throw const FormatException(
          'Demonstration videos must be between 1 second and 60 seconds.',
        );
      }
      if (!mounted) return;
      setState(() {
        _uploadingDemo = true;
        _validationMessage = null;
      });
      final metadata = await upload(
        localFile: file,
        duration: duration,
        source: TeacherActivityDemoSource.uploaded,
      );
      if (!mounted) return;
      setState(() {
        _draft.demonstrationVideo = metadata;
        _demoFile = file;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _validationMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _validationMessage =
              'Could not verify and upload this demonstration video.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingDemo = false);
    }
  }

  Future<void> _removeDemo() async {
    await _demoPlayback.release();
    if (!mounted) return;
    setState(() {
      _demoFile = null;
      _draft.demonstrationVideo = null;
    });
  }

  Future<void> _recordDemoWithElixr() async {
    if (_uploadingDemo || _saving) return;
    final upload = widget.onUploadDemonstration;
    if (upload == null) {
      setState(() {
        _validationMessage =
            'Demonstration recording is unavailable right now.';
      });
      return;
    }
    final metadata = await showTeacherDemoRecordingDialog(
      context,
      upload: upload,
    );
    if (!mounted || metadata == null) return;
    await _demoPlayback.release();
    setState(() {
      _draft.demonstrationVideo = metadata;
      _demoFile = null;
      _validationMessage = null;
    });
  }

  void _syncDraftText() {
    _draft.title = _title.text;
    _draft.instructions = _instructions.text;
    _draft.safetyGuidance = _safety.text;
  }

  Future<void> _save() async {
    if (_isRetiredTemplate || _saving) return;
    _syncDraftText();
    final titleError = TeacherReviewedMovementSpec.validateTitle(_draft.title);
    final instructionsError = TeacherReviewedMovementSpec.validateInstructions(
      _draft.instructions,
    );
    final safetyError = TeacherReviewedMovementSpec.validateSafetyGuidance(
      _draft.safetyGuidance,
    );
    final assessment = _buildAssessment();
    if (titleError != null ||
        instructionsError != null ||
        safetyError != null ||
        assessment == null) {
      setState(() {
        _validationMessage =
            titleError ??
            instructionsError ??
            safetyError ??
            (!_draft.hasValidMaximumScore
                ? 'Choose a valid maximum score from 1 to 100.'
                : 'Use 3–5 complete rubric criteria whose points total the maximum score.');
      });
      return;
    }
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    try {
      if (_isAssignmentEditor) {
        final audience = switch (_audienceType) {
          AssignmentAudienceType.entireClass =>
            const AssignmentAudience.entireClass(),
          AssignmentAudienceType.selectedStudents =>
            AssignmentAudience.selectedStudents(_recipientIds),
          AssignmentAudienceType.individualStudent =>
            AssignmentAudience.individualStudent(_recipientIds),
        };
        if (_audienceType != AssignmentAudienceType.entireClass &&
            _recipientIds.isEmpty) {
          throw StateError('Choose at least one approved student.');
        }
        await widget.onEditAssignment!(
          title: _draft.title,
          instructions: _draft.instructions,
          requiredProp: _draft.requiredProp,
          safetyGuidance: _draft.safetyGuidance,
          assessment: assessment,
          attemptPolicy: _attemptPolicy,
          audience: audience,
          dueAt: _hasDueDate ? _dueAt : null,
        );
      } else if (_isEditing) {
        if (widget.onEditActivity != null) {
          await widget.onEditActivity!(
            title: _draft.title,
            instructions: _draft.instructions,
            requiredProp: _draft.requiredProp,
            safetyGuidance: _draft.safetyGuidance,
            assessment: assessment,
          );
        } else {
          await widget.onEditTeacherReviewed?.call(
            title: _draft.title,
            instructions: _draft.instructions,
            requiredProp: _draft.requiredProp,
            safetyGuidance: _draft.safetyGuidance,
          );
        }
      } else {
        if (widget.onCreateActivity != null) {
          await widget.onCreateActivity!(
            title: _draft.title,
            instructions: _draft.instructions,
            requiredProp: _draft.requiredProp,
            safetyGuidance: _draft.safetyGuidance,
            assessment: assessment,
          );
        } else {
          await widget.onCreateTeacherReviewed(
            title: _draft.title,
            instructions: _draft.instructions,
            requiredProp: _draft.requiredProp,
            safetyGuidance: _draft.safetyGuidance,
          );
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _validationMessage = error.message.toString());
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(
          () => _validationMessage =
              'Could not save the Classroom Activity. Please try again.',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_isRetiredTemplate && !_saving;
    final accent = _isRetiredTemplate
        ? context.elixColors.warning
        : context.elixColors.brandPrimary;
    final heading = _isAssignmentEditor
        ? 'Edit Classroom Activity'
        : _isEditing
        ? 'Edit Teacher Activity'
        : 'Create Teacher Activity';
    final subtitle = _isAssignmentEditor
        ? 'Update this Classroom Activity for future trainee attempts.'
        : _isRetiredTemplate
        ? 'Review the preserved details for this historical movement.'
        : _isEditing
        ? 'Publish a new teacher-reviewed Activity revision for future assignments.'
        : 'Define a focused Activity for trainees to record and submit.';

    return FocusTraversalGroup(
      child: ElixScaffoldPage(
        padding: EdgeInsets.zero,
        header: ElixEditorialPageHeader(
          heading: heading,
          eyebrow: _isAssignmentEditor
              ? 'CLASSROOM ACTIVITY'
              : 'TEACHER ACTIVITIES',
          subtitle: subtitle,
          leading: Icon(FluentIcons.learning_tools, color: accent),
        ),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReviewModeNotice(isRetiredTemplate: _isRetiredTemplate),
                  if (_validationMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ValidationNotice(message: _validationMessage!),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _FormSection(
                    icon: FluentIcons.edit,
                    title: 'Activity details',
                    description: 'Name the Activity and its practice steps.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BuilderField(
                          label: 'Title',
                          helperText:
                              'Use a short, recognizable Activity name.',
                          showHelper: false,
                          child: TextBox(
                            key: const ValueKey('builder-title'),
                            controller: _title,
                            enabled: fieldsEnabled,
                            autofocus: fieldsEnabled,
                            placeholder: 'Activity title',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _BuilderField(
                          label: 'Instructions',
                          helperText:
                              'Describe what the trainee should practice and submit.',
                          child: TextBox(
                            key: const ValueKey('builder-instructions'),
                            controller: _instructions,
                            enabled: fieldsEnabled,
                            minLines: 3,
                            maxLines: 3,
                            placeholder: 'Enter step-by-step practice guidance',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final practiceSetup = _FormSection(
                        icon: FluentIcons.product_variant,
                        title: 'Practice setup',
                        description:
                            'Choose the prop trainees need before recording.',
                        compact: true,
                        child: _BuilderField(
                          label: 'Required prop',
                          helperText:
                              'ELIXR checks that this prop is visible before recording begins.',
                          child: SizedBox(
                            width: double.infinity,
                            child: ComboBox<TrainingProp>(
                              value: _draft.requiredProp,
                              isExpanded: true,
                              items: [
                                for (final value in TrainingProp.values)
                                  ComboBoxItem(
                                    value: value,
                                    child: Text(value.displayLabel),
                                  ),
                              ],
                              onChanged: fieldsEnabled
                                  ? (value) {
                                      if (value == null) return;
                                      setState(
                                        () => _draft.requiredProp = value,
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      );
                      final safetyGuidance = _FormSection(
                        icon: FluentIcons.shield,
                        title: 'Safety guidance',
                        description:
                            'Optional advice for a safer practice space.',
                        optional: true,
                        compact: true,
                        child: _BuilderField(
                          label: 'Guidance for trainees',
                          helperText: 'Add clearance or handling reminders.',
                          child: TextBox(
                            key: const ValueKey('builder-safety'),
                            controller: _safety,
                            enabled: fieldsEnabled,
                            minLines: 3,
                            maxLines: 3,
                            placeholder:
                                'Example: Keep the practice area clear',
                          ),
                        ),
                      );

                      if (constraints.maxWidth >= 620) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: practiceSetup),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(child: safetyGuidance),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          practiceSetup,
                          const SizedBox(height: AppSpacing.lg),
                          safetyGuidance,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FormSection(
                    icon: FluentIcons.heart,
                    title: 'Practice requirements',
                    description:
                        'ELIXR checks the required prop plus these visibility requirements before recording.',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final fields = [
                          _BuilderField(
                            label: 'Hand readiness',
                            helperText: 'How many hands must be visible.',
                            child: ComboBox<ActivityHandRequirement>(
                              key: const ValueKey('builder-readiness-hands'),
                              value: _draft.readiness.hands,
                              isExpanded: true,
                              items: [
                                for (final value
                                    in ActivityHandRequirement.values)
                                  ComboBoxItem(
                                    value: value,
                                    child: Text(value.displayLabel),
                                  ),
                              ],
                              onChanged: fieldsEnabled
                                  ? (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _draft.readiness =
                                            TeacherActivityReadinessSpec(
                                              hands: value,
                                              body: _draft.readiness.body,
                                            );
                                      });
                                    }
                                  : null,
                            ),
                          ),
                          _BuilderField(
                            label: 'Body readiness',
                            helperText:
                                'Whether the trainee’s upper body must be visible.',
                            child: ComboBox<ActivityBodyRequirement>(
                              key: const ValueKey('builder-readiness-body'),
                              value: _draft.readiness.body,
                              isExpanded: true,
                              items: [
                                for (final value
                                    in ActivityBodyRequirement.values)
                                  ComboBoxItem(
                                    value: value,
                                    child: Text(value.displayLabel),
                                  ),
                              ],
                              onChanged: fieldsEnabled
                                  ? (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _draft.readiness =
                                            TeacherActivityReadinessSpec(
                                              hands: _draft.readiness.hands,
                                              body: value,
                                            );
                                      });
                                    }
                                  : null,
                            ),
                          ),
                        ];
                        if (constraints.maxWidth >= 700) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var index = 0;
                                index < fields.length;
                                index++
                              ) ...[
                                Expanded(child: fields[index]),
                                if (index < fields.length - 1)
                                  const SizedBox(width: AppSpacing.md),
                              ],
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < fields.length;
                              index++
                            ) ...[
                              fields[index],
                              if (index < fields.length - 1)
                                const SizedBox(height: AppSpacing.md),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _FormSection(
                    icon: FluentIcons.clipboard_list,
                    title: 'Scoring & rubric',
                    description:
                        'Use a built-in rubric or define 3–5 transparent criteria.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BuilderField(
                          label: 'Rubric template',
                          helperText:
                              'Criteria scale automatically to the maximum score.',
                          child: ComboBox<TeacherActivityRubricTemplate>(
                            key: const ValueKey('builder-rubric-template'),
                            value: _draft.rubricTemplate,
                            isExpanded: true,
                            items: [
                              for (final value
                                  in TeacherActivityRubricTemplate.values)
                                ComboBoxItem(
                                  value: value,
                                  child: Text(value.displayLabel),
                                ),
                            ],
                            onChanged: fieldsEnabled
                                ? (value) {
                                    if (value == null) return;
                                    setState(
                                      () => _draft.rubricTemplate = value,
                                    );
                                  }
                                : null,
                          ),
                        ),
                        if (_draft.rubricTemplate ==
                            TeacherActivityRubricTemplate.custom) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Custom criteria',
                            style: AppTheme.label(
                              color: context.elixTextPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Enter 3–5 criteria. Their point maximums must total ${_draft.maximumScore}.',
                            style: AppTheme.supporting(
                              color: context.elixTextSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          for (
                            var index = 0;
                            index < _customCriteria.length;
                            index++
                          ) ...[
                            _CustomCriterionEditor(
                              index: index,
                              controllers: _customCriteria[index],
                              enabled: fieldsEnabled,
                              canRemove: _customCriteria.length > 3,
                              onRemove: () => _removeCustomCriterion(index),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          Button(
                            key: const ValueKey('builder-add-custom-criterion'),
                            onPressed:
                                fieldsEnabled && _customCriteria.length < 5
                                ? _addCustomCriterion
                                : null,
                            child: const Text('Add criterion'),
                          ),
                        ],
                        if (_draft.rubricTemplate !=
                            TeacherActivityRubricTemplate.custom) ...[
                          const SizedBox(height: AppSpacing.md),
                          _BuilderField(
                            label: 'Maximum score',
                            helperText:
                                'Choose 30, 50, or 100 points, or enter a whole number from 1 to 100.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ComboBox<String>(
                                  key: const ValueKey(
                                    'builder-max-score-preset',
                                  ),
                                  value: _draft.usesCustomMaximumScore
                                      ? 'custom'
                                      : '${_draft.maximumScore}',
                                  isExpanded: true,
                                  items: const [
                                    ComboBoxItem(
                                      value: '30',
                                      child: Text('30 points'),
                                    ),
                                    ComboBoxItem(
                                      value: '50',
                                      child: Text('50 points'),
                                    ),
                                    ComboBoxItem(
                                      value: '100',
                                      child: Text('100 points'),
                                    ),
                                    ComboBoxItem(
                                      value: 'custom',
                                      child: Text('Custom maximum score'),
                                    ),
                                  ],
                                  onChanged: fieldsEnabled
                                      ? (value) {
                                          if (value == null) return;
                                          setState(() {
                                            if (value == 'custom') {
                                              _draft.maximumScore = 0;
                                            } else {
                                              _draft.maximumScore = int.parse(
                                                value,
                                              );
                                            }
                                          });
                                        }
                                      : null,
                                ),
                                if (_draft.usesCustomMaximumScore) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  TextBox(
                                    key: const ValueKey(
                                      'builder-custom-max-score',
                                    ),
                                    controller: _customMaximumScore,
                                    enabled: fieldsEnabled,
                                    placeholder: '1–100',
                                    onChanged: (value) => setState(() {
                                      _draft.maximumScore =
                                          int.tryParse(value.trim()) ?? 0;
                                    }),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Total: ${_customCriteria.fold<int>(0, (sum, item) => sum + (int.tryParse(item.maximumPoints.text.trim()) ?? 0))} points',
                            style: AppTheme.label(
                              color: context.elixTextPrimary,
                            ),
                          ),
                        ],
                        if (_draft.rubricTemplate !=
                                TeacherActivityRubricTemplate.custom &&
                            _draft.hasValidMaximumScore) ...[
                          const SizedBox(height: AppSpacing.md),
                          _RubricCriteriaTable(
                            criteria: TeacherActivityRubric.builtIn(
                              _draft.rubricTemplate,
                              _draft.maximumScore,
                            ).criteria,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final durationField = _BuilderField(
                              label: 'Recording duration',
                              helperText:
                                  'The maximum length for each submitted recording.',
                              child: ComboBox<int>(
                                key: const ValueKey(
                                  'builder-recording-duration',
                                ),
                                value: _draft.recordingDurationSeconds,
                                isExpanded: true,
                                items: [
                                  for (final value
                                      in TeacherActivityAssessmentContract
                                          .supportedRecordingDurations)
                                    ComboBoxItem(
                                      value: value,
                                      child: Text('$value seconds'),
                                    ),
                                ],
                                onChanged: fieldsEnabled
                                    ? (value) {
                                        if (value == null) return;
                                        setState(
                                          () =>
                                              _draft.recordingDurationSeconds =
                                                  value,
                                        );
                                      }
                                    : null,
                              ),
                            );
                            return durationField;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _DemoMediaSection(
                    metadata: _draft.demonstrationVideo,
                    localFile: _demoFile,
                    playback: _demoPlayback,
                    busy: _saving || _uploadingDemo,
                    onPickUpload: _pickAndUploadDemo,
                    onRecord: _recordDemoWithElixr,
                    onRemove: _removeDemo,
                  ),
                  if (_isAssignmentEditor) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _AssignmentSettingsSection(
                      hasDueDate: _hasDueDate,
                      dueAt: _dueAt,
                      attemptPolicy: _attemptPolicy,
                      audienceType: _audienceType,
                      recipientIds: _recipientIds,
                      memberships: widget.approvedMemberships,
                      enabled: fieldsEnabled,
                      onDueDateChanged: (value) => setState(() {
                        _hasDueDate = value;
                        _dueAt ??= DateTime.now().add(const Duration(days: 7));
                      }),
                      onDueAtChanged: (value) => setState(() => _dueAt = value),
                      onAttemptPolicyChanged: (value) =>
                          setState(() => _attemptPolicy = value),
                      onAudienceTypeChanged: (value) => setState(() {
                        _audienceType = value;
                        if (value == AssignmentAudienceType.entireClass) {
                          _recipientIds.clear();
                        } else if (value ==
                                AssignmentAudienceType.individualStudent &&
                            _recipientIds.length > 1) {
                          _recipientIds = {_recipientIds.first};
                        }
                      }),
                      onRecipientChanged: (traineeId, selected) => setState(() {
                        if (selected) {
                          if (_audienceType ==
                              AssignmentAudienceType.individualStudent) {
                            _recipientIds = {traineeId};
                          } else {
                            _recipientIds.add(traineeId);
                          }
                        } else {
                          _recipientIds.remove(traineeId);
                        }
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomBar: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: context.elixCardSurface,
            border: Border(top: BorderSide(color: context.elixBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(_isRetiredTemplate ? 'Close' : 'Cancel'),
              ),
              if (!_isRetiredTemplate) ...[
                const SizedBox(width: AppSpacing.sm),
                ElixPrimaryButton(
                  key: const ValueKey('teacher-reviewed-save'),
                  label: _isAssignmentEditor
                      ? 'Save assignment changes'
                      : _isEditing
                      ? 'Save revision'
                      : 'Create',
                  expanded: false,
                  dense: true,
                  isLoading: _saving,
                  onPressed:
                      _isEditing &&
                          !_isAssignmentEditor &&
                          widget.onEditTeacherReviewed == null
                      ? null
                      : _save,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RubricCriteriaTable extends StatelessWidget {
  const _RubricCriteriaTable({required this.criteria});

  final List<TeacherActivityRubricCriterion> criteria;

  @override
  Widget build(BuildContext context) {
    final total = criteria.fold<int>(
      0,
      (sum, criterion) => sum + criterion.maximumPoints,
    );
    return Container(
      key: const ValueKey('builder-rubric-criteria-table'),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        border: Border.all(color: context.elixBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(6),
          2: IntrinsicColumnWidth(),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: context.elixBorder),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: context.elixColors.brandPrimary),
            children: const [
              _CriteriaTableCell('Criterion', header: true),
              _CriteriaTableCell('What the Teacher assesses', header: true),
              _CriteriaTableCell('Points', header: true, alignEnd: true),
            ],
          ),
          for (final criterion in criteria)
            TableRow(
              children: [
                _CriteriaTableCell(criterion.label),
                _CriteriaTableCell(criterion.description),
                _CriteriaTableCell(
                  '${criterion.maximumPoints}',
                  alignEnd: true,
                ),
              ],
            ),
          TableRow(
            decoration: BoxDecoration(color: context.elixColors.surfaceTinted),
            children: [
              const _CriteriaTableCell('Total', header: true),
              const _CriteriaTableCell('', header: true),
              _CriteriaTableCell('$total points', header: true, alignEnd: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _CriteriaTableCell extends StatelessWidget {
  const _CriteriaTableCell(
    this.text, {
    this.header = false,
    this.alignEnd = false,
  });

  final String text;
  final bool header;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    child: Text(
      text,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: header
          ? AppTheme.label(color: context.elixTextPrimary)
          : AppTheme.body.copyWith(color: context.elixTextSecondary),
    ),
  );
}

class _AssignmentSettingsSection extends StatelessWidget {
  const _AssignmentSettingsSection({
    required this.hasDueDate,
    required this.dueAt,
    required this.attemptPolicy,
    required this.audienceType,
    required this.recipientIds,
    required this.memberships,
    required this.enabled,
    required this.onDueDateChanged,
    required this.onDueAtChanged,
    required this.onAttemptPolicyChanged,
    required this.onAudienceTypeChanged,
    required this.onRecipientChanged,
  });

  final bool hasDueDate;
  final DateTime? dueAt;
  final AssignmentAttemptPolicy attemptPolicy;
  final AssignmentAudienceType audienceType;
  final Set<String> recipientIds;
  final List<GroupMembership> memberships;
  final bool enabled;
  final ValueChanged<bool> onDueDateChanged;
  final ValueChanged<DateTime> onDueAtChanged;
  final ValueChanged<AssignmentAttemptPolicy> onAttemptPolicyChanged;
  final ValueChanged<AssignmentAudienceType> onAudienceTypeChanged;
  final void Function(String traineeId, bool selected) onRecipientChanged;

  @override
  Widget build(BuildContext context) => _FormSection(
    icon: FluentIcons.assign,
    title: 'Assignment settings',
    description:
        'Set access, attempts, and the optional due date for this class.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Checkbox(
          checked: hasDueDate,
          onChanged: enabled
              ? (value) => onDueDateChanged(value ?? false)
              : null,
          content: const Text('Set a due date'),
        ),
        if (hasDueDate) ...[
          const SizedBox(height: AppSpacing.xs),
          DatePicker(
            selected: dueAt ?? DateTime.now(),
            onChanged: enabled ? onDueAtChanged : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _BuilderField(
          label: 'Attempt limit',
          helperText: 'Limit how many recordings each trainee may submit.',
          child: ComboBox<String>(
            value: attemptPolicy.isUnlimited
                ? 'unlimited'
                : '${attemptPolicy.maximumAttempts}',
            isExpanded: true,
            items: const [
              ComboBoxItem(value: '1', child: Text('1 attempt')),
              ComboBoxItem(value: '2', child: Text('2 attempts')),
              ComboBoxItem(value: '3', child: Text('3 attempts')),
              ComboBoxItem(value: 'unlimited', child: Text('Unlimited')),
            ],
            onChanged: !enabled
                ? null
                : (value) {
                    if (value == null) return;
                    onAttemptPolicyChanged(
                      value == 'unlimited'
                          ? const AssignmentAttemptPolicy.unlimited()
                          : AssignmentAttemptPolicy.finite(int.parse(value)),
                    );
                  },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _BuilderField(
          label: 'Assign to',
          helperText: 'Choose the trainees who can access this Activity.',
          child: ComboBox<AssignmentAudienceType>(
            value: audienceType,
            isExpanded: true,
            items: const [
              ComboBoxItem(
                value: AssignmentAudienceType.entireClass,
                child: Text('Entire class'),
              ),
              ComboBoxItem(
                value: AssignmentAudienceType.selectedStudents,
                child: Text('Selected students'),
              ),
              ComboBoxItem(
                value: AssignmentAudienceType.individualStudent,
                child: Text('One student'),
              ),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) onAudienceTypeChanged(value);
                  }
                : null,
          ),
        ),
        if (audienceType != AssignmentAudienceType.entireClass) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final membership in memberships)
            Checkbox(
              checked: recipientIds.contains(membership.traineeId),
              onChanged: enabled
                  ? (value) =>
                        onRecipientChanged(membership.traineeId, value ?? false)
                  : null,
              content: Text(membership.traineeDisplayName),
            ),
        ],
      ],
    ),
  );
}

class _CustomCriterionControllers {
  _CustomCriterionControllers({
    required this.id,
    required String label,
    required String description,
    required int maximumPoints,
  }) : label = TextEditingController(text: label),
       description = TextEditingController(text: description),
       maximumPoints = TextEditingController(text: '$maximumPoints');

  factory _CustomCriterionControllers.fromCriterion(
    TeacherActivityRubricCriterion criterion,
  ) => _CustomCriterionControllers(
    id: criterion.id,
    label: criterion.label,
    description: criterion.description,
    maximumPoints: criterion.maximumPoints,
  );

  factory _CustomCriterionControllers.empty(int ordinal) =>
      _CustomCriterionControllers(
        id: 'custom_$ordinal',
        label: '',
        description: '',
        maximumPoints: 1,
      );

  final String id;
  final TextEditingController label;
  final TextEditingController description;
  final TextEditingController maximumPoints;

  TeacherActivityRubricCriterion? toCriterion() {
    final resolvedLabel = label.text.trim();
    final resolvedDescription = description.text.trim();
    final resolvedMaximum = int.tryParse(maximumPoints.text.trim());
    if (resolvedLabel.isEmpty ||
        resolvedLabel.length > 80 ||
        resolvedDescription.isEmpty ||
        resolvedDescription.length > 500 ||
        resolvedMaximum == null ||
        resolvedMaximum < 1 ||
        resolvedMaximum > 100) {
      return null;
    }
    return TeacherActivityRubricCriterion(
      id: id,
      label: resolvedLabel,
      description: resolvedDescription,
      maximumPoints: resolvedMaximum,
    );
  }

  void dispose() {
    label.dispose();
    description.dispose();
    maximumPoints.dispose();
  }
}

class _CustomCriterionEditor extends StatelessWidget {
  const _CustomCriterionEditor({
    required this.index,
    required this.controllers,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final _CustomCriterionControllers controllers;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: context.elixBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Criterion ${index + 1}',
                style: AppTheme.label(color: context.elixTextPrimary),
              ),
            ),
            if (canRemove)
              IconButton(
                key: ValueKey('builder-remove-custom-criterion-$index'),
                icon: const Icon(FluentIcons.delete),
                onPressed: enabled ? onRemove : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: ValueKey('builder-custom-criterion-label-$index'),
          controller: controllers.label,
          enabled: enabled,
          placeholder: 'Criterion label',
          maxLength: 80,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: ValueKey('builder-custom-criterion-description-$index'),
          controller: controllers.description,
          enabled: enabled,
          placeholder: 'What the Teacher will assess',
          maxLength: 500,
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: ValueKey('builder-custom-criterion-points-$index'),
          controller: controllers.maximumPoints,
          enabled: enabled,
          placeholder: 'Maximum points',
        ),
      ],
    ),
  );
}

class _DemoMediaSection extends StatelessWidget {
  const _DemoMediaSection({
    required this.metadata,
    required this.localFile,
    required this.playback,
    required this.busy,
    required this.onPickUpload,
    required this.onRecord,
    required this.onRemove,
  });

  final TeacherActivityVideoMetadata? metadata;
  final File? localFile;
  final ElixrPlaybackSession playback;
  final bool busy;
  final Future<void> Function() onPickUpload;
  final Future<void> Function() onRecord;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final tone = context.elixColors.brandSecondary;
    final demo = metadata;
    return Semantics(
      label: 'Activity demonstration media',
      child: Container(
        key: const ValueKey('builder-demo-media-placeholder'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.isHighContrast
              ? context.elixCardSurface
              : tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : tone.withValues(alpha: 0.24),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FluentIcons.video,
              size: 17,
              color: context.isHighContrast ? context.elixTextPrimary : tone,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demonstration media',
                    style: AppTheme.label(color: context.elixTextPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (demo == null)
                    Text(
                      'Attach one MP4 from your gallery (maximum 50 MiB and 60 seconds).',
                      style: AppTheme.supporting(
                        color: context.elixTextSecondary,
                      ),
                    )
                  else ...[
                    Text(
                      'Attached ${demo.durationMs ~/ 1000}s MP4 · ${(demo.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MiB',
                      style: AppTheme.supporting(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    if (localFile != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 180,
                        child: ElixrVideoPlayer(
                          key: ValueKey(localFile!.path),
                          source: Uri.file(localFile!.path),
                          mirrored: false,
                          session: playback,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Button(
                        key: const ValueKey('builder-demo-upload'),
                        onPressed: busy ? null : onPickUpload,
                        child: Text(
                          demo == null ? 'Upload MP4' : 'Replace MP4',
                        ),
                      ),
                      Button(
                        key: const ValueKey('builder-demo-record'),
                        onPressed: busy ? null : onRecord,
                        child: Text(
                          demo == null
                              ? 'Record with ELIXR'
                              : 'Replace by recording',
                        ),
                      ),
                      if (demo != null)
                        Button(
                          key: const ValueKey('builder-demo-remove'),
                          onPressed: busy ? null : onRemove,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Direct recording uses the selected camera through ELIXR’s Python camera service.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewModeNotice extends StatelessWidget {
  const _ReviewModeNotice({required this.isRetiredTemplate});

  final bool isRetiredTemplate;

  @override
  Widget build(BuildContext context) {
    if (isRetiredTemplate) {
      final tone = context.elixColors.warning;
      return ElixPanelCard(
        accent: tone,
        showAccentBar: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _ReviewNoticeContent(tone: tone),
      );
    }

    final tone = context.elixColors.brandSecondary;
    return Semantics(
      label: 'Teacher reviewed. No automatic ELIXR score is produced.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.isHighContrast
              ? context.elixCardSurface
              : tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.isHighContrast
                ? context.elixBorder
                : tone.withValues(alpha: 0.22),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.education,
              size: 15,
              color: context.isHighContrast ? context.elixTextPrimary : tone,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Teacher reviewed',
              style: AppTheme.caption.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No automatic ELIXR score',
                textAlign: TextAlign.end,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNoticeContent extends StatelessWidget {
  const _ReviewNoticeContent({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          FluentIcons.warning,
          size: 18,
          color: context.isHighContrast ? context.elixTextPrimary : tone,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historical template scoring',
                style: AppTheme.label(color: context.elixTextPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Automatic template assessment has been retired. '
                'This historical movement is read-only; previous scores '
                'remain available in classroom history.',
                style: AppTheme.supporting(color: context.elixTextSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValidationNotice extends StatelessWidget {
  const _ValidationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = context.elixColors.warning;
    return Container(
      key: const ValueKey('builder-validation'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : tone.withValues(alpha: 0.35),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.warning, size: 16, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTheme.supporting(color: context.elixTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.optional = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final bool optional;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.isHighContrast
                ? context.elixBorder
                : context.elixBorder.withValues(alpha: 0.7),
            width: context.isHighContrast ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 16,
                color: context.isHighContrast
                    ? context.elixTextPrimary
                    : context.elixColors.brandPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTheme.label(
                              color: context.elixTextPrimary,
                            ),
                          ),
                        ),
                        if (optional) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'OPTIONAL',
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _BuilderField extends StatelessWidget {
  const _BuilderField({
    required this.label,
    required this.helperText,
    required this.child,
    this.showHelper = true,
  });

  final String label;
  final String helperText;
  final Widget child;
  final bool showHelper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: AppTheme.label(color: context.elixTextPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (showHelper) ...[
          ExcludeSemantics(
            child: Text(
              helperText,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else
          const SizedBox(height: AppSpacing.xs),
        MergeSemantics(
          child: Semantics(label: label, hint: helperText, child: child),
        ),
      ],
    );
  }
}
