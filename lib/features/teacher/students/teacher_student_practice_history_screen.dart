import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_panel_card.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/assessment_score_display.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import 'teacher_student_detail_controller.dart';

class TeacherStudentPracticeHistoryScreen extends StatefulWidget {
  const TeacherStudentPracticeHistoryScreen({
    super.key,
    required this.traineeId,
    this.groupId,
  });
  final String traineeId;
  final String? groupId;
  @override
  State<TeacherStudentPracticeHistoryScreen> createState() =>
      _TeacherStudentPracticeHistoryScreenState();
}

class _TeacherStudentPracticeHistoryScreenState
    extends State<TeacherStudentPracticeHistoryScreen> {
  TeacherStudentDetailController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null) return;
    _controller = TeacherStudentDetailController(
      groupRepository: context.read(),
      progressRepository: context.read(),
      publicProfileRepository: context.read<PublicProfileRepository>(),
      teacherId: teacherId,
      traineeId: widget.traineeId,
      preferredGroupId: widget.groupId,
      initialPracticePageSize: TeacherProgressRepository.defaultPageSize,
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const Center(child: ProgressRing());
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => TeacherScaffoldPage(
        scrollable: false,
        header: const ElixEditorialPageHeader(
          heading: 'Practice history',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              label: 'Student details',
              tooltip: 'Back to student details',
              semanticLabel: 'Back to student details',
              onPressed: () => context.go(
                AppRoutePaths.teacherStudentDetail(
                  widget.traineeId,
                  groupId: widget.groupId,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _HistoryBody(controller: controller)),
          ],
        ),
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.controller});
  final TeacherStudentDetailController controller;
  @override
  Widget build(BuildContext context) {
    if (controller.state == TeacherStudentDetailState.loadingClassroom ||
        controller.state == TeacherStudentDetailState.loadingProgress)
      return const Center(child: ProgressRing());
    if (controller.state == TeacherStudentDetailState.unauthorized ||
        controller.state == TeacherStudentDetailState.pending ||
        controller.state == TeacherStudentDetailState.relationshipRemoved)
      return const ElixStatusPanel(
        isError: true,
        message:
            'Classroom authorization is required to view practice history.',
      );
    if (controller.state == TeacherStudentDetailState.error ||
        controller.state == TeacherStudentDetailState.connectionRequired)
      return ElixStatusPanel(
        isError: true,
        message: 'Practice history could not be loaded.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      );
    if (controller.sessions.isEmpty)
      return const ElixStatusPanel(message: 'No practice history yet.');
    return ListView(
      children: [
        for (final session in controller.sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ElixPanelCard(
              child: Row(
                children: [
                  MovementImage(movementName: session.movementName, size: 48),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.movementName,
                          style: AppTheme.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${session.difficulty} · ${_historyDate(session.createdAt)} · ${_historyDuration(session.durationSeconds)} · ${session.isRubricAssessed ? AssessmentScoreDisplay.official(session.rubric!.total) : '${session.legacyScore ?? 0}%'}${session.isRubricAssessed ? ' · ${session.rubric!.performanceLevel.label}' : ''}',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                        if (session.evidenceAvailable == true)
                          Text(
                            'Saved evidence available',
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
        if (controller.paginationError != null)
          Button(
            onPressed: controller.retryLoadMore,
            child: const Text('Retry load more'),
          )
        else if (controller.hasMore)
          Center(
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

String _historyDuration(int seconds) {
  if (seconds < 60) return '$seconds sec';
  final duration = Duration(seconds: seconds);
  return duration.inHours > 0
      ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
      : '${duration.inMinutes}m';
}

String _historyDate(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return parsed == null
      ? 'Date unavailable'
      : DateFormat('MMM d, y · h:mm a').format(parsed.toLocal());
}
