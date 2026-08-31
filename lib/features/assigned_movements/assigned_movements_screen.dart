import 'package:elixr_core/repositories/group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/auth_service.dart';
import 'assigned_movement_list.dart';
import 'assigned_movements_controller.dart';

class AssignedMovementsScreen extends StatefulWidget {
  const AssignedMovementsScreen({super.key, this.controller, this.groupId});

  final AssignedMovementsController? controller;
  final String? groupId;

  @override
  State<AssignedMovementsScreen> createState() =>
      _AssignedMovementsScreenState();
}

class _AssignedMovementsScreenState extends State<AssignedMovementsScreen> {
  AssignedMovementsController? _controller;
  late final bool _ownsController;

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
    _controller = AssignedMovementsController(
      traineeId: traineeId,
      groupRepository: context.read<GroupRepository>(),
      assignmentRepository: context.read<ClassroomAssignmentRepository>(),
      submissionRepository: context.read<AssignmentSubmissionRepository>(),
      filterGroupId: widget.groupId,
    )..start();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
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
          padding: EdgeInsets.zero,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.pageTopInset,
                  AppSpacing.lg,
                  0,
                ),
                child: ElixEditorialHeader(
                  heading: widget.groupId == null
                      ? 'Assigned Movements'
                      : 'Your work',
                  subtitle: widget.groupId == null
                      ? 'Classroom work from your approved groups, split into Official ELIXR and Teacher-created. Public profile privacy does not hide these assignments.'
                      : 'Assignments for this classroom. Select an item to continue or review your work.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: _Body(controller: controller)),
            ],
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final AssignedMovementsController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.errorMessage != null && controller.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(controller.errorMessage!),
            const SizedBox(height: AppSpacing.md),
            Button(onPressed: controller.retry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (controller.items.isEmpty) {
      return Center(
        child: Text(
          'No assigned movements yet. When a teacher assigns work to one of your classes, it will appear here.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(color: context.elixTextSecondary),
        ),
      );
    }
    return AssignedMovementList(
      items: controller.items,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
    );
  }
}
