import 'package:elixr_core/models/group_membership.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../services/auth_service.dart';
import 'teacher_student_models.dart';
import 'teacher_students_controller.dart';

class TeacherStudentsScreen extends StatefulWidget {
  const TeacherStudentsScreen({super.key});

  @override
  State<TeacherStudentsScreen> createState() => _TeacherStudentsScreenState();
}

class _TeacherStudentsScreenState extends State<TeacherStudentsScreen> {
  TeacherStudentsController? _controller;
  final _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;
    _controller = TeacherStudentsController(
      repository: context.read(),
      teacherId: userId,
    )..start();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const TeacherScaffoldPage(
        header: ElixEditorialPageHeader(
          heading: 'Students',
          eyebrow: 'TEACHER WORKSPACE',
        ),
        scrollable: false,
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TeacherScaffoldPage(
          header: const ElixEditorialPageHeader(
            heading: 'Students',
            eyebrow: 'TEACHER WORKSPACE',
            subtitle: 'Review your active trainee roster.',
          ),
          scrollable: false,
          contentPadding: EdgeInsets.zero,
          content: controller.loading
              ? const Center(child: ProgressRing())
              : controller.errorMessage != null
              ? _ErrorState(
                  message: controller.errorMessage!,
                  onRetry: controller.retry,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Toolbar(
                          controller: controller,
                          searchController: _searchController,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: controller.groups.isEmpty
                          ? _EmptyStudents(controller: controller)
                          : controller.visibleGroupRosters.isEmpty
                          ? _EmptyStudents(controller: controller)
                          : _GroupedStudentRoster(controller: controller),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.searchController});

  final TeacherStudentsController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextBox(
            controller: searchController,
            placeholder: 'Search by name',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search),
            ),
            onChanged: controller.setSearchQuery,
          ),
        ),
        ComboBox<String?>(
          value: controller.selectedGroupId,
          placeholder: const Text('All classes'),
          items: [
            const ComboBoxItem(value: null, child: Text('All classes')),
            for (final group in controller.groups.where((g) => g.isActive))
              ComboBoxItem(value: group.id, child: Text(group.name)),
          ],
          onChanged: controller.setGroupFilter,
        ),
        ComboBox<TeacherStudentStatusFilter>(
          value: controller.statusFilter,
          items: const [
            ComboBoxItem(
              value: TeacherStudentStatusFilter.approved,
              child: Text('Approved'),
            ),
            ComboBoxItem(
              value: TeacherStudentStatusFilter.all,
              child: Text('All statuses'),
            ),
            ComboBoxItem(
              value: TeacherStudentStatusFilter.pending,
              child: Text('Pending'),
            ),
            ComboBoxItem(
              value: TeacherStudentStatusFilter.inactive,
              child: Text('Removed / inactive'),
            ),
          ],
          onChanged: (value) {
            if (value != null) controller.setStatusFilter(value);
          },
        ),
      ],
    );
  }
}

class _GroupedStudentRoster extends StatelessWidget {
  const _GroupedStudentRoster({required this.controller});

  final TeacherStudentsController controller;

  @override
  Widget build(BuildContext context) {
    final rosters = controller.visibleGroupRosters;
    return CustomScrollView(
      key: const Key('teacher_students_page_scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              for (var index = 0; index < rosters.length; index++) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : AppSpacing.lg,
                      bottom: AppSpacing.sm,
                    ),
                    child: _GroupRosterHeader(roster: rosters[index]),
                  ),
                ),
                if (rosters[index].memberships.isEmpty)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((
                      context,
                      studentIndex,
                    ) {
                      final membership =
                          rosters[index].memberships[studentIndex];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _StudentRow(
                          membership: membership,
                          onOpen: () {
                            context.go(
                              AppRoutePaths.teacherStudentDetail(
                                membership.traineeId,
                                groupId: membership.groupId,
                              ),
                            );
                          },
                        ),
                      );
                    }, childCount: rosters[index].memberships.length),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupRosterHeader extends StatelessWidget {
  const _GroupRosterHeader({required this.roster});

  final TeacherGroupRoster roster;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(roster.group.name, style: AppTheme.headingMedium),
        const SizedBox(height: 2),
        Text(
          roster.memberships.isEmpty
              ? 'No students in this class yet.'
              : '${roster.memberships.length} '
                    '${roster.memberships.length == 1 ? 'student' : 'students'}',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.membership, required this.onOpen});

  final GroupMembership membership;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onOpen,
      builder: (context, states) {
        return ElixPanelCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  membership.traineeDisplayName,
                  style: AppTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
              ),
              _StatusBadge(status: membership.status),
              const SizedBox(width: AppSpacing.md),
              Button(onPressed: onOpen, child: const Text('Open details')),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GroupMembershipStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: context.elixBackground,
      ),
      child: Text(
        teacherStudentStatusLabel(status),
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      ),
    );
  }
}

class _EmptyStudents extends StatelessWidget {
  const _EmptyStudents({required this.controller});

  final TeacherStudentsController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ElixStatusPanel(
          message: controller.groups.isEmpty
              ? 'No students yet. Open Groups, share a class code, then accept students. Each class has its own student list.'
              : 'No students match the current filters.',
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ElixStatusPanel(
          isError: true,
          message: message,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      ),
    );
  }
}
