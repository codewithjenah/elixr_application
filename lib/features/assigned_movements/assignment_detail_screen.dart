import 'dart:async';
import 'dart:io';

import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/progression/assignment_prop_resolution.dart';
import '../../core/progression/practice_variant.dart';
import '../../core/progression/progression_catalog.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/user_name.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/elixr_video_player.dart';
import '../../core/widgets/movement_image.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/repositories/activity_learning_material_repository.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/teacher_activity_assessment.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/teacher_movement_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import 'assigned_movement_list.dart';
import 'assignment_detail_controller.dart';
import '../activity_learning_materials/activity_learning_materials_panel.dart';
import 'widgets/submission_detail_body.dart';

class AssignmentDetailScreen extends StatefulWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.assignmentId,
    this.controller,
  });

  final String assignmentId;
  final AssignmentDetailController? controller;

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  AssignmentDetailController? _controller;
  late final bool _ownsController;
  String? _selectedAttemptId;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final traineeId = context.read<AuthService>().currentUser?.id;
    if (traineeId == null) return;
    _controller = AssignmentDetailController(
      assignmentId: widget.assignmentId,
      traineeId: traineeId,
      groupRepository: context.read<GroupRepository>(),
      assignmentRepository: context.read<ClassroomAssignmentRepository>(),
      submissionRepository: context.read<AssignmentSubmissionRepository>(),
      publicProfileRepository: _tryPublicProfileRepository(context),
    )..start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      final groupId = _controller?.assignment?.groupId.trim();
      context.go(
        groupId == null || groupId.isEmpty
            ? AppRoutePaths.teacherAccess
            : AppRoutePaths.teacherAccessClassWork(groupId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ElixScaffoldPage(
        content: Center(
          child: ElixStatusPanel(
            isError: true,
            icon: FluentIcons.warning,
            title: 'Sign-in required',
            message: 'Sign in to view this assignment.',
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          padding: EdgeInsets.zero,
          content: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.pageTopInset,
              0,
              AppSpacing.lg,
            ),
            child: _Body(
              controller: controller,
              selectedAttemptId: _selectedAttemptId,
              onSelectAttempt: (id) => setState(() => _selectedAttemptId = id),
              onBack: _goBack,
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.onBack,
    required this.onSelectAttempt,
    this.selectedAttemptId,
  });

  final AssignmentDetailController controller;
  final String? selectedAttemptId;
  final ValueChanged<String> onSelectAttempt;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(
        child: ElixStatusPanel(
          isLoading: true,
          icon: FluentIcons.assign,
          title: 'Loading assignment',
          message: 'Loading assignment details and your work.',
        ),
      );
    }
    if (!controller.authorized) {
      return _Message(
        message: controller.assignment == null
            ? (controller.errorMessage ?? 'This assignment is not available.')
            : 'You need to be accepted into this class before you can open this assignment.',
        onBack: onBack,
        onRetry: controller.errorMessage != null ? controller.retry : null,
      );
    }
    final assignment = controller.assignment;
    if (assignment == null) {
      return _Message(
        message: controller.errorMessage ?? 'This assignment is not available.',
        onBack: onBack,
        onRetry: controller.retry,
      );
    }

    final selected = _selectedAttempt(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final header = _AssignmentHeader(
          assignment: assignment,
          attempts: controller.attempts,
          currentAttempt: selected,
          teacherProfilePictureUrl:
              controller.teacherProfile?.profilePictureUrl,
          teacherDisplayName:
              controller.teacherProfile?.displayName ??
              assignment.teacherDisplayName,
          movementRepository: _tryMovementRepository(context),
          materialRepository: _tryMaterialRepository(context),
        );
        final work = _YourWork(
          controller: controller,
          assignment: assignment,
          selected: selected,
          onSelectAttempt: onSelectAttempt,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              key: const Key('assignment_detail_back'),
              label: 'Classwork',
              tooltip: 'Back to classwork',
              semanticLabel: 'Back to classwork',
              onPressed: onBack,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 12,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(child: header),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          flex: 13,
                          child: SingleChildScrollView(
                            key: const Key('assignment_detail_work_scroll'),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.lg,
                              ),
                              child: work,
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: AppSpacing.lg),
                            work,
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  AssignmentAttempt? _selectedAttempt(AssignmentDetailController controller) {
    if (controller.assignment?.activityAssessment != null) {
      final id = selectedAttemptId;
      if (id != null) {
        for (final attempt in controller.attempts) {
          if (attempt.id == id && !attempt.isAbandonedTeacherReviewDraft) {
            return attempt;
          }
        }
      }
      return controller.latestClipSubmission;
    }
    if (controller.assignment?.isTeacherCreated == true) {
      return controller.currentSubmission ?? controller.latestAttempt;
    }
    final id = selectedAttemptId;
    if (id != null) {
      for (final attempt in controller.attempts) {
        if (attempt.id == id) return attempt;
      }
    }
    return controller.latestClipSubmission ?? controller.latestAttempt;
  }
}

class _AssignmentHeader extends StatelessWidget {
  const _AssignmentHeader({
    required this.assignment,
    required this.attempts,
    required this.currentAttempt,
    this.movementRepository,
    this.materialRepository,
    this.teacherProfilePictureUrl,
    required this.teacherDisplayName,
  });

  final GroupAssignment assignment;
  final List<AssignmentAttempt> attempts;
  final AssignmentAttempt? currentAttempt;
  final TeacherMovementRepository? movementRepository;
  final ActivityLearningMaterialRepository? materialRepository;
  final String? teacherProfilePictureUrl;
  final String teacherDisplayName;

  @override
  Widget build(BuildContext context) {
    final activityAssessment = assignment.activityAssessment;
    final statusLabel = assignedMovementStatusLabel(
      assignment,
      currentAttempt,
      assignment.isTeacherCreated ? currentAttempt : null,
    );
    final statusColor = assignedMovementStatusColor(
      assignment,
      currentAttempt,
      assignment.isTeacherCreated ? currentAttempt : null,
    );
    final dueLabel = assignedMovementDueLabel(assignment);
    final dueTimestamp = assignedMovementDueTimestampLabel(assignment);
    final dueColor = assignedMovementDueColor(context, assignment);
    final instructions = assignment.displayInstructions?.trim();
    final safetyGuidance = assignment.displaySafetyGuidance?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElixPanelCard(
          accent: AppColors.primary,
          showAccentBar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (activityAssessment != null) ...[
                ElixEyebrow(label: 'Teacher activity', color: AppColors.accent),
                const SizedBox(height: AppSpacing.xs),
              ],
              ElixEditorialHeader(
                heading: assignment.displayTitle,
                variant: ElixEditorialHeaderVariant.compact,
                subtitle: activityAssessment == null
                    ? 'Assignment details and next steps'
                    : 'A guided recording for your Teacher to review',
                leading: activityAssessment == null
                    ? null
                    : const _AccentIcon(icon: FluentIcons.task_list),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                label:
                    'Teacher $teacherDisplayName, class ${assignment.groupName}',
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: ProfileAvatarWidget(
                        key: const Key('assignment_detail_teacher_avatar'),
                        radius: 20,
                        showBorder: false,
                        networkImageUrl: teacherProfilePictureUrl,
                        initials: userInitials(teacherDisplayName),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teacherDisplayName,
                            style: AppTheme.body.copyWith(
                              color: context.elixTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            assignment.groupName,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ElixPill(
                    text: assignment.origin.displayLabel,
                    color: context.elixTextSecondary,
                    compact: true,
                  ),
                  AssignedMovementStatusBadge(
                    icon: assignedMovementStatusIcon(
                      assignment,
                      currentAttempt,
                      assignment.isTeacherCreated ? currentAttempt : null,
                    ),
                    label: 'Status · $statusLabel',
                    color: statusColor,
                  ),
                  ElixPill(text: dueLabel, color: dueColor, compact: true),
                  if (!assignment.isActive)
                    ElixPill(
                      text: 'Archived',
                      color: context.elixTextSecondary,
                      compact: true,
                    ),
                ],
              ),
              if (dueTimestamp != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  dueTimestamp,
                  style: AppTheme.caption.copyWith(
                    color: dueColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (assignment.isOfficial) ...[
                const SizedBox(height: AppSpacing.sm),
                _OfficialAccessNote(assignment: assignment),
              ],
            ],
          ),
        ),
        if (assignment.officialMovementName != null) ...[
          const SizedBox(height: AppSpacing.md),
          _MovementSummaryCard(assignment: assignment),
        ],
        if (instructions != null && instructions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _NarrativeCard(
            icon: FluentIcons.info,
            title: 'Instructions',
            text: instructions,
          ),
        ],
        if (activityAssessment?.demonstrationVideo != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityDemoCard(
            metadata: activityAssessment!.demonstrationVideo!,
            repository: movementRepository,
          ),
        ],
        if (activityAssessment != null) ...[
          const SizedBox(height: AppSpacing.md),
          _TeacherActivityOverview(
            assignment: assignment,
            assessment: activityAssessment,
            attempts: attempts,
          ),
        ],
        if (safetyGuidance != null && safetyGuidance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _NarrativeCard(
            icon: FluentIcons.warning,
            title: 'Safety',
            text: safetyGuidance,
          ),
        ],
        if (materialRepository != null) ...[
          const SizedBox(height: AppSpacing.md),
          ActivityLearningMaterialsTraineeSection(
            assignmentId: assignment.id,
            repository: materialRepository!,
          ),
        ],
      ],
    );
  }
}

class _OfficialAccessNote extends StatelessWidget {
  const _OfficialAccessNote({required this.assignment});

  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final name = assignment.officialMovementName;
    if (name == null) return const SizedBox.shrink();
    final prop = resolvedAllowedPropForOfficialAssignment(
      officialMovementName: name,
      storedAllowedProp: assignment.allowedProp,
    );
    if (prop == null) return const SizedBox.shrink();
    final level = requiredLevelFor(
      PracticeVariant(movementName: name, trainingProp: prop),
    );
    if (level == null) return const SizedBox.shrink();
    return Text(
      'Assignment Access · Normally unlocks at Level $level',
      style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
    );
  }
}

