import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../assigned_movements/assigned_movement_list.dart';
import 'trainee_class_card.dart';
import 'trainee_class_detail_controller.dart';

class TraineeClassDetailScreen extends StatefulWidget {
  const TraineeClassDetailScreen({
    super.key,
    required this.groupId,
    this.controller,
  });

  final String groupId;
  final TraineeClassDetailController? controller;

  @override
  State<TraineeClassDetailScreen> createState() =>
      _TraineeClassDetailScreenState();
}

class _TraineeClassDetailScreenState extends State<TraineeClassDetailScreen> {
  TraineeClassDetailController? _owned;
  late final bool _ownsController;

  TraineeClassDetailController? get _controller => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ownsController || _owned != null) return;
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
    _owned = TraineeClassDetailController(
      groupId: widget.groupId,
      traineeId: traineeId,
      groupRepository: context.read<GroupRepository>(),
      assignmentRepository: context.read<ClassroomAssignmentRepository>(),
      submissionRepository: submissionRepository,
      publicProfileRepository: publicProfileRepository,
    )..start();
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ElixScaffoldPage(content: Center(child: ProgressRing()));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          content: _ClassDetailBody(controller: controller),
        );
      },
    );
  }
}

class _ClassDetailBody extends StatelessWidget {
  const _ClassDetailBody({required this.controller});

  final TraineeClassDetailController controller;

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
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  key: const Key('teacher_access_class_back'),
                  icon: const Icon(FluentIcons.back),
                  label: const Text('Back to classes'),
                  onPressed: () => context.go(AppRoutePaths.teacherAccess),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: _buildPageContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.unauthorized) {
      return const ElixStatusPanel(
        key: Key('teacher_access_class_unauthorized'),
        message:
            'This class is not available. You need an approved membership '
            'to open it.',
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
        TraineeClassHeroBanner(
          groupId: controller.groupId,
          title: controller.className,
          subtitle: controller.teacherDisplayName,
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
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
        const SizedBox(height: AppSpacing.lg),
        if (controller.errorMessage != null) ...[
          ElixStatusPanel(message: controller.errorMessage!, isError: true),
          const SizedBox(height: AppSpacing.md),
        ],
        controller.tab == TraineeClassDetailTab.classwork
            ? _ClassworkPane(controller: controller)
            : _PeoplePane(controller: controller),
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
    return AssignedMovementContent(
      items: assignments.items,
      showGroupName: false,
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
    if (controller.classmates.isEmpty) {
      return const Align(
        alignment: Alignment.topCenter,
        child: ElixStatusPanel(
          key: Key('teacher_access_class_classmates_empty'),
          icon: FluentIcons.people,
          title: 'No classmates yet',
          message: 'No students in this class yet.',
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < controller.classmates.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) {
              final member = controller.classmates[index];
              final isYou = member.traineeId == controller.traineeId;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.elixCardSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isYou
                        ? AppColors.primary.withValues(
                            alpha: context.isHighContrast ? 1 : 0.35,
                          )
                        : context.elixBorder.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    ProfileAvatarWidget(
                      key: Key(
                        'teacher_access_classmate_avatar_'
                        '${controller.groupId}_${member.traineeId}',
                      ),
                      radius: 18,
                      showBorder: false,
                      initials: userInitials(member.traineeDisplayName),
                      networkImageUrl: controller.profilePictureUrlFor(
                        member.traineeId,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isYou
                                ? '${member.traineeDisplayName} (you)'
                                : member.traineeDisplayName,
                            style: AppTheme.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.elixTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isYou ? 'You are in this class' : 'In this class',
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
