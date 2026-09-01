import 'dart:typed_data';

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
    this.evidenceRepository,
  });
  final String traineeId;
  final String? groupId;
  final TeacherEvidenceRepository? evidenceRepository;
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
      evidenceRepository: widget.evidenceRepository ?? _maybeEvidence(context),
    )..start();
  }

  TeacherEvidenceRepository? _maybeEvidence(BuildContext context) {
    try {
      return context.read<TeacherEvidenceRepository>();
    } on ProviderNotFoundException {
      return null;
    }
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
          heading: 'History',
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
        message: 'Classroom authorization is required to view History.',
      );
    if (controller.state == TeacherStudentDetailState.error ||
        controller.state == TeacherStudentDetailState.connectionRequired)
      return ElixStatusPanel(
        isError: true,
        message: 'History could not be loaded.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      );
    if (controller.sessions.isEmpty)
      return const ElixStatusPanel(message: 'No History yet.');
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
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: _HistoryEvidence(
                              controller: controller,
                              session: session,
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

class _HistoryEvidence extends StatelessWidget {
  const _HistoryEvidence({required this.controller, required this.session});

  final TeacherStudentDetailController controller;
  final PublicProfileSession session;

  @override
  Widget build(BuildContext context) {
    final state = controller.evidenceStateFor(session.sessionId);
    final bytes = controller.evidenceFor(session.sessionId);
    if (state == TeacherEvidenceState.idle) {
      return Button(
        key: Key('teacher_history_evidence_${session.sessionId}'),
        onPressed: () => controller.loadEvidence(session),
        child: const Text('View saved image'),
      );
    }
    if (state == TeacherEvidenceState.loading) {
      return const SizedBox(height: 72, child: Center(child: ProgressRing()));
    }
    if (state == TeacherEvidenceState.loaded && bytes != null) {
      return _EvidencePreview(session: session, bytes: bytes);
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            state == TeacherEvidenceState.unavailable
                ? 'Saved image is unavailable.'
                : 'Saved image could not be loaded.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ),
        Button(
          onPressed: () => controller.retryEvidence(session),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _EvidencePreview extends StatelessWidget {
  const _EvidencePreview({required this.session, required this.bytes});

  final PublicProfileSession session;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'View saved image',
    child: Semantics(
      button: true,
      label: 'View saved image for ${session.movementName}',
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth < 220 ? constraints.maxWidth : 220,
          height: 150,
          child: Button(
            onPressed: () => _showEvidence(context, session, bytes),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(EdgeInsets.zero),
            ),
            child: Container(
              key: Key('teacher_history_evidence_preview_${session.sessionId}'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(-1, 1, 1),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Color(0x8C000000),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Text(
                          'Click to enlarge',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void _showEvidence(
  BuildContext context,
  PublicProfileSession session,
  Uint8List bytes,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: Text('${session.movementName} · Saved image'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
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
