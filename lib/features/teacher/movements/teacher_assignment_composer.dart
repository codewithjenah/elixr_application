import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/auth/teacher_auth_messages.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movements.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/assessment_mode.dart';
import '../../../data/models/assignment_submission_limits.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/teacher_reviewed_movement_spec.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';
import 'teacher_movement_builder_dialog.dart';

const _teacherAssignmentContentMaxWidth = 1120.0;
const _teacherAssignmentWideBreakpoint = 900.0;

/// The one write path used by both movement-first and classroom-first
/// assignment creation.
class TeacherAssignmentCreationService {
  const TeacherAssignmentCreationService({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.assignmentRepository,
    this.movementRepository,
    this.ensureTeacherAuthorization,
  });

  final String teacherId;
  final String teacherDisplayName;
  final ClassroomAssignmentRepository assignmentRepository;
  final TeacherMovementRepository? movementRepository;
  final Future<bool> Function()? ensureTeacherAuthorization;

  /// Creates either an Official ELIXR or Teacher-created assignment.
  ///
  /// Keeping the origin selection and revision lookup here means both
  /// composer entry points produce the same repository payload and enforce
  /// the same current-revision semantics.
  Future<GroupAssignment> create({
    required ElixrGroup group,
    Movement? officialMovement,
    TeacherMovement? teacherCreatedMovement,
    int maxScore = 100,
    DateTime? dueAt,
  }) async {
    final hasOfficial = officialMovement != null;
    final hasTeacherCreated = teacherCreatedMovement != null;
    if (hasOfficial == hasTeacherCreated) {
      throw const ClassroomException(
        ClassroomError.identityMismatch,
        'Choose one movement to assign.',
      );
    }

    if (hasTeacherCreated) {
      ensureTeacherAssignmentMaxScore(maxScore);
    }
    await _ensureTeacherAuthorization();

    final official = officialMovement;
    if (official != null) {
      return assignmentRepository.createOfficialAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        officialMovementName: official.name,
        dueAt: dueAt,
        displayInstructions: official.description,
      );
    }

