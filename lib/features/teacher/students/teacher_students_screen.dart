import 'package:elixr_core/models/group_membership.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
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
      return const ElixScaffoldPage(
        header: PageHeader(title: Text('Students')),
        scrollable: false,
        content: Center(child: ProgressRing()),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ElixScaffoldPage(
          header: const PageHeader(title: Text('Students')),
          scrollable: false,
          content: controller.loading
              ? const Center(child: ProgressRing())
              : controller.errorMessage != null
              ? _ErrorState(
                  message: controller.errorMessage!,
                  onRetry: controller.retry,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Toolbar(
                      controller: controller,
                      searchController: _searchController,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: controller.visibleEntries.isEmpty
                          ? _EmptyStudents(controller: controller)
                          : _StudentRoster(controller: controller),
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
          placeholder: const Text('All groups'),
          items: [
            const ComboBoxItem(value: null, child: Text('All groups')),
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

class _StudentRoster extends StatelessWidget {
  const _StudentRoster({required this.controller});

  final TeacherStudentsController controller;

  @override
  Widget build(BuildContext context) {
    final groupNames = {
      for (final group in controller.groups) group.id: group.name,
    };
    return ListView.separated(
      itemCount: controller.visibleEntries.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final entry = controller.visibleEntries[index];
        return _StudentRow(
          entry: entry,
          groupNames: groupNames,
          onOpen: () {
            final groupId = entry.memberships
                .where((m) => m.isApproved)
                .map((m) => m.groupId)
                .firstOrNull;
            context.go(
              AppRoutePaths.teacherStudentDetail(
                entry.traineeId,
                groupId: groupId,
              ),
            );
          },
        );
      },
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.entry,
    required this.groupNames,
    required this.onOpen,
  });

  final TeacherStudentEntry entry;
  final Map<String, String> groupNames;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onOpen,
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: states.isHovered
                ? context.elixCardSurface.withValues(alpha: 0.9)
                : context.elixCardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.elixBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.displayName, style: AppTheme.headingMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final membership in entry.memberships)
                          _GroupChip(
                            label:
                                groupNames[membership.groupId] ??
                                membership.groupId,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: entry.effectiveStatus),
              const SizedBox(width: AppSpacing.md),
              Button(onPressed: onOpen, child: const Text('Open details')),
            ],
          ),
        );
      },
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.elixBorder),
      ),
      child: Text(label, style: AppTheme.caption),
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
      child: Text(
        controller.allEntries.isEmpty
            ? 'No students yet. Approve join requests in Groups.'
            : 'No students match the current filters.',
        style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        textAlign: TextAlign.center,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: AppTheme.body),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
