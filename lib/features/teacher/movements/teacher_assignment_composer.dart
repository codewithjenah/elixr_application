import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
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
import '../../../data/models/assignment_attempt_policy.dart';
import '../../../data/models/assignment_submission_limits.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/teacher_activity_assessment.dart';
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
    required this.groupRepository,
    this.movementRepository,
    this.ensureTeacherAuthorization,
  });

  final String teacherId;
  final String teacherDisplayName;
  final ClassroomAssignmentRepository assignmentRepository;
  final GroupRepository groupRepository;
  final TeacherMovementRepository? movementRepository;
  final Future<bool> Function()? ensureTeacherAuthorization;

  /// Creates either an Official ELIXR or Teacher-created assignment.
  ///
  /// Keeping the origin selection and revision lookup here means both
  /// composer entry points produce the same repository payload and enforce
  /// the same current-revision semantics.
  Future<GroupAssignment> create({
    required ElixrGroup group,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
    Movement? officialMovement,
    TeacherMovement? teacherCreatedMovement,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? topic,
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
    if (!audience.isEntireClass) {
      final members = await groupRepository
          .watchGroupMemberships(
            groupId: group.id,
            teacherId: teacherId,
            status: GroupMembershipStatus.approved,
          )
          .first;
      ensureAssignmentAudienceMatchesRoster(
        audience: audience,
        group: group,
        memberships: members,
      );
    }

    final official = officialMovement;
    if (official != null) {
      final normalizedTopic = topic?.trim();
      if (normalizedTopic == null || normalizedTopic.isEmpty) {
        return assignmentRepository.createOfficialAssignment(
          teacherId: teacherId,
          teacherDisplayName: teacherDisplayName,
          group: group,
          officialMovementName: official.name,
          dueAt: dueAt,
          status: status,
          publishAt: publishAt,
          displayInstructions: official.description,
          attemptPolicy: attemptPolicy,
          audience: audience,
        );
      }
      return assignmentRepository.createOfficialAssignmentWithTopic(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        officialMovementName: official.name,
        dueAt: dueAt,
        status: status,
        publishAt: publishAt,
        displayInstructions: official.description,
        topic: normalizedTopic,
        attemptPolicy: attemptPolicy,
        audience: audience,
      );
    }

    final selectedCustom = teacherCreatedMovement!;
    final movementRepository = this.movementRepository;
    if (movementRepository == null) {
      throw const ClassroomException(
        ClassroomError.notFound,
        'Teacher Activity data is unavailable right now.',
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
    final normalizedTopic = topic?.trim();
    if (normalizedTopic == null || normalizedTopic.isEmpty) {
      return assignmentRepository.createTeacherCreatedAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        movement: custom,
        revision: revision,
        maxScore: maxScore,
        activityAssessment: activityAssessment,
        attemptPolicy: attemptPolicy,
        displayTitle: displayTitle,
        displayInstructions: displayInstructions,
        displaySafetyGuidance: displaySafetyGuidance,
        dueAt: dueAt,
        status: status,
        publishAt: publishAt,
        audience: audience,
      );
    }
    return assignmentRepository.createTeacherCreatedAssignmentWithTopic(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: custom,
      revision: revision,
      maxScore: maxScore,
      activityAssessment: activityAssessment,
      attemptPolicy: attemptPolicy,
      displayTitle: displayTitle,
      displayInstructions: displayInstructions,
      displaySafetyGuidance: displaySafetyGuidance,
      dueAt: dueAt,
      status: status,
      publishAt: publishAt,
      topic: normalizedTopic,
      audience: audience,
    );
  }

  Future<TeacherMovement> createTeacherReviewedMovement({
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final movementRepository = this.movementRepository;
    if (movementRepository == null) {
      throw const ClassroomException(
        ClassroomError.notFound,
        'Teacher Activity data is unavailable right now.',
      );
    }
    await _ensureTeacherAuthorization();
    return movementRepository.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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
  required GroupRepository groupRepository,
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
        groupRepository: groupRepository,
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
            groupRepository: groupRepository,
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
    required this.groupRepository,
    this.lockedGroup,
    this.officialMovement,
    this.teacherCreatedMovement,
  });

  final String teacherId;
  final String teacherDisplayName;
  final List<ElixrGroup> groups;
  final TeacherMovementRepository? movementRepository;
  final TeacherAssignmentCreationService creationService;
  final GroupRepository groupRepository;
  final ElixrGroup? lockedGroup;
  final Movement? officialMovement;
  final TeacherMovement? teacherCreatedMovement;

  @override
  State<TeacherAssignmentComposer> createState() =>
      _TeacherAssignmentComposerState();
}

enum _AssignmentOriginSelection { official, teacherCreated }

enum _PublicationAction { draft, publish, schedule }

extension on AssignmentAudienceType {
  bool get isTargeted => this != AssignmentAudienceType.entireClass;
}

class _TeacherAssignmentComposerState extends State<TeacherAssignmentComposer> {
  late final bool _classroomScoped;
  late final TextEditingController _maxScoreController;
  late final TextEditingController _assignmentTitleController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _safetyGuidanceController;
  late final TextEditingController _topicController;
  late final TextEditingController _rosterSearchController;
  late ElixrGroup? _selectedGroup;
  late Movement? _selectedOfficialMovement;
  late TeacherMovement? _selectedTeacherCreatedMovement;
  late _AssignmentOriginSelection _origin;

  DateTime? _dueAt;
  DateTime _publicationDate = _manilaCivilDateNow().add(
    const Duration(days: 1),
  );
  int _publicationHour = 9;
  int _publicationMinute = 0;
  bool _submitting = false;
  bool _creatingTeacherMovement = false;
  bool _loadingTeacherMovements = false;
  String? _movementLoadError;
  String? _validationError;
  List<TeacherMovement> _teacherMovements = const [];
  Map<String, TeacherMovementRevision> _teacherMovementRevisions = const {};
  StreamSubscription<List<TeacherMovement>>? _movementSubscription;
  StreamSubscription<List<GroupMembership>>? _rosterSubscription;
  int _movementLoadToken = 0;
  int _rosterLoadToken = 0;
  AssignmentAudienceType _audienceType = AssignmentAudienceType.entireClass;
  Set<String> _targetTraineeIds = const {};
  List<GroupMembership> _eligibleTrainees = const [];
  bool _loadingRoster = false;
  String? _rosterLoadError;
  bool _customizeActivity = false;
  ActivityHandRequirement _readinessHands = ActivityHandRequirement.none;
  ActivityBodyRequirement _readinessBody = ActivityBodyRequirement.none;
  TeacherActivityRubricTemplate _rubricTemplate =
      TeacherActivityRubricTemplate.standardTechnique;
  AssignmentAttemptPolicy _attemptPolicy =
      AssignmentAttemptPolicy.legacyDefault;
  int _recordingDurationSeconds =
      TeacherActivityAssessmentContract.defaultRecordingDurationSeconds;
  TeacherActivityVideoMetadata? _demonstrationVideo;
  List<_CustomCriterionDraft> _customCriteria = [];

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

  TeacherReviewedMovementSpec? get _selectedActivitySpec {
    final movement = _selectedTeacherCreatedMovement;
    final revision = movement == null
        ? null
        : _teacherMovementRevisions[movement.id];
    final spec = revision?.spec;
    return spec is TeacherReviewedMovementSpec ? spec : null;
  }

  bool get _hasValidMaxScore {
    if (!_isTeacherCreated) return true;
    if (!_customizeActivity) return _selectedActivitySpec != null;
    if (_rubricTemplate == TeacherActivityRubricTemplate.custom) return true;
    final value = int.tryParse(_maxScoreController.text.trim());
    return value != null && value >= 1 && value <= 100;
  }

  int? get _maximumScore => int.tryParse(_maxScoreController.text.trim());

  TeacherActivityRubric? get _activityRubric {
    if (_rubricTemplate != TeacherActivityRubricTemplate.custom) {
      final maximum = _maximumScore;
      if (maximum == null || maximum < 1 || maximum > 100) return null;
      return TeacherActivityRubric.builtIn(_rubricTemplate, maximum);
    }
    final criteria = <TeacherActivityRubricCriterion>[];
    for (var index = 0; index < _customCriteria.length; index++) {
      final draft = _customCriteria[index];
      final label = draft.label.text.trim();
      final description = draft.description.text.trim();
      final points = int.tryParse(draft.maximumPoints.text.trim());
      if (label.isEmpty ||
          label.length > 80 ||
          description.isEmpty ||
          description.length > 500 ||
          points == null ||
          points < 1 ||
          points > 100) {
        return null;
      }
      criteria.add(
        TeacherActivityRubricCriterion(
          id: 'criterion_${index + 1}',
          label: label,
          description: description,
          maximumPoints: points,
        ),
      );
    }
    final rubric = TeacherActivityRubric(
      template: TeacherActivityRubricTemplate.custom,
      maximumScore: criteria.fold<int>(
        0,
        (total, criterion) => total + criterion.maximumPoints,
      ),
      criteria: criteria,
    );
    return rubric.isValid ? rubric : null;
  }

  TeacherActivityAssessmentConfig? get _activityAssessment {
    if (!_isTeacherCreated) return null;
    if (!_customizeActivity) return _selectedActivitySpec?.effectiveAssessment;
    final rubric = _activityRubric;
    if (rubric == null) return null;
    final config = TeacherActivityAssessmentConfig(
      readiness: TeacherActivityReadinessSpec(
        hands: _readinessHands,
        body: _readinessBody,
      ),
      rubric: rubric,
      recordingDurationSeconds: _recordingDurationSeconds,
      demonstrationVideo: _demonstrationVideo,
    );
    return config.isValid ? config : null;
  }

  bool get _hasValidActivityAssessment =>
      !_isTeacherCreated || _activityAssessment != null;

  String? get _activityDetailsValidation {
    if (!_isTeacherCreated) return null;
    if (!_customizeActivity) return null;
    if (TeacherReviewedMovementSpec.validateTitle(
          _assignmentTitleController.text,
        ) !=
        null) {
      return 'Enter an assignment title of 80 characters or fewer.';
    }
    if (TeacherReviewedMovementSpec.validateInstructions(
          _instructionsController.text,
        ) !=
        null) {
      return 'Enter assignment instructions of 2,000 characters or fewer.';
    }
    if (TeacherReviewedMovementSpec.validateSafetyGuidance(
          _safetyGuidanceController.text,
        ) !=
        null) {
      return 'Safety guidance must be 1,000 characters or fewer.';
    }
    return null;
  }

  bool get _hasValidTeacherMovement {
    final movement = _selectedTeacherCreatedMovement;
    if (movement == null || !movement.isActive) return false;
    if (!_classroomScoped) return true;
    final revision = _teacherMovementRevisions[movement.id];
    return revision != null && _isAssignableTeacherRevision(revision);
  }

  bool get _hasValidAudience => switch (_audienceType) {
    AssignmentAudienceType.entireClass => _targetTraineeIds.isEmpty,
    AssignmentAudienceType.selectedStudents => _targetTraineeIds.isNotEmpty,
    AssignmentAudienceType.individualStudent => _targetTraineeIds.length == 1,
  };

  AssignmentAudience get _audience => switch (_audienceType) {
    AssignmentAudienceType.entireClass =>
      const AssignmentAudience.entireClass(),
    AssignmentAudienceType.selectedStudents =>
      AssignmentAudience.selectedStudents(_targetTraineeIds),
    AssignmentAudienceType.individualStudent =>
      AssignmentAudience.individualStudent(_targetTraineeIds),
  };

  bool get _canSubmit =>
      !_submitting &&
      _selectedGroup?.isActive == true &&
      (_selectedOfficialMovement != null || _hasValidTeacherMovement) &&
      (!_classroomScoped || !_isTeacherCreated || !_loadingTeacherMovements) &&
      _hasValidMaxScore &&
      _hasValidActivityAssessment &&
      _activityDetailsValidation == null &&
      _hasValidAudience &&
      (!_audienceType.isTargeted ||
          (!_loadingRoster && _rosterLoadError == null));

  @override
  void initState() {
    super.initState();
    _classroomScoped = !_hasMovementOverride;
    _maxScoreController = TextEditingController(
      text: '${TeacherActivityAssessmentContract.defaultMaximumScore}',
    );
    _assignmentTitleController = TextEditingController(
      text: widget.teacherCreatedMovement?.title ?? '',
    );
    _instructionsController = TextEditingController();
    _safetyGuidanceController = TextEditingController();
    _topicController = TextEditingController();
    _rosterSearchController = TextEditingController();
    _selectedGroup = widget.lockedGroup ?? _firstActiveGroup();
    _selectedOfficialMovement = widget.officialMovement;
    _selectedTeacherCreatedMovement = widget.teacherCreatedMovement;
    _origin = widget.teacherCreatedMovement != null
        ? _AssignmentOriginSelection.teacherCreated
        : _AssignmentOriginSelection.official;
    if (_classroomScoped) {
      _selectedOfficialMovement = _enabledOfficialMovements.firstOrNull;
      _startWatchingTeacherMovements();
    } else {
      unawaited(_prefillActivityDefaultsForSelectedMovement());
    }
  }

  Future<void> _watchRosterForSelectedGroup() async {
    final token = ++_rosterLoadToken;
    await _rosterSubscription?.cancel();
    _rosterSubscription = null;
    final group = _selectedGroup;
    if (!mounted || token != _rosterLoadToken) return;
    setState(() {
      _loadingRoster = group != null;
      _rosterLoadError = null;
      _eligibleTrainees = const [];
      _targetTraineeIds = const {};
      _rosterSearchController.clear();
    });
    if (group == null) return;
    try {
      _rosterSubscription = widget.groupRepository
          .watchApprovedGroupMembers(
            groupId: group.id,
            teacherId: widget.teacherId,
          )
          .listen(
            (members) {
              if (!mounted || token != _rosterLoadToken) return;
              final eligible =
                  [
                    for (final member in members)
                      if (member.groupId == group.id &&
                          member.teacherId == widget.teacherId &&
                          member.hasClassroomAuthorization)
                        member,
                  ]..sort(
                    (a, b) => a.traineeDisplayName.toLowerCase().compareTo(
                      b.traineeDisplayName.toLowerCase(),
                    ),
                  );
              final validIds = eligible
                  .map((member) => member.traineeId)
                  .toSet();
              setState(() {
                _eligibleTrainees = eligible;
                _targetTraineeIds = _targetTraineeIds
                    .where(validIds.contains)
                    .toSet();
                _loadingRoster = false;
                _rosterLoadError = null;
                _validationError = null;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || token != _rosterLoadToken) return;
              setState(() {
                _loadingRoster = false;
                _rosterLoadError = 'Could not load this classroom roster.';
                _targetTraineeIds = const {};
              });
            },
          );
    } catch (_) {
      if (!mounted || token != _rosterLoadToken) return;
      setState(() {
        _loadingRoster = false;
        _rosterLoadError = 'Could not load this classroom roster.';
        _targetTraineeIds = const {};
      });
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
      _movementLoadError = 'Teacher Activities are unavailable right now.';
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
                _movementLoadError = 'Could not load Teacher Activities.';
              });
            },
          );
    } catch (_) {
      _loadingTeacherMovements = false;
      _movementLoadError = 'Could not load Teacher Activities.';
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
        _movementLoadError = 'Could not load Teacher Activities.';
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
    unawaited(_rosterSubscription?.cancel());
    _maxScoreController.dispose();
    _assignmentTitleController.dispose();
    _instructionsController.dispose();
    _safetyGuidanceController.dispose();
    for (final draft in _customCriteria) {
      draft.dispose();
    }
    _topicController.dispose();
    _rosterSearchController.dispose();
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
      audienceLabel: _audienceSummaryLabel,
      readinessLabel: _isTeacherCreated ? _readinessSummaryLabel : null,
      attemptsLabel: _attemptPolicy.displayLabel,
      recordingDurationSeconds: _isTeacherCreated
          ? _recordingDurationSeconds
          : null,
      rubricLabel: _isTeacherCreated ? _rubricTemplate.displayLabel : null,
      onSaveDraft: _canSubmit
          ? () => _submit(context, _PublicationAction.draft)
          : null,
      onPublish: _canSubmit
          ? () => _submit(context, _PublicationAction.publish)
          : null,
      onSchedule: _canSubmit
          ? () => _submit(context, _PublicationAction.schedule)
          : null,
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
          eyebrow: 'CLASSROOM',
          title: 'Where should it go?',
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
          icon: FluentIcons.contact,
          eyebrow: 'AUDIENCE',
          title: 'Who should receive it?',
          description: 'Choose the whole class, a small group, or one trainee.',
        ),
        const SizedBox(height: AppSpacing.lg),
        _AssignmentAudienceSelector(
          selected: _audienceType,
          enabled: !_submitting,
          onChanged: _onAudienceTypeChanged,
        ),
        if (_audienceType.isTargeted) ...[
          const SizedBox(height: AppSpacing.md),
          _buildRosterPicker(context),
        ],
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
        if ((_isTeacherCreated && _hasValidTeacherMovement) ||
            _selectedOfficialMovement != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.clock,
            eyebrow: 'SUBMISSION RULES',
            title: 'Attempt allowance',
            description:
                'Choose how many completed attempts this classroom receives.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _attemptAllowanceField(),
        ],
        if (_isTeacherCreated && _hasValidTeacherMovement) ...[
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.completed,
            eyebrow: 'SELECTED ACTIVITY',
            title: _selectedTeacherCreatedMovement!.title,
            description: _activityInheritanceSummary,
          ),
          const SizedBox(height: AppSpacing.md),
          ToggleSwitch(
            key: const Key('teacher_assignment_customize_activity'),
            checked: _customizeActivity,
            content: const Text('Customize for this assignment'),
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _customizeActivity = value;
                    if (value) _initializeCustomizationFromActivity();
                  }),
          ),
          if (_customizeActivity) ...[
            const SizedBox(height: AppSpacing.xl),
            _ComposerSectionHeading(
              icon: FluentIcons.edit,
              eyebrow: 'ASSIGNMENT DETAILS',
              title: 'Adapt the activity for this class',
              description:
                  'These fields are captured on the Assignment; your reusable Teacher Activity stays unchanged.',
            ),
            const SizedBox(height: AppSpacing.lg),
            _ComposerField(
              label: 'Assignment title',
              hint: 'Required · up to 80 characters',
              child: TextBox(
                key: const Key('teacher_assignment_title'),
                controller: _assignmentTitleController,
                maxLength: TeacherReviewedMovementSpec.titleMaxLength,
                enabled: !_submitting,
                onChanged: (_) => setState(() => _validationError = null),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ComposerField(
              label: 'Instructions',
              hint: 'Required · explain what the trainee should practice.',
              child: TextBox(
                key: const Key('teacher_assignment_instructions'),
                controller: _instructionsController,
                maxLines: 4,
                maxLength: TeacherReviewedMovementSpec.instructionsMaxLength,
                enabled: !_submitting,
                onChanged: (_) => setState(() => _validationError = null),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ComposerField(
              label: 'Safety guidance',
              hint: 'Optional · visible before the trainee starts an attempt.',
              child: TextBox(
                key: const Key('teacher_assignment_safety_guidance'),
                controller: _safetyGuidanceController,
                maxLines: 3,
                maxLength: TeacherReviewedMovementSpec.safetyGuidanceMaxLength,
                enabled: !_submitting,
                onChanged: (_) => setState(() => _validationError = null),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _ComposerSectionHeading(
              icon: FluentIcons.calculator,
              eyebrow: 'ASSESSMENT',
              title: 'Configure this activity assignment',
              description:
                  'These settings override the reusable Teacher Activity defaults for this classroom only.',
            ),
            const SizedBox(height: AppSpacing.lg),
            _activityAssessmentFields(context),
          ],
        ],
        if (!_isTeacherCreated || _hasValidTeacherMovement) ...[
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.tag,
            eyebrow: 'ORGANIZATION',
            title: 'Add a topic',
            description: 'Optional. Topics organize Classwork for this class.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _ComposerField(
            label: 'Topic',
            hint: 'For example: Bottle Basics',
            child: TextBox(
              key: const Key('teacher_assignment_topic'),
              controller: _topicController,
              maxLength: GroupAssignment.maxTopicLength,
              enabled: !_submitting,
              onChanged: (_) => setState(() => _validationError = null),
            ),
          ),
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
          const SizedBox(height: AppSpacing.xl),
          _ComposerSectionHeading(
            icon: FluentIcons.clock,
            eyebrow: 'PUBLICATION',
            title: 'Choose how trainees receive it',
            description:
                'Save a private draft, publish now, or set a Manila date and time.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _PublicationScheduleField(
            date: _publicationDate,
            hour: _publicationHour,
            minute: _publicationMinute,
            enabled: !_submitting,
            onDateChanged: (value) => setState(() => _publicationDate = value),
            onHourChanged: (value) => setState(() => _publicationHour = value),
            onMinuteChanged: (value) =>
                setState(() => _publicationMinute = value),
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

  Widget _activityAssessmentFields(BuildContext context) {
    final maximum = _maximumScore;
    final isPreset = TeacherActivityAssessmentContract.supportedMaximumScores
        .contains(maximum);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_rubricTemplate != TeacherActivityRubricTemplate.custom) ...[
          _ComposerField(
            label: 'Maximum score',
            hint: 'Use a preset or enter a custom maximum from 1 to 100.',
            child: ComboBox<String>(
              key: const Key('teacher_assignment_maximum_preset'),
              value: isPreset ? '$maximum' : 'custom',
              isExpanded: true,
              items: const [
                ComboBoxItem(value: '30', child: Text('30 points')),
                ComboBoxItem(value: '50', child: Text('50 points')),
                ComboBoxItem(value: '100', child: Text('100 points')),
                ComboBoxItem(value: 'custom', child: Text('Custom maximum')),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        if (value != 'custom') _maxScoreController.text = value;
                        _validationError = null;
                      });
                    },
            ),
          ),
          if (!isPreset) ...[
            const SizedBox(height: AppSpacing.sm),
            _ComposerField(
              label: 'Custom maximum score',
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
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        _ComposerField(
          label: 'Readiness requirements',
          hint:
              'Visibility is checked before recording; it does not score technique.',
          child: Column(
            children: [
              _activityOptionPicker<ActivityHandRequirement>(
                key: const Key('teacher_assignment_readiness_hands'),
                value: _readinessHands,
                values: ActivityHandRequirement.values,
                label: (value) => value.displayLabel,
                onChanged: (value) => setState(() => _readinessHands = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              _activityOptionPicker<ActivityBodyRequirement>(
                key: const Key('teacher_assignment_readiness_body'),
                value: _readinessBody,
                values: ActivityBodyRequirement.values,
                label: (value) => value.displayLabel,
                onChanged: (value) => setState(() => _readinessBody = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ComposerField(
          label: 'Recording duration',
          hint: 'The recording automatically stops at the selected limit.',
          child: ComboBox<int>(
            key: const Key('teacher_assignment_recording_duration'),
            value: _recordingDurationSeconds,
            isExpanded: true,
            items: [
              for (final seconds
                  in TeacherActivityAssessmentContract
                      .supportedRecordingDurations)
                ComboBoxItem(value: seconds, child: Text('$seconds seconds')),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _recordingDurationSeconds = value!),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ComposerField(
          label: 'Rubric',
          hint: 'Built-in criteria scale deterministically to the maximum.',
          child: ComboBox<TeacherActivityRubricTemplate>(
            key: const Key('teacher_assignment_rubric_template'),
            value: _rubricTemplate,
            isExpanded: true,
            items: [
              for (final template in TeacherActivityRubricTemplate.values)
                ComboBoxItem(
                  value: template,
                  child: Text(template.displayLabel),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _rubricTemplate = value;
                      if (value == TeacherActivityRubricTemplate.custom &&
                          _customCriteria.isEmpty) {
                        _customCriteria = List.generate(
                          3,
                          (index) => _CustomCriterionDraft(index + 1),
                        );
                      }
                    });
                  },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _rubricPreview(context),
      ],
    );
  }

  Widget _attemptAllowanceField() => _ComposerField(
    label: 'Attempt allowance',
    hint: 'A finite attempt is counted only when recording genuinely starts.',
    child: ComboBox<String>(
      key: const Key('teacher_assignment_attempt_policy'),
      value: _attemptPolicy.isUnlimited
          ? 'unlimited'
          : '${_attemptPolicy.maximumAttempts}',
      isExpanded: true,
      items: const [
        ComboBoxItem(value: '1', child: Text('1 attempt')),
        ComboBoxItem(value: '2', child: Text('2 attempts')),
        ComboBoxItem(value: '3', child: Text('3 attempts')),
        ComboBoxItem(value: 'unlimited', child: Text('Unlimited attempts')),
      ],
      onChanged: _submitting
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _attemptPolicy = value == 'unlimited'
                    ? const AssignmentAttemptPolicy.unlimited()
                    : AssignmentAttemptPolicy.finite(int.parse(value));
              });
            },
    ),
  );

  Widget _activityOptionPicker<T>({
    required Key key,
    required T value,
    required List<T> values,
    required String Function(T value) label,
    required ValueChanged<T> onChanged,
  }) => ComboBox<T>(
    key: key,
    value: value,
    isExpanded: true,
    items: [
      for (final item in values)
        ComboBoxItem(value: item, child: Text(label(item))),
    ],
    onChanged: _submitting
        ? null
        : (item) {
            if (item != null) onChanged(item);
          },
  );

  Widget _rubricPreview(BuildContext context) {
    if (_rubricTemplate == TeacherActivityRubricTemplate.custom) {
      return _customRubricEditor(context);
    }
    final rubric = _activityRubric;
    if (rubric == null) return const SizedBox.shrink();
    return _RubricCriteriaPreview(criteria: rubric.criteria);
  }

  Widget _customRubricEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in _customCriteria.indexed) ...[
        _CustomCriterionEditor(
          key: Key('teacher_assignment_custom_criterion_${entry.$1}'),
          index: entry.$1 + 1,
          draft: entry.$2,
          enabled: !_submitting,
          canRemove: _customCriteria.length > 3,
          onChanged: () => setState(() => _validationError = null),
          onRemove: () => setState(() {
            final removed = _customCriteria.removeAt(entry.$1);
            removed.dispose();
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (_customCriteria.length < 5)
        Button(
          key: const Key('teacher_assignment_add_criterion'),
          onPressed: _submitting
              ? null
              : () => setState(
                  () => _customCriteria.add(
                    _CustomCriterionDraft(_customCriteria.length + 1),
                  ),
                ),
          child: const Text('Add criterion'),
        ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Total: ${_customCriteria.fold<int>(0, (total, draft) => total + (int.tryParse(draft.maximumPoints.text.trim()) ?? 0))} points',
        style: AppTheme.label(color: context.elixTextPrimary),
      ),
      if (_activityRubric == null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'Use 3–5 complete criteria whose points total the maximum.',
            style: AppTheme.caption.copyWith(color: context.elixColors.error),
          ),
        ),
    ],
  );

  String get _movementTitle =>
      _selectedOfficialMovement?.name ??
      (_isTeacherCreated && _assignmentTitleController.text.trim().isNotEmpty
          ? _assignmentTitleController.text.trim()
          : _selectedTeacherCreatedMovement?.title) ??
      'Choose a movement';

  String get _readinessSummaryLabel {
    final requirements = <String>[];
    if (_readinessHands != ActivityHandRequirement.none) {
      requirements.add(_readinessHands.displayLabel);
    }
    if (_readinessBody != ActivityBodyRequirement.none) {
      requirements.add(_readinessBody.displayLabel);
    }
    return requirements.isEmpty ? 'Camera only' : requirements.join(' · ');
  }

  String get _activityInheritanceSummary {
    final spec = _selectedActivitySpec;
    final assessment = spec?.effectiveAssessment;
    if (spec == null || assessment == null) return 'Loading Activity settings…';
    final demo = assessment.demonstrationVideo == null
        ? 'no demonstration'
        : 'demonstration attached';
    return '${spec.requiredProp.displayLabel} · '
        '${assessment.readiness.hands.displayLabel} · '
        '${assessment.readiness.body.displayLabel} · '
        '${assessment.rubric.template.displayLabel}, '
        '${assessment.rubric.maximumScore} points · '
        '${assessment.recordingDurationSeconds}s · $demo';
  }

  void _initializeCustomizationFromActivity() {
    final movement = _selectedTeacherCreatedMovement;
    final spec = _selectedActivitySpec;
    if (movement == null || spec == null) return;
    final assessment = spec.effectiveAssessment;
    for (final draft in _customCriteria) {
      draft.dispose();
    }
    _assignmentTitleController.text = movement.title;
    _instructionsController.text = spec.instructions;
    _safetyGuidanceController.text = spec.safetyGuidance ?? '';
    _maxScoreController.text = '${assessment.rubric.maximumScore}';
    _readinessHands = assessment.readiness.hands;
    _readinessBody = assessment.readiness.body;
    _rubricTemplate = assessment.rubric.template;
    _recordingDurationSeconds = assessment.recordingDurationSeconds;
    _demonstrationVideo = assessment.demonstrationVideo;
    _customCriteria =
        assessment.rubric.template == TeacherActivityRubricTemplate.custom
        ? [
            for (final criterion in assessment.rubric.criteria)
              _CustomCriterionDraft.fromCriterion(criterion),
          ]
        : [];
  }

  String get _audienceSummaryLabel {
    switch (_audienceType) {
      case AssignmentAudienceType.entireClass:
        return 'Entire class';
      case AssignmentAudienceType.selectedStudents:
        final count = _targetTraineeIds.length;
        return count == 1 ? '1 selected student' : '$count selected students';
      case AssignmentAudienceType.individualStudent:
        if (_targetTraineeIds.length != 1) return 'Choose one student';
        final id = _targetTraineeIds.single;
        for (final member in _eligibleTrainees) {
          if (member.traineeId == id) return member.traineeDisplayName;
        }
        return '1 student';
    }
  }

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
        _customizeActivity = false;
        _selectedTeacherCreatedMovement = null;
        _selectedOfficialMovement ??= _enabledOfficialMovements.firstOrNull;
      } else {
        _selectedOfficialMovement = null;
        _selectedTeacherCreatedMovement ??= _teacherMovements.firstOrNull;
      }
    });
    if (value == _AssignmentOriginSelection.teacherCreated) {
      unawaited(_prefillActivityDefaultsForSelectedMovement());
    }
  }

  void _onGroupChanged(String? value) {
    if (value == null) return;
    for (final group in _activeGroups) {
      if (group.id == value) {
        setState(() {
          _selectedGroup = group;
          _targetTraineeIds = const {};
          _validationError = null;
        });
        if (_audienceType.isTargeted) {
          unawaited(_watchRosterForSelectedGroup());
        }
        return;
      }
    }
  }

  void _onAudienceTypeChanged(AssignmentAudienceType value) {
    if (_audienceType == value || _submitting) return;
    final shouldLoadRoster =
        value.isTargeted &&
        (_eligibleTrainees.isEmpty || _rosterLoadError != null);
    if (value == AssignmentAudienceType.entireClass) {
      _rosterLoadToken++;
      unawaited(_rosterSubscription?.cancel());
      _rosterSubscription = null;
    }
    setState(() {
      if (value == AssignmentAudienceType.entireClass) {
        _targetTraineeIds = const {};
        _eligibleTrainees = const [];
        _rosterLoadError = null;
        _loadingRoster = false;
        _rosterSearchController.clear();
      } else if (value == AssignmentAudienceType.individualStudent &&
          _targetTraineeIds.length != 1) {
        _targetTraineeIds = const {};
      }
      _audienceType = value;
      _validationError = null;
    });
    if (shouldLoadRoster) unawaited(_watchRosterForSelectedGroup());
  }

  Widget _buildRosterPicker(BuildContext context) {
    if (_loadingRoster) {
      return const _AudienceRosterState(
        key: Key('teacher_assignment_roster_loading'),
        message: 'Loading eligible trainees…',
        loading: true,
      );
    }
    if (_rosterLoadError != null) {
      return _AudienceRosterState(
        key: const Key('teacher_assignment_roster_error'),
        message: _rosterLoadError!,
        actionLabel: 'Retry',
        onAction: _watchRosterForSelectedGroup,
      );
    }
    if (_eligibleTrainees.isEmpty) {
      return const _AudienceRosterState(
        key: Key('teacher_assignment_roster_empty'),
        message: 'No approved trainees are available in this classroom.',
      );
    }
    final query = _rosterSearchController.text.trim().toLowerCase();
    final visible = [
      for (final member in _eligibleTrainees)
        if (query.isEmpty ||
            member.traineeDisplayName.toLowerCase().contains(query))
          member,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextBox(
                key: const Key('teacher_assignment_roster_search'),
                controller: _rosterSearchController,
                enabled: !_submitting,
                placeholder: 'Search trainees',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(FluentIcons.search, size: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${_targetTraineeIds.length} selected',
              key: const Key('teacher_assignment_selected_count'),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(maxHeight: 264),
          decoration: BoxDecoration(
            border: Border.all(color: context.elixBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'No trainees match that search.',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const Key('teacher_assignment_roster'),
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(size: 1),
                  itemBuilder: (context, index) {
                    final member = visible[index];
                    final selected = _targetTraineeIds.contains(
                      member.traineeId,
                    );
                    return _AudienceTraineeRow(
                      member: member,
                      selected: selected,
                      multiple:
                          _audienceType ==
                          AssignmentAudienceType.selectedStudents,
                      enabled: !_submitting,
                      onPressed: () => _toggleTrainee(member.traineeId),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _toggleTrainee(String traineeId) {
    if (_submitting) return;
    setState(() {
      if (_audienceType == AssignmentAudienceType.individualStudent) {
        _targetTraineeIds = {traineeId};
      } else if (_targetTraineeIds.contains(traineeId)) {
        _targetTraineeIds = {..._targetTraineeIds}..remove(traineeId);
      } else {
        _targetTraineeIds = {..._targetTraineeIds, traineeId};
      }
      _validationError = null;
    });
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
          _customizeActivity = false;
          _validationError = null;
        });
        unawaited(_prefillActivityDefaultsForSelectedMovement());
        return;
      }
    }
  }

  Future<void> _showCreateTeacherMovement() async {
    if (_submitting || _creatingTeacherMovement) return;
    if (widget.movementRepository == null) {
      setState(
        () =>
            _validationError = 'Teacher Activities are unavailable right now.',
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
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => TeacherMovementBuilderDialog(
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
            onCreateActivity:
                ({
                  required title,
                  required instructions,
                  required requiredProp,
                  required assessment,
                  safetyGuidance,
                }) async {
                  try {
                    created = await widget.creationService
                        .createTeacherReviewedMovement(
                          title: title,
                          instructions: instructions,
                          requiredProp: requiredProp,
                          safetyGuidance: safetyGuidance,
                          assessment: assessment,
                        );
                  } on ClassroomException catch (error) {
                    creationError =
                        error.message ?? 'That Activity could not be created.';
                  } catch (_) {
                    creationError = 'That Activity could not be created.';
                  }
                },
            onUploadDemonstration: widget.movementRepository == null
                ? null
                : ({required localFile, required duration, required source}) =>
                      widget.movementRepository!.uploadActivityDemonstration(
                        teacherId: widget.teacherId,
                        localFile: localFile,
                        duration: duration,
                        source: source,
                      ),
          ),
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
      _customizeActivity = false;
      _movementLoadError = null;
      _validationError = null;
    });
    await _prefillActivityDefaultsForSelectedMovement();
  }

  Future<void> _prefillActivityDefaultsForSelectedMovement() async {
    final movement = _selectedTeacherCreatedMovement;
    if (movement == null) return;
    final selectedMovementId = movement.id;
    var revision = _teacherMovementRevisions[movement.id];
    final repository = widget.movementRepository;
    if (revision == null && repository != null) {
      try {
        revision = await repository.getRevision(
          movementId: movement.id,
          revisionId: movement.currentRevisionId,
        );
      } catch (_) {
        return;
      }
    }
    if (!mounted ||
        _selectedTeacherCreatedMovement?.id != selectedMovementId ||
        revision?.spec is! TeacherReviewedMovementSpec) {
      return;
    }
    setState(() {
      _customizeActivity = false;
      _attemptPolicy = AssignmentAttemptPolicy.teacherActivityDefault;
      _validationError = null;
    });
  }

  DateTime get _scheduledPublishAt => DateTime.utc(
    _publicationDate.year,
    _publicationDate.month,
    _publicationDate.day,
    _publicationHour - 8,
    _publicationMinute,
  );

  String? _formValidationError([_PublicationAction? action]) {
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
    final activityDetailsValidation = _activityDetailsValidation;
    if (activityDetailsValidation != null) return activityDetailsValidation;
    if (_isTeacherCreated && !_hasValidActivityAssessment) {
      return 'Complete the rubric so its criteria total the assignment maximum.';
    }
    if (_audienceType.isTargeted && _rosterLoadError != null) {
      return _rosterLoadError;
    }
    if (_audienceType == AssignmentAudienceType.selectedStudents &&
        _targetTraineeIds.isEmpty) {
      return 'Select at least one trainee.';
    }
    if (_audienceType == AssignmentAudienceType.individualStudent &&
        _targetTraineeIds.length != 1) {
      return 'Select one trainee.';
    }
    if (action == _PublicationAction.schedule) {
      final publishAt = _scheduledPublishAt;
      if (!publishAt.isAfter(DateTime.now().toUtc())) {
        return 'Choose a future Manila publication date and time.';
      }
      if (_dueAt != null && !_dueAt!.toUtc().isAfter(publishAt)) {
        return 'The due date must be later than the scheduled publication time.';
      }
    }
    return null;
  }

  Future<void> _submit(
    BuildContext pageContext,
    _PublicationAction action,
  ) async {
    if (_submitting) return;
    final validationError = _formValidationError(action);
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
        audience: _audience,
        officialMovement: _selectedOfficialMovement,
        teacherCreatedMovement: _isTeacherCreated
            ? _selectedTeacherCreatedMovement
            : null,
        maxScore:
            _activityAssessment?.rubric.maximumScore ??
            int.tryParse(_maxScoreController.text.trim()) ??
            100,
        activityAssessment: _activityAssessment,
        attemptPolicy: _attemptPolicy,
        displayTitle: _isTeacherCreated && _customizeActivity
            ? _assignmentTitleController.text.trim()
            : null,
        displayInstructions: _isTeacherCreated && _customizeActivity
            ? _instructionsController.text.trim()
            : null,
        displaySafetyGuidance: _isTeacherCreated && _customizeActivity
            ? _safetyGuidanceController.text.trim()
            : null,
        dueAt: _dueAt,
        status: switch (action) {
          _PublicationAction.draft => GroupAssignmentStatus.draft,
          _PublicationAction.publish => GroupAssignmentStatus.active,
          _PublicationAction.schedule => GroupAssignmentStatus.scheduled,
        },
        publishAt: action == _PublicationAction.schedule
            ? _scheduledPublishAt
            : null,
        topic: _topicController.text,
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

class _CustomCriterionDraft {
  _CustomCriterionDraft(int number)
    : label = TextEditingController(text: 'Criterion $number'),
      description = TextEditingController(),
      maximumPoints = TextEditingController();

  _CustomCriterionDraft.fromCriterion(TeacherActivityRubricCriterion value)
    : label = TextEditingController(text: value.label),
      description = TextEditingController(text: value.description),
      maximumPoints = TextEditingController(text: '${value.maximumPoints}');

  final TextEditingController label;
  final TextEditingController description;
  final TextEditingController maximumPoints;

  void dispose() {
    label.dispose();
    description.dispose();
    maximumPoints.dispose();
  }
}

class _RubricCriteriaPreview extends StatelessWidget {
  const _RubricCriteriaPreview({required this.criteria});

  final List<TeacherActivityRubricCriterion> criteria;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('teacher_assignment_rubric_preview'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: context.elixCardSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.elixBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final criterion in criteria) ...[
          Text(
            '${criterion.label} · ${criterion.maximumPoints} pts',
            style: AppTheme.caption.copyWith(
              color: context.elixTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            criterion.description,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    ),
  );
}

class _CustomCriterionEditor extends StatelessWidget {
  const _CustomCriterionEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.enabled,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _CustomCriterionDraft draft;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      border: Border.all(color: context.elixBorder),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Criterion $index', style: AppTheme.cardTitle()),
            ),
            if (canRemove)
              IconButton(
                icon: const Icon(FluentIcons.delete),
                onPressed: enabled ? onRemove : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: Key('teacher_assignment_criterion_${index}_label'),
          controller: draft.label,
          enabled: enabled,
          maxLength: 80,
          placeholder: 'Criterion label',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: Key('teacher_assignment_criterion_${index}_description'),
          controller: draft.description,
          enabled: enabled,
          maxLength: 500,
          maxLines: 2,
          placeholder: 'What should the teacher look for?',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextBox(
          key: Key('teacher_assignment_criterion_${index}_points'),
          controller: draft.maximumPoints,
          enabled: enabled,
          keyboardType: TextInputType.number,
          maxLength: 3,
          placeholder: 'Maximum points',
          onChanged: (_) => onChanged(),
        ),
      ],
    ),
  );
}

class _AssignmentAudienceSelector extends StatelessWidget {
  const _AssignmentAudienceSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final AssignmentAudienceType selected;
  final bool enabled;
  final ValueChanged<AssignmentAudienceType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AudienceChoice(
          key: const Key('teacher_assignment_audience_entire'),
          title: 'Entire class',
          description: 'Every approved trainee in this classroom receives it.',
          checked: selected == AssignmentAudienceType.entireClass,
          enabled: enabled,
          onPressed: () => onChanged(AssignmentAudienceType.entireClass),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AudienceChoice(
          key: const Key('teacher_assignment_audience_selected'),
          title: 'Selected students',
          description: 'Only the trainees you select receive it.',
          checked: selected == AssignmentAudienceType.selectedStudents,
          enabled: enabled,
          onPressed: () => onChanged(AssignmentAudienceType.selectedStudents),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AudienceChoice(
          key: const Key('teacher_assignment_audience_individual'),
          title: 'Individual student',
          description: 'Choose one trainee for focused practice.',
          checked: selected == AssignmentAudienceType.individualStudent,
          enabled: enabled,
          onPressed: () => onChanged(AssignmentAudienceType.individualStudent),
        ),
      ],
    );
  }
}

class _AudienceChoice extends StatelessWidget {
  const _AudienceChoice({
    super.key,
    required this.title,
    required this.description,
    required this.checked,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String description;
  final bool checked;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = context.elixColors.brandPrimary;
    return Semantics(
      button: true,
      selected: checked,
      label: '$title. $description',
      child: HoverButton(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onPressed: enabled ? onPressed : null,
        builder: (context, states) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: checked
                ? accent.withValues(alpha: 0.10)
                : context.elixCardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: checked ? accent : context.elixBorder,
              width: checked ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioButton(
                checked: checked,
                onChanged: enabled ? (_) => onPressed() : null,
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
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
      ),
    );
  }
}

class _AudienceTraineeRow extends StatelessWidget {
  const _AudienceTraineeRow({
    required this.member,
    required this.selected,
    required this.multiple,
    required this.enabled,
    required this.onPressed,
  });

  final GroupMembership member;
  final bool selected;
  final bool multiple;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: member.traineeDisplayName,
      child: HoverButton(
        key: Key('teacher_assignment_trainee_${member.traineeId}'),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onPressed: enabled ? onPressed : null,
        builder: (context, states) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (multiple)
                Checkbox(
                  checked: selected,
                  onChanged: enabled ? (_) => onPressed() : null,
                )
              else
                RadioButton(
                  checked: selected,
                  onChanged: enabled ? (_) => onPressed() : null,
                ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  member.traineeDisplayName,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceRosterState extends StatelessWidget {
  const _AudienceRosterState({
    super.key,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(width: 18, height: 18, child: ProgressRing()),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            Button(
              onPressed: () => unawaited(onAction!()),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
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
                child: const Text('Teacher Activities'),
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
    required this.audienceLabel,
    this.readinessLabel,
    this.attemptsLabel,
    this.recordingDurationSeconds,
    this.rubricLabel,
    required this.onSaveDraft,
    required this.onPublish,
    required this.onSchedule,
  });

  final ElixrGroup? group;
  final String movementTitle;
  final String movementModeLabel;
  final bool isTeacherCreated;
  final DateTime? dueAt;
  final bool canSubmit;
  final bool isSubmitting;
  final int? maximumScore;
  final String audienceLabel;
  final String? readinessLabel;
  final String? attemptsLabel;
  final int? recordingDurationSeconds;
  final String? rubricLabel;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onPublish;
  final VoidCallback? onSchedule;

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
                  label: 'Classroom',
                  value: group?.name ?? 'Choose a class',
                ),
                const SizedBox(height: AppSpacing.lg),
                _SummaryItem(
                  icon: FluentIcons.contact,
                  label: 'Audience',
                  value: audienceLabel,
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
                if (readinessLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryItem(
                    icon: FluentIcons.camera,
                    label: 'Readiness',
                    value: readinessLabel!,
                  ),
                ],
                if (attemptsLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryItem(
                    icon: FluentIcons.repeat_all,
                    label: 'Attempts',
                    value: attemptsLabel!,
                  ),
                ],
                if (recordingDurationSeconds != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryItem(
                    icon: FluentIcons.video,
                    label: 'Recording',
                    value: '$recordingDurationSeconds seconds',
                  ),
                ],
                if (rubricLabel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryItem(
                    icon: FluentIcons.bulleted_list,
                    label: 'Rubric',
                    value: rubricLabel!,
                  ),
                ],
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
                Button(
                  key: const Key('teacher_assignment_save_draft'),
                  onPressed: isSubmitting ? null : onSaveDraft,
                  child: const Text('Save draft'),
                ),
                const SizedBox(height: AppSpacing.sm),
                ElixPrimaryButton(
                  key: const Key('teacher_assignment_publish_now'),
                  label: 'Publish now',
                  icon: FluentIcons.send,
                  isLoading: isSubmitting,
                  onPressed: onPublish,
                ),
                const SizedBox(height: AppSpacing.sm),
                Button(
                  key: const Key('teacher_assignment_schedule'),
                  onPressed: isSubmitting ? null : onSchedule,
                  child: const Text('Schedule'),
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

class _PublicationScheduleField extends StatelessWidget {
  const _PublicationScheduleField({
    required this.date,
    required this.hour,
    required this.minute,
    required this.enabled,
    required this.onDateChanged,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final DateTime date;
  final int hour;
  final int minute;
  final bool enabled;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Schedule time (Manila)', style: AppTheme.body),
      const SizedBox(height: AppSpacing.sm),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DatePicker(
          key: const Key('teacher_assignment_publish_date'),
          selected: date,
          onChanged: enabled ? onDateChanged : null,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          SizedBox(
            width: 130,
            child: ComboBox<int>(
              key: const Key('teacher_assignment_publish_hour'),
              value: hour,
              placeholder: const Text('Hour'),
              items: [
                for (var value = 0; value < 24; value++)
                  ComboBoxItem(
                    value: value,
                    child: Text(value.toString().padLeft(2, '0')),
                  ),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) onHourChanged(value);
                    }
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 130,
            child: ComboBox<int>(
              key: const Key('teacher_assignment_publish_minute'),
              value: minute,
              placeholder: const Text('Minute'),
              items: const [
                ComboBoxItem(value: 0, child: Text('00')),
                ComboBoxItem(value: 15, child: Text('15')),
                ComboBoxItem(value: 30, child: Text('30')),
                ComboBoxItem(value: 45, child: Text('45')),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) onMinuteChanged(value);
                    }
                  : null,
            ),
          ),
        ],
      ),
    ],
  );
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
