import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/router/navigation_helpers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/class_challenge_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../assigned_movements/assigned_movement_list.dart';
import '../classroom_announcements/classroom_announcements_controller.dart';
import '../classroom_announcements/classroom_announcements_pane.dart';
import '../class_challenges/class_challenges_pane.dart';
import 'trainee_class_detail_controller.dart';

class TraineeClassDetailScreen extends StatefulWidget {
  const TraineeClassDetailScreen({
    super.key,
    required this.groupId,
    this.controller,
    this.announcementsController,
    this.initialTab,
  });

  final String groupId;
  final TraineeClassDetailController? controller;
  final ClassroomAnnouncementsController? announcementsController;
  final String? initialTab;

  @override
  State<TraineeClassDetailScreen> createState() =>
      _TraineeClassDetailScreenState();
}

class _TraineeClassDetailScreenState extends State<TraineeClassDetailScreen> {
  TraineeClassDetailController? _owned;
  ClassroomAnnouncementsController? _ownedAnnouncements;
  late final bool _ownsController;

  TraineeClassDetailController? get _controller => widget.controller ?? _owned;
  ClassroomAnnouncementsController? get _announcementsController =>
      widget.announcementsController ?? _ownedAnnouncements;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final injected = widget.controller;
    if (_ownsController && _owned == null) {
      final traineeId = context.read<AuthService>().currentUser?.id;
      if (traineeId == null) return;
      PublicProfileRepository? publicProfileRepository;
      try {
        publicProfileRepository = context.read<PublicProfileRepository>();
      } on ProviderNotFoundException {
        publicProfileRepository = null;
      }
      AssignmentSubmissionRepository? submissionRepository;
      try {
        submissionRepository = context.read<AssignmentSubmissionRepository>();
      } on ProviderNotFoundException {
        submissionRepository = null;
      }
      _owned =
          TraineeClassDetailController(
              groupId: widget.groupId,
              traineeId: traineeId,
              groupRepository: context.read<GroupRepository>(),
              assignmentRepository: context
                  .read<ClassroomAssignmentRepository>(),
              submissionRepository: submissionRepository,
              publicProfileRepository: publicProfileRepository,
            )
            ..setTab(_traineeTabFromQuery(widget.initialTab))
            ..start();
    }
    final traineeId = injected?.traineeId ?? _owned?.traineeId;
    if (traineeId == null || _announcementsController != null) return;
    ClassroomAnnouncementRepository? announcements;
    try {
      announcements = context.read<ClassroomAnnouncementRepository>();
    } on ProviderNotFoundException {
      announcements = null;
    }
    if (announcements != null) {
      _ownedAnnouncements = ClassroomAnnouncementsController(
        repository: announcements,
        groupId: widget.groupId,
        currentUserId: traineeId,
        canManage: false,
        isGroupActive: () => _controller?.group?.isActive == true,
      )..start();
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    _ownedAnnouncements?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ElixScaffoldPage(content: Center(child: ProgressRing()));
    }
    return AnimatedBuilder(
      animation: Listenable.merge([controller, ?_announcementsController]),
      builder: (context, _) {
        return ElixScaffoldPage(
          content: _ClassDetailBody(
            controller: controller,
            announcements: _announcementsController,
          ),
        );
      },
    );
  }
}

TraineeClassDetailTab _traineeTabFromQuery(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'classwork' => TraineeClassDetailTab.classwork,
    'challenges' => TraineeClassDetailTab.challenges,
    'people' => TraineeClassDetailTab.people,
    _ => TraineeClassDetailTab.announcements,
  };
}

class _ClassDetailBody extends StatelessWidget {
  const _ClassDetailBody({required this.controller, this.announcements});