    final selectedCustom = teacherCreatedMovement!;
    final movementRepository = this.movementRepository;
    if (movementRepository == null) {
      throw const ClassroomException(
        ClassroomError.notFound,
        'Teacher-created movement data is unavailable right now.',
      );
    }
    // The picker can hold a snapshot from before the teacher edits or
    // deletes a movement. Re-read the root immediately before writing so the
    // assignment always pins the movement's actual current revision.
    final custom = await movementRepository.getMovement(
      movementId: selectedCustom.id,
    );
    if (custom == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (custom.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final revision = await movementRepository.getRevision(
      movementId: custom.id,
      revisionId: custom.currentRevisionId,
    );
    if (revision == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    return assignmentRepository.createTeacherCreatedAssignment(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: custom,
      revision: revision,
      maxScore: maxScore,
      dueAt: dueAt,
    );
  }

  Future<TeacherMovement> createTeacherReviewedMovement({
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final movementRepository = this.movementRepository;
    if (movementRepository == null) {
      throw const ClassroomException(
        ClassroomError.notFound,
        'Teacher-created movement data is unavailable right now.',
      );
    }
    await _ensureTeacherAuthorization();
    return movementRepository.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
  }

  Future<void> _ensureTeacherAuthorization() async {
    final ensure = ensureTeacherAuthorization;
    if (ensure == null) return;
    if (!await ensure()) {
      throw const ClassroomException(
        ClassroomError.forbidden,
        TeacherAuthMessages.teacherAuthorizationRefreshRequired,
      );
    }
  }
}

/// Opens the shared assignment composer as a full-page Teacher workspace.
///
/// When [officialMovement] or [teacherCreatedMovement] is supplied, the
/// screen is movement-scoped and lets the teacher choose an active classroom.
/// When neither is supplied, it is classroom-scoped and [lockedGroup] is
/// displayed as fixed context while the teacher chooses the movement.
Future<bool?> showTeacherAssignmentComposer(
  BuildContext context, {
  required String teacherId,
  required String teacherDisplayName,
  required List<ElixrGroup> groups,
  required TeacherMovementRepository? movementRepository,
  required ClassroomAssignmentRepository assignmentRepository,
  TeacherAssignmentCreationService? creationService,
  ElixrGroup? lockedGroup,
  Movement? officialMovement,
  TeacherMovement? teacherCreatedMovement,
  Future<bool> Function()? ensureTeacherAuthorization,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final service =
      creationService ??
      TeacherAssignmentCreationService(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        assignmentRepository: assignmentRepository,
        movementRepository: movementRepository,
        ensureTeacherAuthorization: ensureTeacherAuthorization,
      );
  return Navigator.of(context).push<bool>(
    PageRouteBuilder<bool>(
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      pageBuilder: (_, animation, secondaryAnimation) =>
          TeacherAssignmentComposer(
            teacherId: teacherId,
            teacherDisplayName: teacherDisplayName,
            groups: groups,
            movementRepository: movementRepository,
            creationService: service,
            lockedGroup: lockedGroup,
            officialMovement: officialMovement,
            teacherCreatedMovement: teacherCreatedMovement,
          ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.025, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class TeacherAssignmentComposer extends StatefulWidget {
  const TeacherAssignmentComposer({
    super.key,
    required this.teacherId,
    required this.teacherDisplayName,
    required this.groups,
    required this.movementRepository,
    required this.creationService,
    this.lockedGroup,
    this.officialMovement,
    this.teacherCreatedMovement,
  });

  final String teacherId;
  final String teacherDisplayName;
  final List<ElixrGroup> groups;
  final TeacherMovementRepository? movementRepository;
  final TeacherAssignmentCreationService creationService;
  final ElixrGroup? lockedGroup;
  final Movement? officialMovement;
  final TeacherMovement? teacherCreatedMovement;

  @override
  State<TeacherAssignmentComposer> createState() =>
      _TeacherAssignmentComposerState();
}

enum _AssignmentOriginSelection { official, teacherCreated }

class _TeacherAssignmentComposerState extends State<TeacherAssignmentComposer> {
  late final bool _classroomScoped;
  late final TextEditingController _maxScoreController;
  late ElixrGroup? _selectedGroup;
  late Movement? _selectedOfficialMovement;
  late TeacherMovement? _selectedTeacherCreatedMovement;
  late _AssignmentOriginSelection _origin;

  DateTime? _dueAt;
  bool _submitting = false;
  bool _creatingTeacherMovement = false;
  bool _loadingTeacherMovements = false;
  String? _movementLoadError;
  String? _validationError;
  List<TeacherMovement> _teacherMovements = const [];
  Map<String, TeacherMovementRevision> _teacherMovementRevisions = const {};
  StreamSubscription<List<TeacherMovement>>? _movementSubscription;
  int _movementLoadToken = 0;

  bool get _hasMovementOverride =>
      widget.officialMovement != null || widget.teacherCreatedMovement != null;

  List<ElixrGroup> get _activeGroups {
    final groups = [
      for (final group in widget.groups)
        if (group.isActive) group,
    ];
    final locked = widget.lockedGroup;
    if (locked != null &&
        locked.isActive &&
        !groups.any((group) => group.id == locked.id)) {
      groups.add(locked);
    }
    return groups;
  }

  bool get _isTeacherCreated =>
      _origin == _AssignmentOriginSelection.teacherCreated;

  bool get _hasValidMaxScore {
    if (!_isTeacherCreated) return true;
    final value = int.tryParse(_maxScoreController.text.trim());
    return value != null && value >= 1 && value <= 100;
  }

  bool get _hasValidTeacherMovement {
    final movement = _selectedTeacherCreatedMovement;
    if (movement == null || !movement.isActive) return false;
    if (!_classroomScoped) return true;
    final revision = _teacherMovementRevisions[movement.id];
    return revision != null && _isAssignableTeacherRevision(revision);
  }

  bool get _canSubmit =>
      !_submitting &&
      _selectedGroup?.isActive == true &&
      (_selectedOfficialMovement != null || _hasValidTeacherMovement) &&
      (!_classroomScoped || !_isTeacherCreated || !_loadingTeacherMovements) &&
      _hasValidMaxScore;

  @override
  void initState() {
    super.initState();
    _classroomScoped = !_hasMovementOverride;
    _maxScoreController = TextEditingController(text: '100');
    _selectedGroup = widget.lockedGroup ?? _firstActiveGroup();
    _selectedOfficialMovement = widget.officialMovement;
    _selectedTeacherCreatedMovement = widget.teacherCreatedMovement;
    _origin = widget.teacherCreatedMovement != null
        ? _AssignmentOriginSelection.teacherCreated
        : _AssignmentOriginSelection.official;
    if (_classroomScoped) {
      _selectedOfficialMovement = _enabledOfficialMovements.firstOrNull;
      _startWatchingTeacherMovements();
    }
  }

  ElixrGroup? _firstActiveGroup() {
    for (final group in _activeGroups) {
      return group;
    }
    return null;
  }

  List<Movement> get _enabledOfficialMovements =>
      movementCatalog.where((movement) => movement.enabled).toList();

  void _startWatchingTeacherMovements() {
    final repository = widget.movementRepository;
    if (repository == null) {
      _movementLoadError =
          'Teacher-created movements are unavailable right now.';
      return;
    }
    _loadingTeacherMovements = true;
    try {
      _movementSubscription = repository
          .watchTeacherMovements(teacherId: widget.teacherId)
          .listen(
            _onTeacherMovements,
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted) return;
              setState(() {
                _loadingTeacherMovements = false;
                _movementLoadError =
                    'Could not load Teacher-created movements.';
              });
            },
          );
    } catch (_) {
      _loadingTeacherMovements = false;
      _movementLoadError = 'Could not load Teacher-created movements.';
    }
  }

  void _onTeacherMovements(List<TeacherMovement> movements) {
    unawaited(_loadAssignableTeacherMovements(movements));
  }

  Future<void> _loadAssignableTeacherMovements(
    List<TeacherMovement> movements,
  ) async {
    final repository = widget.movementRepository;
    if (repository == null) return;
    final token = ++_movementLoadToken;
    final candidates = movements
        .where(
          (movement) =>
              movement.teacherId == widget.teacherId && movement.isActive,
        )
        .toList(growable: false);
    final revisions = <String, TeacherMovementRevision>{};
    try {
      for (final movement in candidates) {
        final revision = await repository.getRevision(
          movementId: movement.id,
          revisionId: movement.currentRevisionId,
        );
        if (revision != null && _isAssignableTeacherRevision(revision)) {
          revisions[movement.id] = revision;
        }
      }
    } catch (_) {
      if (!mounted || token != _movementLoadToken) return;
      setState(() {
        _loadingTeacherMovements = false;
        _movementLoadError = 'Could not load Teacher-created movements.';
      });
      return;
    }
    if (!mounted || token != _movementLoadToken) return;
    final assignable = [
      for (final movement in candidates)
        if (revisions.containsKey(movement.id)) movement,
    ];
    setState(() {
      _teacherMovements = assignable;
      _teacherMovementRevisions = revisions;
      _loadingTeacherMovements = false;
      _movementLoadError = null;
      final selected = _selectedTeacherCreatedMovement;
      if (selected != null &&
          !assignable.any((movement) => movement.id == selected.id)) {
        _selectedTeacherCreatedMovement = assignable.firstOrNull;
      } else if (_isTeacherCreated && selected == null) {
        _selectedTeacherCreatedMovement = assignable.firstOrNull;
      }
    });
  }

  bool _isAssignableTeacherRevision(TeacherMovementRevision revision) {
    return revision.teacherId == widget.teacherId &&
        revision.assessmentMode == AssessmentMode.teacherReviewed &&
        revision.spec is TeacherReviewedMovementSpec;
  }

  @override
  void dispose() {
    unawaited(_movementSubscription?.cancel());
    _maxScoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _classroomScoped ? 'Create assignment' : 'Assign to class';
    final subtitle = _classroomScoped
        ? 'Choose a movement, set expectations, and send it to your class.'
        : 'Choose a class and set the deadline before you publish it.';

    return TeacherScaffoldPage(
      header: ElixEditorialPageHeader(
        heading: title,
        eyebrow: 'ASSIGNMENT STUDIO',
        subtitle: subtitle,
        variant: ElixEditorialHeaderVariant.standard,
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              key: const Key('teacher_assignment_back'),
              icon: const Icon(FluentIcons.back),
              label: const Text('Back'),
              onPressed: _submitting ? null : () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _teacherAssignmentContentMaxWidth,
              ),
              child: _pageContent(context, constraints.maxWidth),
            ),
          );
        },
      ),
    );
  }

  Widget _pageContent(BuildContext context, double availableWidth) {
    if (_activeGroups.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ComposerHeroCard(
            eyebrow: 'NEEDS YOUR ATTENTION',
            title: 'No active class yet',
            description:
                'Create an active class before assigning this movement to trainees.',
            icon: FluentIcons.people,
            accent: context.elixColors.warning,
          ),
          const SizedBox(height: AppSpacing.lg),
          _ComposerSurface(
            child: ElixStatusPanel(
              message:
                  'Your movement is ready, but there is no active class to receive it.',
              icon: FluentIcons.info,
              actionLabel: 'Back',
              onAction: () => Navigator.pop(context),
            ),
          ),
        ],
      );
    }

    final form = _ComposerSurface(
      key: const Key('teacher_assignment_form'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: _content(context),
    );
    final summary = _AssignmentSummaryCard(
      key: const Key('teacher_assignment_summary'),
      group: _selectedGroup,
      movementTitle: _movementTitle,
      movementModeLabel: _movementModeLabel,
      isTeacherCreated: _isTeacherCreated,
      dueAt: _dueAt,
      canSubmit: _canSubmit,
      isSubmitting: _submitting,
      maximumScore: int.tryParse(_maxScoreController.text.trim()),
      onSubmit: _canSubmit ? () => _submit(context) : null,
    );
    final wide = availableWidth >= _teacherAssignmentWideBreakpoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComposerHeroCard(
          eyebrow: _classroomScoped ? 'NEW ASSIGNMENT' : 'MOVEMENT READY',
          title: _classroomScoped
              ? 'Build a practice brief'
              : 'Publish $_movementTitle',
          description: _classroomScoped
              ? 'Give your class a clear target and a deadline they can act on.'
              : 'One last check before this movement appears in the selected class.',
          icon: _classroomScoped ? FluentIcons.task_list : FluentIcons.send,
          accent: context.elixColors.brandPrimary,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: form),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: 330, child: summary),
            ],
          )
        else ...[
          form,
          const SizedBox(height: AppSpacing.lg),
          summary,
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Publishing sends this existing movement to the selected classroom. '
          'Movement content stays reusable in your library.',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComposerSectionHeading(
          icon: FluentIcons.people,
          eyebrow: 'AUDIENCE',
          title: 'Who is this for?',
          description: _classroomScoped
              ? 'This assignment will be shared with one class.'
              : 'Choose the class that should receive this movement.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_classroomScoped)
          _ComposerReadOnlyField(
            key: const Key('teacher_assignment_locked_group'),
            label: 'Classroom',
            value: widget.lockedGroup?.name ?? 'Classroom',
            hint: 'The class is fixed from the group workspace.',
            icon: FluentIcons.lock,
          )
        else
          _ComposerField(
            label: 'Classroom',
            hint: 'Only active classes can receive new assignments.',
            child: ComboBox<String>(
              key: const Key('teacher_assignment_class'),
              value: _selectedGroup?.id,
              isExpanded: true,
              items: [
                for (final group in _activeGroups)
                  ComboBoxItem(value: group.id, child: Text(group.name)),
              ],
              onChanged: _submitting ? null : _onGroupChanged,
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        _ComposerSectionHeading(
          icon: FluentIcons.learning_tools,
          eyebrow: 'PRACTICE SETUP',
          title: 'What should they practice?',
          description: _classroomScoped
              ? 'Pick an official movement or one of your reviewed movements.'
              : 'This movement is selected. Review the assignment settings below.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_classroomScoped) ...[
          _MovementSourceSelector(
            selected: _origin,
            enabled: !_submitting,
            onChanged: _onOriginChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _classroomMovementPicker(context),
        ] else
          _MovementIdentityCard(
            key: const Key('teacher_assignment_movement_title'),
            title: _movementTitle,
            subtitle: _movementModeLabel,
            isTeacherCreated: _isTeacherCreated,
          ),
        if (_classroomScoped && !_isTeacherCreated) ...[
          const SizedBox(height: AppSpacing.md),
          const _AutomaticScoringCard(),
        ],
        if (_isTeacherCreated && _hasValidTeacherMovement) ...[
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.calculator,
            eyebrow: 'ASSESSMENT',
            title: 'Set the grading limit',
            description:
                'Teacher-reviewed work uses the maximum score you define.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _ComposerField(
            label: 'Maximum score',
            hint: 'Enter a value from 1 to 100.',
            child: TextBox(
              key: const Key('teacher_assignment_max_score'),
              controller: _maxScoreController,
              keyboardType: TextInputType.number,
              maxLength: 3,
              enabled: !_submitting,
              onChanged: (_) => setState(() => _validationError = null),
            ),
          ),
          if (!_hasValidMaxScore && _validationError == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Enter a maximum score from 1 to 100.',
                style: AppTheme.caption.copyWith(
                  color: context.elixColors.error,
                ),
              ),
            ),
        ],
        if (!_isTeacherCreated || _hasValidTeacherMovement) ...[
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.calendar,
            eyebrow: 'DEADLINE',
            title: 'When should it be done?',
            description:
                'A due date keeps the class aligned without surprises.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _DueDateField(
            dueAt: _dueAt,
            enabled: !_submitting,
            onToggle: (checked) {
              setState(() {
                _validationError = null;
                _dueAt = checked == true
                    ? manilaEndOfDayUtc(
                        _manilaCivilDateNow().add(const Duration(days: 7)),
                      )
                    : null;
              });
            },
            onChanged: (value) =>
                setState(() => _dueAt = manilaEndOfDayUtc(value)),
          ),
        ],
        if (_movementLoadError != null && _classroomScoped) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            _movementLoadError!,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        if (_validationError != null) ...[
          const SizedBox(height: AppSpacing.lg),
          InfoBar(
            key: const Key('teacher_assignment_error'),
            title: const Text('Could not create assignment'),
            content: Text(_validationError!),
            severity: InfoBarSeverity.error,
            onClose: () => setState(() => _validationError = null),
          ),
        ],
      ],
    );
  }

  String get _movementTitle =>
      _selectedOfficialMovement?.name ??
      _selectedTeacherCreatedMovement?.title ??
      'Choose a movement';

  String get _movementModeLabel {
    final custom = _selectedTeacherCreatedMovement;
    if (_selectedOfficialMovement != null) {
      return 'Official ELIXR guided assessment';
    }
    if (custom != null) return 'Teacher reviewed · No automatic ELIXR score';
    return 'Choose an assignable movement.';
  }

  Widget _classroomMovementPicker(BuildContext context) {
    if (_origin == _AssignmentOriginSelection.official) {
      return _MovementChoiceList(
        key: const Key('teacher_assignment_movement'),
        children: [
          for (final movement in _enabledOfficialMovements)
            _MovementChoiceCard(
              key: Key('teacher_assignment_official_${movement.name}'),
              title: movement.name,
              metadata:
                  '${movement.difficulty} · ${movement.supportedProps.map((prop) => prop.displayLabel).join(', ')}',
              description: movement.description,
              movementName: movement.name,
              selected: _selectedOfficialMovement?.name == movement.name,
              enabled: !_submitting,
              onPressed: () => _onOfficialMovementChanged(movement.name),
            ),
        ],
      );
    }

    if (_loadingTeacherMovements) {
      return _teacherMovementLoadingState(context);
    }
    if (_teacherMovements.isEmpty) {
      return _firstTeacherMovementState(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MovementChoiceList(
          key: const Key('teacher_assignment_movement'),
          children: [
            for (final movement in _teacherMovements)
              _MovementChoiceCard(
                key: Key('teacher_assignment_custom_${movement.id}'),
                title: movement.title,
                metadata: _teacherMovementMetadata(movement),
                description: _teacherMovementDescription(movement),
                movementName: movement.title,
                selected: _selectedTeacherCreatedMovement?.id == movement.id,
                enabled: !_submitting,
                isTeacherCreated: true,
                onPressed: () => _onTeacherMovementChanged(movement.id),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: Button(
            key: const Key('teacher_assignment_create_movement'),
            onPressed: _submitting || _creatingTeacherMovement
                ? null
                : _showCreateTeacherMovement,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.add, size: 14),
                SizedBox(width: 6),
                Text('Create movement'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _teacherMovementMetadata(TeacherMovement movement) {
    final spec = _teacherMovementRevisions[movement.id]?.spec;
    if (spec is TeacherReviewedMovementSpec) {
      return 'Teacher reviewed · ${spec.requiredProp.displayLabel}';
    }
    return 'Teacher reviewed';
  }

  String _teacherMovementDescription(TeacherMovement movement) {
    final spec = _teacherMovementRevisions[movement.id]?.spec;
    if (spec is TeacherReviewedMovementSpec) return spec.instructions;
    return 'Trainees submit a recording for your review.';
  }

  Widget _teacherMovementLoadingState(BuildContext context) {
    return Container(
      key: const Key('teacher_assignment_movement_loading'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: ProgressRing()),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Checking your movements…',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }

  Widget _firstTeacherMovementState(BuildContext context) {
    final accent = context.elixColors.brandPrimary;
    return Container(
      key: const Key('teacher_assignment_empty_movement_state'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.10),
          context.elixCardSurface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(FluentIcons.add, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Create your first movement',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add a teacher-reviewed movement, then assign it to this class.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Button(
            key: const Key('teacher_assignment_create_movement'),
            onPressed: _submitting || _creatingTeacherMovement
                ? null
                : _showCreateTeacherMovement,
            child: const Text('Create movement'),
          ),
        ],
      ),
    );
  }

  void _onOriginChanged(_AssignmentOriginSelection? value) {
    if (value == null) return;
    setState(() {
      _origin = value;
      _validationError = null;
      if (value == _AssignmentOriginSelection.official) {
        _selectedTeacherCreatedMovement = null;
        _selectedOfficialMovement ??= _enabledOfficialMovements.firstOrNull;
      } else {
        _selectedOfficialMovement = null;
        _selectedTeacherCreatedMovement ??= _teacherMovements.firstOrNull;
      }
    });
  }

  void _onGroupChanged(String? value) {
    if (value == null) return;
    for (final group in _activeGroups) {
      if (group.id == value) {
        setState(() {
          _selectedGroup = group;
          _validationError = null;
        });
        return;
      }
    }
  }

  void _onOfficialMovementChanged(String? value) {
    if (value == null) return;
    for (final movement in _enabledOfficialMovements) {
      if (movement.name == value) {
        setState(() {
          _selectedOfficialMovement = movement;
          _validationError = null;
        });
        return;
      }
    }
  }

  void _onTeacherMovementChanged(String? value) {
    if (value == null) return;
    for (final movement in _teacherMovements) {
      if (movement.id == value) {
        setState(() {
          _selectedTeacherCreatedMovement = movement;
          _validationError = null;
        });
        return;
      }
    }
  }

  Future<void> _showCreateTeacherMovement() async {
    if (_submitting || _creatingTeacherMovement) return;
    if (widget.movementRepository == null) {
      setState(
        () => _validationError =
            'Teacher-created movements are unavailable right now.',
      );
      return;
    }

    setState(() {
      _creatingTeacherMovement = true;
      _validationError = null;
    });

    TeacherMovement? created;
    String? creationError;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => TeacherMovementBuilderDialog(
          onCreateTeacherReviewed:
              ({
                required title,
                required instructions,
                required requiredProp,
                safetyGuidance,
              }) async {
                try {
                  created = await widget.creationService
                      .createTeacherReviewedMovement(
                        title: title,
                        instructions: instructions,
                        requiredProp: requiredProp,
                        safetyGuidance: safetyGuidance,
                      );
                } on ClassroomException catch (error) {
                  creationError =
                      error.message ?? 'That movement could not be created.';
                } catch (_) {
                  creationError = 'That movement could not be created.';
                }
              },
        ),
      );
      if (!mounted) return;
      if (creationError != null) {
        setState(() => _validationError = creationError);
        return;
      }
      final movement = created;
      if (movement == null) return;
      await _selectCreatedTeacherMovement(movement);
    } finally {
      if (mounted) {
        setState(() => _creatingTeacherMovement = false);
      }
    }
  }

  Future<void> _selectCreatedTeacherMovement(TeacherMovement movement) async {
    final repository = widget.movementRepository;
    if (repository == null) return;
    TeacherMovementRevision? revision;
    try {
      revision = await repository.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _validationError =
              'The movement was created, but its assignment details could not '
              'be loaded. Try selecting it again.',
        );
      }
      return;
    }
    if (!mounted) return;
    if (revision == null || !_isAssignableTeacherRevision(revision)) {
      setState(
        () => _validationError =
            'The new movement is not ready to be assigned yet.',
      );
      return;
    }
    final loadedRevision = revision;
    setState(() {
      _teacherMovements = [
        for (final item in _teacherMovements)
          if (item.id != movement.id) item,
        movement,
      ];
      _teacherMovementRevisions = {
        ..._teacherMovementRevisions,
        movement.id: loadedRevision,
      };
      _origin = _AssignmentOriginSelection.teacherCreated;
      _selectedOfficialMovement = null;
      _selectedTeacherCreatedMovement = movement;
      _movementLoadError = null;
      _validationError = null;
    });
  }

  String? _formValidationError() {
    if (_selectedGroup?.isActive != true) {
      return 'Choose an active classroom.';
    }
    if (_selectedOfficialMovement == null && !_hasValidTeacherMovement) {
      if (_isTeacherCreated && _loadingTeacherMovements) {
        return 'Wait for the assignable movements to finish loading.';
      }
      if (_isTeacherCreated && _movementLoadError != null) {
        return _movementLoadError;
      }
      return 'Choose a movement.';
    }
    if (_isTeacherCreated && !_hasValidMaxScore) {
      return 'Enter a maximum score from 1 to 100.';
    }
    return null;
  }

  Future<void> _submit(BuildContext pageContext) async {
    if (_submitting) return;
    final validationError = _formValidationError();
    if (validationError != null) {
      setState(() => _validationError = validationError);
      return;
    }
    final group = _selectedGroup;
    if (group == null) return;

    setState(() {
      _submitting = true;
      _validationError = null;
    });
    try {
      await widget.creationService.create(
        group: group,
        officialMovement: _selectedOfficialMovement,
        teacherCreatedMovement: _isTeacherCreated
            ? _selectedTeacherCreatedMovement
            : null,
        maxScore: int.tryParse(_maxScoreController.text.trim()) ?? 100,
        dueAt: _dueAt,
      );
      if (pageContext.mounted) Navigator.pop(pageContext, true);
    } on ClassroomException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationError =
            error.message ?? 'That assignment could not be created.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationError = 'That assignment could not be created.';
      });
    }
  }
}

