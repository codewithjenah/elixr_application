import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/classroom_announcement_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/router/navigation_helpers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../assigned_movements/assigned_movement_list.dart';
import '../classroom_announcements/classroom_announcements_controller.dart';
import '../classroom_announcements/classroom_announcements_pane.dart';
import 'trainee_class_card.dart';
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
      return const Center(child: ProgressRing());
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

    final showStreamContext =
        controller.tab == TraineeClassDetailTab.announcements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStreamContext) ...[
          TraineeClassHeroBanner(
            groupId: controller.groupId,
            title: controller.className,
            subtitle:
                [
                      controller.teacherDisplayName,
                      controller.group?.section,
                      controller.group?.schedule,
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
            height: 128,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
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
              key: const Key('teacher_access_class_tab_people'),
              label: 'People',
              icon: FluentIcons.people,
              selected: controller.tab == TraineeClassDetailTab.people,
              onPressed: () => controller.setTab(TraineeClassDetailTab.people),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(message: controller.errorMessage!, isError: true),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controller.tab == TraineeClassDetailTab.classwork)
          _ClassworkPane(controller: controller)
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

class _ClassworkPane extends StatelessWidget {
  const _ClassworkPane({required this.controller});

  final TraineeClassDetailController controller;

  @override
  Widget build(BuildContext context) {
    final assignments = controller.assignments;
    if (assignments == null || assignments.loading) {
      return const Center(child: ProgressRing());
    }
    if (assignments.errorMessage != null && assignments.items.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: ElixStatusPanel(
          message: assignments.errorMessage!,
          isError: true,
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Button(
            key: const Key('teacher_access_class_view_your_work'),
            onPressed: () => context.push(
              AppRoutePaths.teacherAccessClassWork(controller.groupId),
              extra: true,
            ),
            child: const Text('View your work'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ClassroomTopicContent(items: assignments.items, showGroupName: false),
      ],
    );
  }
}

class _PeoplePane extends StatelessWidget {
  const _PeoplePane({required this.controller});

  final TraineeClassDetailController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.classmatesLoading) {
      return const Center(child: ProgressRing());
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
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
          const SizedBox(height: AppSpacing.xl),
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
        Divider(
          style: DividerThemeData(
            decoration: BoxDecoration(color: context.elixBorder),
            horizontalMargin: EdgeInsets.zero,
            verticalMargin: EdgeInsets.zero,
          ),
        ),
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
    return HoverButton(
      onPressed: onPressed,
      cursor: SystemMouseCursors.click,
      builder: (context, states) {
        final hovered = states.isHovered;
        final foreground = selected ? Colors.white : context.elixTextPrimary;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? (highContrast ? AppColors.primary : null)
                : Color.alphaBlend(
                    (hovered ? AppColors.primary : Colors.transparent)
                        .withValues(alpha: hovered ? 0.06 : 0),
                    context.elixCardSurface,
                  ),
            gradient: selected && !highContrast
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.accent],
                  )
                : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? (highContrast ? context.elixBorder : Colors.transparent)
                  : context.elixBorder.withValues(
                      alpha: highContrast ? 1 : 0.9,
                    ),
              width: highContrast ? 2 : 1,
            ),
            boxShadow: selected && !highContrast
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
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
