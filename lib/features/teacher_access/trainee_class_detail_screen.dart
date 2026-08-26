import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/utils/user_name.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
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
          header: PageHeader(
            title: Text(controller.className),
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
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.unauthorized) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          key: Key('teacher_access_class_unauthorized'),
          message:
              'This class is not available. You need an approved membership '
              'to open it.',
          isError: true,
        ),
      );
    }
    if (controller.errorMessage != null &&
        controller.classmates.isEmpty &&
        (controller.assignments?.items.isEmpty ?? true)) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ElixStatusPanel(
          message: controller.errorMessage!,
          isError: true,
        ),
      );
    }

    final banner = traineeClassBannerColor(controller.groupId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: banner,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.className,
                        style: AppTheme.headingLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        controller.teacherDisplayName,
                        style: AppTheme.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ToggleButton(
                key: const Key('teacher_access_class_tab_classwork'),
                checked: controller.tab == TraineeClassDetailTab.classwork,
                onChanged: (_) =>
                    controller.setTab(TraineeClassDetailTab.classwork),
                child: const Text('Classwork'),
              ),
              ToggleButton(
                key: const Key('teacher_access_class_tab_people'),
                checked: controller.tab == TraineeClassDetailTab.people,
                onChanged: (_) =>
                    controller.setTab(TraineeClassDetailTab.people),
                child: const Text('People'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (controller.errorMessage != null) ...[
            ElixStatusPanel(message: controller.errorMessage!, isError: true),
            const SizedBox(height: AppSpacing.md),
          ],
          Expanded(
            child: controller.tab == TraineeClassDetailTab.classwork
                ? _ClassworkPane(controller: controller)
                : _PeoplePane(controller: controller),
          ),
        ],
      ),
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
      return ElixStatusPanel(message: assignments.errorMessage!, isError: true);
    }
    if (assignments.items.isEmpty) {
      return ElixStatusPanel(
        key: const Key('teacher_access_class_assignments_empty'),
        message:
            'No assigned movements in this class yet. Work from your '
            'teacher will show up here.',
      );
    }
    return AssignedMovementList(items: assignments.items, showGroupName: false);
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
      return const ElixStatusPanel(
        key: Key('teacher_access_class_classmates_empty'),
        message: 'No students in this class yet.',
      );
    }
    return ListView.separated(
      itemCount: controller.classmates.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final member = controller.classmates[index];
        final isYou = member.traineeId == controller.traineeId;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.elixBackground.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.elixBorder.withValues(alpha: 0.45),
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
    );
  }
}
