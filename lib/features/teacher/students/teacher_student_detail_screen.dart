import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:elixr_core/elixr_core.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../services/auth_service.dart';
import '../../profile/widgets/profile_section_card.dart';
import '../classwork/teacher_classwork_controller.dart';
import '../classwork/teacher_classwork_pane.dart';
import 'teacher_student_detail_controller.dart';
import 'teacher_student_models.dart';

class TeacherStudentDetailScreen extends StatefulWidget {
  const TeacherStudentDetailScreen({
    super.key,
    required this.traineeId,
    this.preferredGroupId,
    this.evidenceRepository,
    this.classworkController,
  });

  final String traineeId;
  final String? preferredGroupId;
  final TeacherEvidenceRepository? evidenceRepository;
  final TeacherClassworkController? classworkController;

  @override
  State<TeacherStudentDetailScreen> createState() =>
      _TeacherStudentDetailScreenState();
}

class _TeacherStudentDetailScreenState
    extends State<TeacherStudentDetailScreen> {
  TeacherStudentDetailController? _controller;
  TeacherClassworkController? _ownedClassworkController;

  TeacherClassworkController? get _classworkController =>
      widget.classworkController ?? _ownedClassworkController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final auth = context.read<AuthService>();
    final userId = auth.currentUser?.id;
    if (userId == null) return;
    _controller = TeacherStudentDetailController(
      groupRepository: context.read(),
      progressRepository: context.read(),
      publicProfileRepository: context.read<PublicProfileRepository>(),
      teacherId: userId,
      traineeId: widget.traineeId,
      preferredGroupId: widget.preferredGroupId,
      evidenceRepository:
          widget.evidenceRepository ?? _maybeEvidenceRepository(context),
    )..start();
    final preferredGroupId = widget.preferredGroupId?.trim();
    if (preferredGroupId != null &&
        preferredGroupId.isNotEmpty &&
        widget.classworkController == null) {
      final assignmentRepository = _maybeRead<ClassroomAssignmentRepository>(
        context,
      );
      if (assignmentRepository != null) {
        _ownedClassworkController = TeacherClassworkController(
          teacherId: userId,
          teacherDisplayName: auth.currentUser!.fullName,
          groupId: preferredGroupId,
          groupRepository: context.read<GroupRepository>(),
          assignmentRepository: assignmentRepository,
          submissionRepository: _maybeRead<AssignmentSubmissionRepository>(
            context,
          ),
          chatRepository: _maybeRead<ChatRepository>(context),
          fixedTraineeId: widget.traineeId,
        )..start();
      }
    }
  }

  TeacherEvidenceRepository? _maybeEvidenceRepository(BuildContext context) {
    try {
      return context.read<TeacherEvidenceRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ownedClassworkController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Student',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Center(child: ProgressRing()),
      );
    }

    final classwork = _classworkController;
    return AnimatedBuilder(
      animation: classwork == null
          ? controller
          : Listenable.merge([controller, classwork]),
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: ElixEditorialPageHeader(
            heading: 'Student details',
            eyebrow: 'TEACHER WORKSPACE',
            variant: ElixEditorialHeaderVariant.compact,
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.contact),
                  label: const Text('View public profile'),
                  onPressed: () {
                    context.push(
                      AppRoutePaths.teacherProfile(controller.traineeId),
                    );
                  },
                ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.chat),
                  label: const Text('Message student'),
                  onPressed:
                      controller.state == TeacherStudentDetailState.unauthorized
                      ? null
                      : () {
                          final location = Uri(
                            path: AppRoutePaths.teacherMessages,
                            queryParameters: {
                              'userId': controller.traineeId,
                              'name': controller.displayName,
                              'role': 'Trainee',
                              if (controller.profileRoot?.profilePictureUrl !=
                                  null)
                                'avatar':
                                    controller.profileRoot!.profilePictureUrl,
                            },
                          ).toString();
                          context.go(location);
                        },
                ),
              ],
            ),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElixBackButton(
                key: const Key('teacher_student_back'),
                label: widget.preferredGroupId == null
                    ? 'Students'
                    : 'Classroom',
                tooltip: widget.preferredGroupId == null
                    ? 'Back to students'
                    : 'Back to classroom',
                semanticLabel: widget.preferredGroupId == null
                    ? 'Back to students'
                    : 'Back to classroom',
                onPressed: () => context.go(
                  widget.preferredGroupId == null
                      ? AppRoutePaths.teacherStudents
                      : AppRoutePaths.teacherGroup(widget.preferredGroupId!),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _StudentIdentity(controller: controller),
              const SizedBox(height: AppSpacing.lg),
              _DetailBody(
                controller: controller,
                classworkController: classwork,
                preferredGroupId: widget.preferredGroupId,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StudentIdentity extends StatelessWidget {
  const _StudentIdentity({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProfileAvatarWidget(
          key: const Key('teacher_student_detail_avatar'),
          radius: 28,
          showBorder: false,
          initials: userInitials(controller.displayName),
          networkImageUrl: controller.profileRoot?.profilePictureUrl,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(controller.displayName, style: AppTheme.headingMedium),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.controller,
    required this.classworkController,
    required this.preferredGroupId,
  });

  final TeacherStudentDetailController controller;
  final TeacherClassworkController? classworkController;
  final String? preferredGroupId;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      TeacherStudentDetailState.loadingClassroom => const Center(
        child: ProgressRing(),
      ),
      TeacherStudentDetailState.unauthorized => _MessagePanel(
        title: 'Not authorized',
        body: preferredGroupId == null
            ? 'This student is not in any of your groups. Classroom membership is required before you can view details.'
            : 'This student is not an approved member of this classroom.',
        icon: FluentIcons.lock_solid,
      ),
      TeacherStudentDetailState.pending => _MembershipPanel(
        controller: controller,
        title: 'Pending approval',
        body:
            'This student has requested to join your classroom. Approve the membership in Groups before coaching or viewing progress.',
      ),
      TeacherStudentDetailState.relationshipRemoved => _MembershipPanel(
        controller: controller,
        title: 'Membership inactive',
        body:
            'This student no longer has an active approved membership in your groups.',
      ),
      TeacherStudentDetailState.connectionRequired => _MessagePanel(
        title: 'Connection required',
        body:
            'Could not verify classroom membership. Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      ),
      TeacherStudentDetailState.error => _MessagePanel(
        title: 'Something went wrong',
        body: 'Practice history could not be loaded.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      ),
      _ => _AuthorizedBody(
        controller: controller,
        classworkController: classworkController,
        preferredGroupId: preferredGroupId,
      ),
    };
  }
}

class _AuthorizedBody extends StatelessWidget {
  const _AuthorizedBody({
    required this.controller,
    required this.classworkController,
    required this.preferredGroupId,
  });

  final TeacherStudentDetailController controller;
  final TeacherClassworkController? classworkController;
  final String? preferredGroupId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.isPrivateProfile) const _PrivateProfileBadge(),
        const SizedBox(height: AppSpacing.md),
        _ClassroomStatus(controller: controller),
        if (preferredGroupId != null && classworkController != null) ...[
          const SizedBox(height: AppSpacing.xl),
          TeacherStudentClassworkSection(controller: classworkController!),
        ],
        const SizedBox(height: AppSpacing.xl),
        _ProgressSection(controller: controller),
      ],
    );
  }
}