class _ComposerSurface extends StatelessWidget {
  const _ComposerSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.elixColors.borderSubtle,
          width: highContrast ? 2 : 1,
        ),
        boxShadow: highContrast
            ? const []
            : [
                BoxShadow(
                  color: const Color(
                    0xFF000000,
                  ).withValues(alpha: isDark ? 0.22 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _ComposerHeroCard extends StatelessWidget {
  const _ComposerHeroCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final base = context.elixCardSurface;
    final secondary = context.elixColors.brandSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: highContrast ? base : null,
        gradient: highContrast
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: isDark ? 0.2 : 0.1),
                    base,
                  ),
                  Color.alphaBlend(
                    secondary.withValues(alpha: isDark ? 0.1 : 0.05),
                    base,
                  ),
                ],
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : accent.withValues(alpha: isDark ? 0.34 : 0.22),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highContrast
                  ? context.elixCardSurface
                  : accent.withValues(alpha: isDark ? 0.2 : 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: AppTheme.eyebrow(color: accent)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  style: AppTheme.pageTitle(
                    context,
                    color: context.elixTextPrimary,
                  ).copyWith(fontSize: 26, height: 1.15),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  description,
                  style: AppTheme.supporting(color: context.elixTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerSectionHeading extends StatelessWidget {
  const _ComposerSectionHeading({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.brandPrimary;
    final highContrast = context.isHighContrast;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highContrast
                ? context.elixCardSurface
                : accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
            border: highContrast
                ? Border.all(color: context.elixBorder, width: 2)
                : null,
          ),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: AppTheme.eyebrow(color: accent)),
              const SizedBox(height: 2),
              Text(
                title,
                style: AppTheme.cardTitle(color: context.elixTextPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTheme.supporting(color: context.elixTextSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovementSourceSelector extends StatelessWidget {
  const _MovementSourceSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final _AssignmentOriginSelection selected;
  final bool enabled;
  final ValueChanged<_AssignmentOriginSelection?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('teacher_assignment_source'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Movement library',
          style: AppTheme.label(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ToggleButton(
                key: const Key('teacher_assignment_source_official'),
                checked: selected == _AssignmentOriginSelection.official,
                onChanged: enabled
                    ? (_) => onChanged(_AssignmentOriginSelection.official)
                    : null,
                child: const Text('Official ELIXR'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ToggleButton(
                key: const Key('teacher_assignment_source_mine'),
                checked: selected == _AssignmentOriginSelection.teacherCreated,
                onChanged: enabled
                    ? (_) =>
                          onChanged(_AssignmentOriginSelection.teacherCreated)
                    : null,
                child: const Text('My Movements'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          selected == _AssignmentOriginSelection.official
              ? 'Official movements use ELIXR-guided assessment.'
              : 'Your reusable movements are reviewed by you.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _MovementChoiceList extends StatelessWidget {
  const _MovementChoiceList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a movement',
          style: AppTheme.label(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680 ? 2 : 1;
            final itemWidth = columns == 2
                ? (constraints.maxWidth - AppSpacing.sm) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final child in children)
                  SizedBox(width: itemWidth, child: child),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MovementChoiceCard extends StatelessWidget {
  const _MovementChoiceCard({
    super.key,
    required this.title,
    required this.metadata,
    required this.description,
    required this.movementName,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.isTeacherCreated = false,
  });

  final String title;
  final String metadata;
  final String description;
  final String movementName;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final bool isTeacherCreated;

  @override
  Widget build(BuildContext context) {
    final accent = isTeacherCreated
        ? context.elixColors.brandSecondary
        : context.elixColors.brandPrimary;
    final highContrast = context.isHighContrast;
    return Semantics(
      selected: selected,
      button: true,
      label: '$title, $metadata',
      child: Button(
        onPressed: enabled ? onPressed : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected && !highContrast
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : context.elixColors.borderSubtle,
              width: selected || highContrast ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: MovementImage(movementName: movementName, size: 56),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body.copyWith(
                        color: context.elixTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected
                    ? FluentIcons.completed_solid
                    : FluentIcons.circle_ring,
                size: 18,
                color: selected ? accent : context.elixTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerField extends StatelessWidget {
  const _ComposerField({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTheme.label(color: context.elixTextPrimary)),
        const SizedBox(height: AppSpacing.sm),
        child,
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _ComposerReadOnlyField extends StatelessWidget {
  const _ComposerReadOnlyField({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTheme.label(color: context.elixTextPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: highContrast
                ? context.elixCardSurface
                : context.elixColors.interactiveSelected.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: highContrast
                  ? context.elixBorder
                  : context.elixColors.brandPrimary.withValues(alpha: 0.22),
              width: highContrast ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.elixColors.brandPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElixPill(
                text: 'LOCKED',
                color: context.elixColors.brandPrimary,
                compact: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _MovementIdentityCard extends StatelessWidget {
  const _MovementIdentityCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isTeacherCreated,
  });

  final String title;
  final String subtitle;
  final bool isTeacherCreated;

  @override
  Widget build(BuildContext context) {
    final accent = isTeacherCreated
        ? context.elixColors.brandSecondary
        : context.elixColors.brandPrimary;
    final highContrast = context.isHighContrast;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : accent.withValues(alpha: 0.24),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isTeacherCreated ? FluentIcons.edit : FluentIcons.shield,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          ElixPill(
            text: isTeacherCreated ? 'REVIEWED' : 'OFFICIAL',
            color: accent,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _AutomaticScoringCard extends StatelessWidget {
  const _AutomaticScoringCard();

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.success;
    final highContrast = context.isHighContrast;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: highContrast
              ? context.elixBorder
              : accent.withValues(alpha: 0.24),
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.completed_solid, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic ELIXR scoring',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Every trainee receives immediate guided feedback as they practice.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DueDateField extends StatelessWidget {
  const _DueDateField({
    required this.dueAt,
    required this.enabled,
    required this.onToggle,
    required this.onChanged,
  });

  final DateTime? dueAt;
  final bool enabled;
  final ValueChanged<bool?> onToggle;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: highContrast
                ? context.elixCardSurface
                : context.elixColors.interactiveHover,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.elixColors.borderSubtle,
              width: highContrast ? 2 : 1,
            ),
          ),
          child: Checkbox(
            key: const Key('teacher_assignment_due_date_toggle'),
            checked: dueAt != null,
            content: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a due date (optional)'),
                SizedBox(height: 2),
                Text('Default is one week from today.'),
              ],
            ),
            onChanged: enabled ? onToggle : null,
          ),
        ),
        if (dueAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DatePicker(
              key: const Key('teacher_assignment_due_date'),
              selected: _manilaCivilDate(dueAt!),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _AssignmentSummaryCard extends StatelessWidget {
  const _AssignmentSummaryCard({
    super.key,
    required this.group,
    required this.movementTitle,
    required this.movementModeLabel,
    required this.isTeacherCreated,
    required this.dueAt,
    required this.canSubmit,
    required this.isSubmitting,
    required this.maximumScore,
    required this.onSubmit,
  });

  final ElixrGroup? group;
  final String movementTitle;
  final String movementModeLabel;
  final bool isTeacherCreated;
  final DateTime? dueAt;
  final bool canSubmit;
  final bool isSubmitting;
  final int? maximumScore;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.brandSecondary;
    final highContrast = context.isHighContrast;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.elixColors.borderSubtle,
          width: highContrast ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: highContrast
                  ? context.elixCardSurface
                  : accent.withValues(alpha: 0.11),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(21),
              ),
            ),
            child: Row(
              children: [
                Icon(FluentIcons.preview, size: 19, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Assignment summary',
                    style: AppTheme.cardTitle(color: context.elixTextPrimary),
                  ),
                ),
                ElixPill(
                  text: canSubmit ? 'READY' : 'DRAFT',
                  color: canSubmit ? context.elixColors.success : accent,
                  compact: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryItem(
                  icon: FluentIcons.people,
                  label: 'Assigned to',
                  value: group?.name ?? 'Choose a class',
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryItem(
                  icon: FluentIcons.learning_tools,
                  label: 'Movement',
                  value: movementTitle,
                  detail: movementModeLabel,
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryItem(
                  icon: FluentIcons.calculator,
                  label: 'Scoring',
                  value: isTeacherCreated
                      ? maximumScore == null
                            ? 'Set a maximum score'
                            : 'Up to $maximumScore points'
                      : 'Automatic ELIXR scoring',
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryItem(
                  icon: FluentIcons.calendar,
                  label: 'Due date',
                  value: dueAt == null
                      ? 'No due date'
                      : _formatSummaryDate(dueAt!),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: highContrast
                        ? context.elixCardSurface
                        : context.elixColors.interactiveHover,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        canSubmit ? FluentIcons.check_mark : FluentIcons.info,
                        size: 16,
                        color: canSubmit
                            ? context.elixColors.success
                            : context.elixTextSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          canSubmit
                              ? 'Everything looks good. You can publish this assignment.'
                              : 'Complete the assignment details to continue.',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ElixPrimaryButton(
                  key: const Key('teacher_assignment_create'),
                  label: 'Publish assignment',
                  icon: FluentIcons.send,
                  isLoading: isSubmitting,
                  onPressed: onSubmit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSummaryDate(DateTime dueAt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final manila = dueAt.toUtc().add(const Duration(hours: 8));
    return '${months[manila.month - 1]} ${manila.day}, ${manila.year}';
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.elixColors.brandSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTheme.eyebrow(color: context.elixTextSecondary),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: AppTheme.body.copyWith(
                  color: context.elixTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

DateTime _manilaCivilDateNow() {
  final manila = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(manila.year, manila.month, manila.day);
}

DateTime _manilaCivilDate(DateTime utcValue) {
  final manila = utcValue.toUtc().add(const Duration(hours: 8));
  return DateTime(manila.year, manila.month, manila.day);
}