class _MovementSummaryCard extends StatelessWidget {
  const _MovementSummaryCard({required this.assignment});

  final GroupAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final name = assignment.officialMovementName;
    if (name == null || name.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final prop = resolvedAllowedPropForOfficialAssignment(
      officialMovementName: name,
      storedAllowedProp: assignment.allowedProp,
    );
    return ElixPanelCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.isHighContrast
                  ? context.elixCardSurface
                  : context.elixColors.surfaceInteractive,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isHighContrast
                    ? context.elixBorder
                    : context.elixColors.borderSubtle,
                width: context.isHighContrast ? 2 : 1,
              ),
            ),
            child: MovementImage(movementName: name, size: 48),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Movement',
                  style: AppTheme.label(color: context.elixTextSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.cardTitle(color: context.elixTextPrimary),
                ),
                if (prop != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Required prop · ${prop.displayLabel}',
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TeacherMovementRepository? _tryMovementRepository(BuildContext context) {
  try {
    return context.read<TeacherMovementRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

ActivityLearningMaterialRepository? _tryMaterialRepository(
  BuildContext context,
) {
  try {
    return context.read<ActivityLearningMaterialRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

PublicProfileRepository? _tryPublicProfileRepository(BuildContext context) {
  try {
    return context.read<PublicProfileRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

class _ActivityDemoCard extends StatefulWidget {
  const _ActivityDemoCard({required this.metadata, required this.repository});

  final TeacherActivityVideoMetadata metadata;
  final TeacherMovementRepository? repository;

  @override
  State<_ActivityDemoCard> createState() => _ActivityDemoCardState();
}

class _ActivityDemoCardState extends State<_ActivityDemoCard> {
  final ElixrPlaybackSession _playback = ElixrPlaybackSession();
  File? _file;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() => _error = StateError('Demo playback unavailable.'));
      return;
    }
    try {
      final file = await repository.openActivityDemonstration(widget.metadata);
      if (!mounted) {
        await repository.releaseActivityDemonstration(file);
        return;
      }
      setState(() => _file = file);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _release() async {
    await _playback.release();
    final file = _file;
    if (file != null) {
      await widget.repository?.releaseActivityDemonstration(file);
    }
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Teacher demonstration', style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 220,
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'The private demonstration could not be opened.',
                          textAlign: TextAlign.center,
                          style: AppTheme.body.copyWith(color: AppColors.error),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _DetailOutlineButton(
                          label: 'Try again',
                          onPressed: () {
                            setState(() => _error = null);
                            unawaited(_open());
                          },
                        ),
                      ],
                    ),
                  )
                : _file == null
                ? const Center(child: ProgressRing())
                : ElixrVideoPlayer(
                    source: Uri.file(_file!.path),
                    mirrored: false,
                    session: _playback,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TeacherActivityOverview extends StatelessWidget {
  const _TeacherActivityOverview({
    required this.assignment,
    required this.assessment,
    required this.attempts,
  });

  final GroupAssignment assignment;
  final TeacherActivityAssessmentConfig assessment;
  final List<AssignmentAttempt> attempts;

  @override
  Widget build(BuildContext context) {
    final readiness = assessment.readiness;
    final consumed = attempts
        .where((attempt) => attempt.recordingStartedAt != null)
        .length;
    final maximum = assignment.attemptPolicy.maximumAttempts;
    final attemptSummary = assignment.attemptPolicy.isUnlimited
        ? '$consumed used · Unlimited tries'
        : '$consumed used · ${maximum! - consumed < 0 ? 0 : maximum - consumed} tries remaining of $maximum';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          icon: FluentIcons.info,
          title: 'Before you start',
          subtitle: 'Your activity at a glance',
        ),
        const SizedBox(height: AppSpacing.sm),
        _ActivityMetadataGrid(
          children: [
            _ActivityDetail(
              icon: FluentIcons.contact,
              label: 'Teacher',
              value: assignment.teacherDisplayName,
            ),
            _ActivityDetail(
              icon: FluentIcons.people,
              label: 'Class',
              value: assignment.groupName,
            ),
            _ActivityDetail(
              icon: FluentIcons.calendar,
              label: 'Deadline',
              value: [
                assignedMovementDueLabel(assignment),
                ?assignedMovementDueTimestampLabel(assignment),
              ].join(' · '),
            ),
            _ActivityDetail(
              icon: FluentIcons.clock,
              label: 'Recording',
              value: '${assessment.recordingDurationSeconds} seconds',
            ),
            _ActivityDetail(
              icon: FluentIcons.refresh,
              label: 'Tries',
              value: attemptSummary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ElixPanelCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          accent: AppColors.accent,
          showAccentBar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                icon: FluentIcons.camera,
                title: 'Camera readiness',
                subtitle: 'Set up before your recording begins',
              ),
              const SizedBox(height: AppSpacing.sm),
              _ReadinessRow(
                icon: FluentIcons.shopping_cart,
                label: 'Required prop',
                value: assignment.allowedProp?.displayLabel ?? 'Selected prop',
                emphasized: true,
              ),
              _ReadinessRow(
                icon: FluentIcons.touch,
                label: 'Hands',
                value: readiness.hands.displayLabel,
              ),
              _ReadinessRow(
                icon: FluentIcons.camera,
                label: 'Body',
                value: readiness.body.displayLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ElixPanelCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SectionHeading(
                      icon: FluentIcons.completed,
                      title: 'How your teacher will check it',
                      subtitle: assessment.rubric.template.displayLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _RubricTotalScore(
                    maximumScore: assessment.rubric.maximumScore,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (
                var index = 0;
                index < assessment.rubric.criteria.length;
                index++
              )
                _RubricCriterionRow(
                  number: index + 1,
                  criterion: assessment.rubric.criteria[index],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityDetail extends StatelessWidget {
  const _ActivityDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: AppTheme.practiceMetricTileDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.accent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.label(color: context.elixTextSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
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

class _ActivityMetadataGrid extends StatelessWidget {
  const _ActivityMetadataGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 420 ? 2 : 1;
      final itemWidth =
          (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final child in children)
            SizedBox(width: itemWidth, child: child),
        ],
      );
    },
  );
}

class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: context.isHighContrast
          ? context.elixCardSurface
          : context.elixColors.surfaceInteractive,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: context.isHighContrast
            ? context.elixBorder
            : context.elixColors.borderSubtle,
        width: context.isHighContrast ? 2 : 1,
      ),
    ),
    child: Icon(icon, size: 19, color: context.elixColors.brandPrimary),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _AccentIcon(icon: icon),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTheme.cardTitle(color: context.elixTextPrimary),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
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

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: emphasized ? AppColors.accent : context.elixTextSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextPrimary,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RubricCriterionRow extends StatelessWidget {
  const _RubricCriterionRow({required this.number, required this.criterion});
  final int number;
  final TeacherActivityRubricCriterion criterion;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: context.elixBorder.withValues(alpha: 0.55)),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: AppTheme.caption.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                criterion.label,
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                criterion.description,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ElixPill(
          text: '${criterion.maximumPoints} pts',
          color: AppColors.accent,
          compact: true,
        ),
      ],
    ),
  );
}

class _RubricTotalScore extends StatelessWidget {
  const _RubricTotalScore({required this.maximumScore});

  final int maximumScore;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Total score: $maximumScore points',
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: AppTheme.practiceMetricTileDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'TOTAL SCORE',
            style: AppTheme.label(color: context.elixTextSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '$maximumScore pts',
            style: AppTheme.bodySecondary.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => ElixPanelCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(icon: icon, title: title),
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextPrimary,
          ),
        ),
      ],
    ),
  );
}

class _YourWork extends StatelessWidget {
  const _YourWork({
    required this.controller,
    required this.assignment,
    required this.onSelectAttempt,
    this.selected,
  });

  final AssignmentDetailController controller;
  final GroupAssignment assignment;
  final AssignmentAttempt? selected;
  final ValueChanged<String> onSelectAttempt;

  @override
  Widget build(BuildContext context) {
    final isTeacherActivity = assignment.activityAssessment != null;
    // Teacher Activities have a history selector. Keep the submitted-work
    // card aligned with its selected row so a trainee sees the historical
    // score and scoring criteria for that exact submission.
    final current = isTeacherActivity
        ? selected
        : assignment.isTeacherCreated
        ? controller.currentSubmission
        : selected;
    final workflowAttempt = isTeacherActivity
        ? controller.latestActivityWorkflowAttempt
        : current;
    final maximumAttempts = assignment.attemptPolicy.maximumAttempts;
    final consumedAttempts = controller.activityAttempts
        .where((attempt) => attempt.recordingStartedAt != null)
        .length;
    final hasAvailableActivityAttempt =
        maximumAttempts == null || consumedAttempts < maximumAttempts;
    final canStart = canStartAssignedMovement(
      assignment,
      workflowAttempt,
      workflowAttempt,
      activityAttempts: controller.activityAttempts,
    );
    final attemptAssessment =
        current?.activityAssessmentSnapshot ?? assignment.activityAssessment;
    return ElixPanelCard(
      key: const Key('assignment_detail_your_work'),
      variant: ElixPanelVariant.normal,
      accent: AppColors.primary,
      showAccentBar: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _AccentIcon(icon: FluentIcons.document),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Your work', style: AppTheme.sectionTitle(context)),
              ),
              ElixPill(
                text: current == null ? 'Not submitted' : 'Current submission',
                color: current == null
                    ? AppColors.accent
                    : context.elixTextSecondary,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (current == null)
            _EmptyWorkState(
              canStart: canStart,
              noTriesRemaining:
                  isTeacherActivity && !hasAvailableActivityAttempt,
              label: assignedMovementPracticeButtonLabel(
                workflowAttempt,
                assignment: assignment,
              ),
              onStart: () =>
                  context.go(AppRoutePaths.assignedPractice(assignment.id)),
            )
          else
            SubmissionDetailBody(
              key: ValueKey(current.id),
              assignment: assignment,
              attempt: current,
              viewerRole: SubmissionDetailViewerRole.trainee,
              submissionRepository: controller.submissionRepository,
              openLocalPlayback: controller.openLocalPlayback,
              releaseLocalPlayback: controller.releaseLocalPlayback,
            ),
          if (attemptAssessment != null && current != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This recording uses the scoring criteria saved when you started '
              'it (${attemptAssessment.rubric.maximumScore} points total).',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
          if (assignment.isTeacherCreated &&
              !isTeacherActivity &&
              current?.hasAttachedDraftClip == true) ...[
            const SizedBox(height: AppSpacing.md),
            if (controller.turnInErrorMessage != null)
              InfoBar(
                title: const Text('Could not turn in recording'),
                content: Text(controller.turnInErrorMessage!),
                severity: InfoBarSeverity.error,
                onClose: () {},
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isTeacherActivity
                  ? 'Your Activity recording uploaded but was not sent to your Teacher.'
                  : 'Recording attached. Your Teacher cannot see it until you turn it in.',
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  ElixPrimaryButton(
                    label: isTeacherActivity
                        ? 'Retry automatic submission'
                        : 'Turn in',
                    expanded: false,
                    dense: true,
                    isLoading: controller.turnInBusy,
                    onPressed: controller.turnInBusy
                        ? null
                        : isTeacherActivity
                        ? controller.turnIn
                        : () => _confirmTurnIn(
                            context,
                            controller,
                            assignment,
                            current!,
                          ),
                  ),
                  if (!isTeacherActivity)
                    _DetailOutlineButton(
                      label: controller.draftRemovalBusy
                          ? 'Removing…'
                          : 'Remove recording',
                      onPressed: controller.draftRemovalBusy
                          ? null
                          : () => controller.removeAttachedDraft(),
                    ),
                ],
              ),
            ),
          ],
          if (assignment.isTeacherCreated &&
              current?.isDraftClipRemovalPending == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              controller.draftRemovalErrorMessage ??
                  'Removing the attached recording…',
              style: AppTheme.bodySecondary.copyWith(
                color: controller.draftRemovalErrorMessage == null
                    ? context.elixTextSecondary
                    : AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DetailOutlineButton(
              label: 'Retry removal',
              onPressed: controller.draftRemovalBusy
                  ? null
                  : controller.removeAttachedDraft,
            ),
          ],
          if ((!assignment.isTeacherCreated || isTeacherActivity) &&
              controller.attempts
                      .where(
                        (attempt) => !attempt.isAbandonedTeacherReviewDraft,
                      )
                      .length >
                  1) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Work history', style: AppTheme.headingMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final attempt in controller.attempts)
              if (!attempt.isAbandonedTeacherReviewDraft)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _AttemptHistoryRow(
                    assignment: assignment,
                    attempt: attempt,
                    selected: selected?.id == attempt.id,
                    onTap: () => onSelectAttempt(attempt.id),
                  ),
                ),
          ],
          if (assignment.isTeacherCreated &&
              !isTeacherActivity &&
              current?.status == AssignmentAttemptStatus.submitted) ...[
            const SizedBox(height: AppSpacing.md),
            if (controller.unsubmitErrorMessage != null)
              InfoBar(
                title: const Text('Could not withdraw the clip'),
                content: Text(controller.unsubmitErrorMessage!),
                severity: InfoBarSeverity.error,
                onClose: () {},
              ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _DetailOutlineButton(
                label: controller.unsubmitBusy ? 'Working…' : 'Unsubmit',
                onPressed: controller.unsubmitBusy || !controller.canUnsubmit
                    ? null
                    : () => _confirmUnsubmit(context, controller),
              ),
            ),
            if (!controller.canUnsubmit && !controller.unsubmitBusy)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  assignment.isOverdue
                      ? 'Unsubmit is unavailable after the deadline.'
                      : 'This submission can no longer be withdrawn.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
          ],
          if (assignment.isTeacherCreated &&
              !isTeacherActivity &&
              current?.status == AssignmentAttemptStatus.unsubmitting) ...[
            const SizedBox(height: AppSpacing.md),
            if (controller.unsubmitErrorMessage != null)
              InfoBar(
                title: const Text('Clip withdrawal needs a retry'),
                content: Text(controller.unsubmitErrorMessage!),
                severity: InfoBarSeverity.error,
                onClose: () {},
              ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _DetailOutlineButton(
                label: controller.unsubmitBusy
                    ? 'Working…'
                    : 'Retry withdrawal',
                onPressed: controller.unsubmitBusy || !controller.canUnsubmit
                    ? null
                    : () => _confirmUnsubmit(context, controller),
              ),
            ),
          ],
          if (current != null) ...[
            const SizedBox(height: AppSpacing.lg),
            if (canStart)
              ElixPrimaryButton(
                label: assignedMovementPracticeButtonLabel(
                  workflowAttempt,
                  assignment: assignment,
                ),
                expanded: true,
                icon: FluentIcons.play,
                onPressed: () =>
                    context.go(AppRoutePaths.assignedPractice(assignment.id)),
              )
            else if (isTeacherActivity && !hasAvailableActivityAttempt)
              Align(
                alignment: Alignment.centerLeft,
                child: ElixPill(
                  text: 'No tries remaining',
                  color: context.elixTextSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EmptyWorkState extends StatelessWidget {
  const _EmptyWorkState({
    required this.canStart,
    required this.noTriesRemaining,
    required this.label,
    required this.onStart,
  });
  final bool canStart;
  final bool noTriesRemaining;
  final String label;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Not submitted work',
    child: Column(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.isHighContrast
                ? context.elixCardSurface
                : context.elixColors.surfaceInteractive,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.isHighContrast
                  ? context.elixBorder
                  : context.elixColors.borderSubtle,
              width: context.isHighContrast ? 2 : 1,
            ),
          ),
          child: Icon(
            FluentIcons.video,
            size: 22,
            color: context.elixColors.brandPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'You have not submitted work for this assignment yet.',
          textAlign: TextAlign.center,
          style: AppTheme.cardTitle(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Prepare your space, then record an attempt for your teacher to review.',
          textAlign: TextAlign.center,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (canStart)
          ElixPrimaryButton(
            label: label,
            expanded: true,
            icon: FluentIcons.play,
            dense: true,
            onPressed: onStart,
          )
        else if (noTriesRemaining)
          ElixPill(
            text: 'No tries remaining',
            color: context.elixTextSecondary,
          ),
      ],
    ),
  );
}

Future<void> _confirmUnsubmit(
  BuildContext context,
  AssignmentDetailController controller,
) async {
  const title = 'Unsubmit this clip?';
  const message =
      'The submitted clip will be removed and this assignment will return '
      'to in progress. You can record and submit a new clip while the '
      'assignment is still open.';
  final confirmed = await _confirmAssignmentAction(
    context,
    title: title,
    message: message,
    confirmLabel: 'Unsubmit',
  );
  if (confirmed) await controller.unsubmit();
}

Future<void> _confirmTurnIn(
  BuildContext context,
  AssignmentDetailController controller,
  GroupAssignment assignment,
  AssignmentAttempt attempt,
) async {
  final duration = attempt.videoDurationMs == null
      ? 'Recording attached'
      : 'Recording duration ${formatSubmissionDurationMs(attempt.videoDurationMs!)}';
  final confirmed = await _confirmAssignmentAction(
    context,
    title: 'Turn in your work?',
    message:
        '${assignment.displayTitle}\n$duration\n\n'
        'This recording will be submitted to ${assignment.teacherDisplayName} for checking.',
    confirmLabel: 'Turn in',
  );
  if (confirmed) await controller.turnIn();
}

Future<bool> _confirmAssignmentAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final useShad =
      !context.isHighContrast && shad.ShadTheme.maybeOf(context) != null;
  if (!useShad) {
    return await showDialog<bool>(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }
  return await ElixDialog.show<bool>(
        context,
        title: title,
        content: Text(
          message,
          style: AppTheme.body.copyWith(
            fontSize: 14,
            color: context.elixTextSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          Button(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElixPrimaryButton(
            label: confirmLabel,
            expanded: false,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
          ),
        ],
        uniformActionSize: const Size(128, 56),
      ) ??
      false;
}

class _DetailOutlineButton extends StatelessWidget {
  const _DetailOutlineButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return Button(onPressed: onPressed, child: Text(label));
    }
    return shad.ShadButton.outline(
      onPressed: onPressed,
      enabled: onPressed != null,
      child: Text(label),
    );
  }
}

class _AttemptHistoryRow extends StatelessWidget {
  const _AttemptHistoryRow({
    required this.assignment,
    required this.attempt,
    required this.selected,
    required this.onTap,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt attempt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when =
        attempt.submittedAt ?? attempt.completedAt ?? attempt.createdAt;
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        return ElixPanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignedMovementStatusLabel(
                        assignment,
                        attempt,
                        attempt.isTeacherReviewSubmission ? attempt : null,
                      ),
                      style: AppTheme.body,
                    ),
                    if (when != null)
                      Text(
                        formatSubmissionTimestamp(when),
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    if (attempt.supersedesAttemptId != null)
                      Text(
                        'Resubmission',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(FluentIcons.check_mark, size: 16)
              else
                const Icon(FluentIcons.chevron_right, size: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onBack, this.onRetry});

  final String message;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElixStatusPanel(
              message: message,
              isError: true,
              icon: FluentIcons.warning,
              title: 'Assignment unavailable',
              actionLabel: onRetry == null ? null : 'Retry',
              onAction: onRetry,
            ),
            const SizedBox(height: AppSpacing.md),
            ElixBackButton(
              key: const Key('assignment_detail_message_back'),
              label: 'Assigned movements',
              tooltip: 'Back to assigned movements',
              semanticLabel: 'Back to assigned movements',
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}