class _PrivateProfileBadge extends StatelessWidget {
  const _PrivateProfileBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(FluentIcons.lock_solid, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Private public profile — classroom membership remains visible to you as the assigning Teacher.',
              style: AppTheme.body.copyWith(color: context.elixTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassroomStatus extends StatelessWidget {
  const _ClassroomStatus({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return ProfileSectionCard(
      title: 'Classroom status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Approved member in ${controller.approvedMemberships.length} group(s).',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final membership in controller.approvedMemberships)
                _StatusBadge(
                  label: teacherStudentStatusLabel(membership.status),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.controller});

  final TeacherStudentDetailController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      TeacherStudentDetailState.loadingProgress => const Center(
        child: ProgressRing(),
      ),
      TeacherStudentDetailState.empty => const _MessagePanel(
        title: 'No practice history yet',
        body: 'Shared progress is empty so far.',
      ),
      TeacherStudentDetailState.ready => ProfileSectionCard(
        title: 'Practice progress',
        child: _ProgressReady(controller: controller),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ProgressReady extends StatelessWidget {
  const _ProgressReady({required this.controller});

  final TeacherStudentDetailController controller;
  static final _duration = NumberFormat.decimalPattern();

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null) ...[
          Text(
            'Total practice: ${_duration.format(summary.totalDurationSeconds)} seconds',
            style: AppTheme.body,
          ),
          if (summary.completedMovementNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Completed movements',
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final movementName in summary.completedMovementNames)
                  Tooltip(
                    message: movementName,
                    child: MovementImage(movementName: movementName, size: 48),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        if (controller.sessions.isEmpty)
          Text(
            'No sessions on this page.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          )
        else
          ...controller.sessions.map((session) {
            final scoreLabel = session.isRubricAssessed
                ? '${session.rubric!.total}/12'
                : '${session.legacyScore ?? 0}%';
            return ListTile(
              leading: MovementImage(
                movementName: session.movementName,
                size: 48,
              ),
              title: Text(session.movementName),
              subtitle: Text('${session.difficulty} · $scoreLabel'),
              trailing: session.evidenceAvailable == true
                  ? _SavedImageAction(controller: controller, session: session)
                  : null,
            );
          }),
        if (controller.paginationError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Could not load more sessions.', style: AppTheme.caption),
          Button(
            onPressed: controller.retryLoadMore,
            child: const Text('Retry load more'),
          ),
        ] else if (controller.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Button(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              child: controller.loadingMore
                  ? const ProgressRing()
                  : const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _SavedImageAction extends StatelessWidget {
  const _SavedImageAction({required this.controller, required this.session});

  final TeacherStudentDetailController controller;
  final PublicProfileSession session;

  @override
  Widget build(BuildContext context) {
    final state = controller.evidenceStateFor(session.sessionId);
    return switch (state) {
      TeacherEvidenceState.idle => Button(
        key: Key('teacher_saved_image_${session.sessionId}'),
        onPressed: () => _open(context),
        child: const Text('View saved image'),
      ),
      TeacherEvidenceState.loading => const Button(
        onPressed: null,
        child: ProgressRing(),
      ),
      TeacherEvidenceState.loaded => Button(
        key: Key('teacher_saved_image_${session.sessionId}'),
        onPressed: () {
          final bytes = controller.evidenceFor(session.sessionId);
          if (bytes != null) _showImage(context, bytes);
        },
        child: const Text('View saved image'),
      ),
      TeacherEvidenceState.unavailable => _RetrySavedImageAction(
        message: 'Saved image unavailable',
        onRetry: () => _open(context),
      ),
      TeacherEvidenceState.error => _RetrySavedImageAction(
        message: 'Could not load saved image',
        onRetry: () => _open(context),
      ),
    };
  }

  Future<void> _open(BuildContext context) async {
    await controller.loadEvidence(session);
    if (!context.mounted) return;
    final bytes = controller.evidenceFor(session.sessionId);
    if (bytes != null) _showImage(context, bytes);
  }

  void _showImage(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text('${session.movementName} · Saved image'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _RetrySavedImageAction extends StatelessWidget {
  const _RetrySavedImageAction({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: AppTheme.caption),
        const SizedBox(width: AppSpacing.xs),
        Button(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _MembershipPanel extends StatelessWidget {
  const _MembershipPanel({
    required this.controller,
    required this.title,
    required this.body,
  });

  final TeacherStudentDetailController controller;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.isPrivateProfile) const _PrivateProfileBadge(),
        const SizedBox(height: AppSpacing.md),
        _MessagePanel(title: title, body: body),
        const SizedBox(height: AppSpacing.lg),
        Text(controller.displayName, style: AppTheme.headingMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          teacherStudentStatusLabel(
            effectiveMembershipStatus(controller.classroomMemberships),
          ),
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ElixStatusPanel(
      title: title,
      message: body,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.elixBorder),
      ),
      child: Text(label, style: AppTheme.caption),
    );
  }
}