  final TraineeClassDetailController controller;
  final ClassroomAnnouncementsController? announcements;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('teacher_access_class_page_scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElixEditorialPageHeader(
            heading: controller.className,
            eyebrow: 'CLASSROOM',
            subtitle: 'Review assignments and activity for this class.',
            variant: ElixEditorialHeaderVariant.compact,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ElixBackButton(
              key: const Key('teacher_access_class_back'),
              label: 'Classes',
              tooltip: 'Back to classes',
              semanticLabel: 'Back to classes',
              onPressed: () => popOrGo(context, AppRoutePaths.teacherAccess),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildPageContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(BuildContext context) {
    if (controller.loading) {
      return const ElixStatusPanel(
        isLoading: true,
        icon: FluentIcons.people,
        title: 'Loading classroom',
        message: 'Loading classroom details and classwork.',
      );
    }
    if (controller.unauthorized) {
      return const ElixStatusPanel(
        key: Key('teacher_access_class_unauthorized'),
        message:
            'This class is not available. Only active classes you have joined '
            'can be opened here.',
        isError: true,
      );
    }
    if (controller.errorMessage != null &&
        controller.classmates.isEmpty &&
        (controller.assignments?.items.isEmpty ?? true)) {
      return ElixStatusPanel(message: controller.errorMessage!, isError: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClassroomSummaryCard(controller: controller),
        const SizedBox(height: AppSpacing.md),
        ElixPanelCard(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ClassDetailTab(
                key: const Key('teacher_access_class_tab_announcements'),
                label: 'Stream',
                icon: FluentIcons.megaphone,
                selected: controller.tab == TraineeClassDetailTab.announcements,
                onPressed: () =>
                    controller.setTab(TraineeClassDetailTab.announcements),
              ),
              _ClassDetailTab(
                key: const Key('teacher_access_class_tab_classwork'),
                label: 'Classwork',
                icon: FluentIcons.education,
                selected: controller.tab == TraineeClassDetailTab.classwork,
                onPressed: () =>
                    controller.setTab(TraineeClassDetailTab.classwork),
              ),
              _ClassDetailTab(
                key: const Key('teacher_access_class_tab_challenges'),
                label: 'Challenges',
                icon: FluentIcons.trophy,
                selected: controller.tab == TraineeClassDetailTab.challenges,
                onPressed: () =>
                    controller.setTab(TraineeClassDetailTab.challenges),
              ),
              _ClassDetailTab(
                key: const Key('teacher_access_class_tab_people'),
                label: 'People',
                icon: FluentIcons.people,
                selected: controller.tab == TraineeClassDetailTab.people,
                onPressed: () =>
                    controller.setTab(TraineeClassDetailTab.people),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(
            message: controller.errorMessage!,
            isError: true,
            icon: FluentIcons.error_badge,
            actionLabel: 'Retry',
            onAction: controller.start,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.tab == TraineeClassDetailTab.classwork)
          _ClassworkPane(controller: controller)
        else if (controller.tab == TraineeClassDetailTab.challenges)
          ClassChallengesPane(
            key: const Key('teacher_access_class_challenges'),
            repository: context.read<ClassChallengeRepository>(),
            groupId: controller.groupId,
            teacherId: controller.membership?.teacherId ?? '',
            teacherDisplayName: controller.teacherDisplayName,
            currentUserId: controller.traineeId,
            isTeacher: false,
            groupIsActive: controller.group?.isActive == true,
            participantCount: controller.classmates.length,
            onOpenLeaderboard: (challenge) => context.push(
              AppRoutePaths.classChallengeLeaderboard(
                controller.groupId,
                challenge.id,
              ),
            ),
            onStart: (challenge) => context.go(
              AppRoutePaths.classChallengePlay(
                controller.groupId,
                challenge.id,
              ),
            ),
          )
        else if (controller.tab == TraineeClassDetailTab.announcements)
          announcements == null
              ? const ElixStatusPanel(
                  message: 'Announcements are not available right now.',
                  isError: true,
                )
              : ClassroomAnnouncementsPane(
                  controller: announcements!,
                  teacherDisplayName: controller.teacherDisplayName,
                  teacherProfilePictureUrl: controller.profilePictureUrlFor(
                    controller.membership?.teacherId ?? '',
                  ),
                  canManage: false,
                  groupIsActive: controller.group?.isActive == true,
                  assignments:
                      controller.assignments?.items
                          .map((item) => item.assignment)
                          .toList(growable: false) ??
                      const [],
                  onOpenAssignment: (assignment) => context.push(
                    AppRoutePaths.assignmentDetail(assignment.id),
                  ),
                )
        else
          _PeoplePane(controller: controller),
      ],
    );
  }
}

class _ClassroomSummaryCard extends StatelessWidget {
  const _ClassroomSummaryCard({required this.controller});

  final TraineeClassDetailController controller;

  @override
  Widget build(BuildContext context) {
    final group = controller.group;
    final metadata = [
      if (group?.section?.trim().isNotEmpty == true) group!.section!.trim(),
      if (group?.schedule?.trim().isNotEmpty == true) group!.schedule!.trim(),
    ];
    final assignmentCount = controller.assignments?.items.length;
    final status = group?.isActive == true ? 'Active' : 'Unavailable';

    return ElixPanelCard(
      accent: AppColors.primary,
      showAccentBar: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatarWidget(
                    key: Key(
                      'teacher_access_class_teacher_avatar_summary_'
                      '${controller.groupId}',
                    ),
                    radius: 24,
                    showBorder: false,
                    initials: userInitials(controller.teacherDisplayName),
                    networkImageUrl: controller.profilePictureUrlFor(
                      controller.membership?.teacherId ?? '',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Teacher',
                          style: AppTheme.label(
                            color: context.elixTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          controller.teacherDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle(
                            color: context.elixTextPrimary,
                          ),
                        ),
                        if (metadata.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            metadata.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
              final statusChip = ElixPill(
                text: status,
                color: status == 'Active'
                    ? context.elixColors.success
                    : context.elixColors.warning,
                compact: true,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.sm),
                    statusChip,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: AppSpacing.md),
                  statusChip,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _ClassroomHairline(),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _ClassroomMeta(
                icon: FluentIcons.assign,
                label: 'Classwork',
                value: assignmentCount == null
                    ? 'Loading'
                    : '$assignmentCount '
                          '${assignmentCount == 1 ? 'assignment' : 'assignments'}',
              ),
              _ClassroomMeta(
                icon: FluentIcons.people,
                label: 'People',
                value:
                    '${controller.classmates.length} '
                    '${controller.classmates.length == 1 ? 'member' : 'members'}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassroomMeta extends StatelessWidget {
  const _ClassroomMeta({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: context.elixTextSecondary),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.label(color: context.elixTextSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClassworkPane extends StatelessWidget {
  const _ClassworkPane({required this.controller});

  final TraineeClassDetailController controller;

  @override
  Widget build(BuildContext context) {
    final assignments = controller.assignments;
    if (assignments == null || assignments.loading) {
      return const ElixStatusPanel(
        isLoading: true,
        icon: FluentIcons.education,
        title: 'Loading classwork',
        message: 'Loading assignments for this classroom.',
      );
    }
    if (assignments.errorMessage != null && assignments.items.isEmpty) {
      return ElixStatusPanel(
        message: assignments.errorMessage!,
        isError: true,
        icon: FluentIcons.error_badge,
        title: 'Could not load classwork',
        actionLabel: 'Retry',
        onAction: assignments.retry,
      );
    }
    if (assignments.items.isEmpty) {
      return const Align(
        alignment: Alignment.topCenter,
        child: ElixStatusPanel(
          key: Key('teacher_access_class_assignments_empty'),
          icon: FluentIcons.education,
          title: 'No classwork yet',
          message:
              'No assigned movements in this class yet. Work from your '
              'teacher will show up here.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, 1600.0)
            : 1600.0;
        return SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ClassworkToolbar(),
              const SizedBox(height: AppSpacing.md),
              ClassroomTopicContent(
                items: assignments.items,
                showGroupName: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassworkToolbar extends StatelessWidget {
  const _ClassworkToolbar();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Practice, review submissions, and track what is due.',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
    );
  }
}

class _PeoplePane extends StatelessWidget {
  const _PeoplePane({required this.controller});

  final TraineeClassDetailController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.classmatesLoading) {
      return const ElixStatusPanel(
        isLoading: true,
        icon: FluentIcons.people,
        title: 'Loading people',
        message: 'Loading classmates for this classroom.',
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: ElixPanelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RosterSectionHeader(title: 'Teachers'),
            _RosterRow(
              key: const Key('teacher_access_class_teacher_row'),
              avatarKey: Key(
                'teacher_access_class_teacher_avatar_${controller.groupId}',
              ),
              initials: userInitials(controller.teacherDisplayName),
              networkImageUrl: controller.profilePictureUrlFor(
                controller.membership?.teacherId ?? '',
              ),
              name: controller.teacherDisplayName,
            ),
            const SizedBox(height: AppSpacing.lg),
            _RosterSectionHeader(
              title: 'Classmates',
              trailing:
                  '${controller.classmates.length} '
                  '${controller.classmates.length == 1 ? 'classmate' : 'classmates'}',
            ),
            if (controller.classmates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: ElixStatusPanel(
                  key: Key('teacher_access_class_classmates_empty'),
                  icon: FluentIcons.people,
                  title: 'No classmates yet',
                  message: 'No students in this class yet.',
                ),
              )
            else
              for (final member in controller.classmates)
                _RosterRow(
                  key: Key(
                    'teacher_access_classmate_row_'
                    '${controller.groupId}_${member.traineeId}',
                  ),
                  avatarKey: Key(
                    'teacher_access_classmate_avatar_'
                    '${controller.groupId}_${member.traineeId}',
                  ),
                  initials: userInitials(member.traineeDisplayName),
                  networkImageUrl: controller.profilePictureUrlFor(
                    member.traineeId,
                  ),
                  name: member.traineeId == controller.traineeId
                      ? '${member.traineeDisplayName} (you)'
                      : member.traineeDisplayName,
                ),
          ],
        ),
      ),
    );
  }
}

class _RosterSectionHeader extends StatelessWidget {
  const _RosterSectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  trailing!,
                  style: AppTheme.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ClassroomHairline(),
      ],
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    super.key,
    required this.avatarKey,
    required this.initials,
    required this.name,
    this.networkImageUrl,
  });

  final Key avatarKey;
  final String initials;
  final String name;
  final String? networkImageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.elixBorder)),
      ),
      child: Row(
        children: [
          ProfileAvatarWidget(
            key: avatarKey,
            radius: 18,
            showBorder: false,
            initials: initials,
            networkImageUrl: networkImageUrl,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              name,
              style: AppTheme.body.copyWith(
                color: context.elixTextPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassDetailTab extends StatelessWidget {
  const _ClassDetailTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final colors = context.elixColors;
    return HoverButton(
      onPressed: onPressed,
      cursor: SystemMouseCursors.click,
      builder: (context, states) {
        final hovered = states.isHovered;
        final foreground = selected
            ? (highContrast ? colors.textPrimary : colors.brandPrimary)
            : colors.textPrimary;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? colors.surfaceSelected
                : hovered
                ? colors.interactiveHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colors.brandPrimary
                  : highContrast
                  ? colors.borderStrong
                  : Colors.transparent,
              width: highContrast || selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassroomHairline extends StatelessWidget {
  const _ClassroomHairline();

  @override
  Widget build(BuildContext context) {
    if (context.isHighContrast || shad.ShadTheme.maybeOf(context) == null) {
      return Container(height: 1, color: context.elixBorder);
    }
    return shad.ShadSeparator.horizontal(
      thickness: 1,
      color: context.elixBorder,
      margin: EdgeInsets.zero,
    );
  }
}
