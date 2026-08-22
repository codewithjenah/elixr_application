import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import '../practice/practice_run_phase.dart';
import '../practice/widgets/readiness_checklist_panel.dart';
import '../practice/widgets/training_action_area.dart';
import '../practice/widgets/training_camera_workspace.dart';
import '../practice/widgets/training_performance.dart';
import '../practice/widgets/training_session_header.dart';
import '../practice/widgets/training_session_panel.dart';
import '../practice/widgets/training_status_row.dart';
import 'template_scored_practice_controller.dart';

class TemplateScoredPracticeScreen extends StatefulWidget {
  const TemplateScoredPracticeScreen({
    super.key,
    required this.assignment,
    required this.traineeId,
    this.controller,
    this.websocketService,
  });

  final GroupAssignment assignment;
  final String traineeId;

  @visibleForTesting
  final TemplateScoredPracticeController? controller;

  @visibleForTesting
  final WebSocketService? websocketService;

  @override
  State<TemplateScoredPracticeScreen> createState() =>
      _TemplateScoredPracticeScreenState();
}

class _TemplateScoredPracticeScreenState
    extends State<TemplateScoredPracticeScreen> {
  late final TemplateScoredPracticeController _controller;
  late final bool _ownsController;
  bool _started = false;

  static const _wideBreakpoint = 1100.0;
  static const _panelWidth = 370.0;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        TemplateScoredPracticeController(
          assignment: widget.assignment,
          traineeId: widget.traineeId,
          assignmentRepository: context.read<ClassroomAssignmentRepository>(),
          websocket: widget.websocketService,
        );
    _controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.attachSettings(context.read<SettingsService>());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    await _controller.closePractice();
    if (!mounted) return;
    context.go(AppRoutePaths.assignedMovements);
  }

  TrainingSessionPhase _panelPhase() {
    if (_controller.holdConfirmed) return TrainingSessionPhase.completed;
    return switch (_controller.phase) {
      PracticeRunPhase.idle => TrainingSessionPhase.ready,
      PracticeRunPhase.preparingCamera => TrainingSessionPhase.preparingCamera,
      PracticeRunPhase.readiness => TrainingSessionPhase.readiness,
      PracticeRunPhase.countdown => TrainingSessionPhase.getReady,
      PracticeRunPhase.active => TrainingSessionPhase.inProgress,
      PracticeRunPhase.completed => TrainingSessionPhase.completed,
      PracticeRunPhase.error => TrainingSessionPhase.cameraError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    final phase = _controller.phase;
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final cameraLive =
        phase == PracticeRunPhase.readiness ||
        phase == PracticeRunPhase.countdown ||
        phase == PracticeRunPhase.active;
    final settings = context.watch<SettingsService>();

    final header = TrainingSessionHeader(
      onBack: () => unawaited(_leave()),
      title: assignment.displayTitle,
      statusPill: 'Wrist Stall',
      instruction:
          '${_controller.lateralityLabel} · Bottle · Classroom score, no global XP.',
      connectionState: _controller.connectionState,
      connecting: _controller.connecting,
      wideLayout: isWide,
      trailing: Button(
        key: const ValueKey('template-practice-back'),
        onPressed: () => unawaited(_leave()),
        child: const Text('Back'),
      ),
    );

    final camera = TrainingCameraWorkspace(
      frameBytes: _controller.previewFrame,
      mirrored: settings.cameraMirrored,
      connectionState: _controller.connectionState,
      connecting: _controller.connecting,
      isSessionActive: cameraLive,
      isPreparingCamera: phase == PracticeRunPhase.preparingCamera,
      accentBorder:
          phase == PracticeRunPhase.preparingCamera ||
          phase == PracticeRunPhase.readiness ||
          phase == PracticeRunPhase.countdown,
      errorMessage: _controller.websocket.errorMessage,
      sessionError: _controller.errorMessage,
      onRetry: () => unawaited(_controller.connect()),
      countdownActive: phase == PracticeRunPhase.countdown,
      onCountdownComplete: () =>
          unawaited(_controller.activateAfterCountdown()),
      overlayFeedback: phase == PracticeRunPhase.active
          ? _controller.latestFeedback
          : null,
    );

    return ElixScaffoldPage(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: camera),
                      const SizedBox(width: AppSpacing.practiceCameraPanelGap),
                      SizedBox(width: _panelWidth, child: _buildPanel()),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 360, child: camera),
                        const SizedBox(height: AppSpacing.md),
                        _buildPanel(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    final phase = _controller.phase;
    final readiness = _controller.readiness;
    final confirmed = _controller.holdConfirmed;
    final assessment = _controller.assessment;
    final feedback = _controller.latestFeedback;

    return TrainingSessionPanel(
      phase: _panelPhase(),
      expandVertically: MediaQuery.sizeOf(context).width >= _wideBreakpoint,
      metrics: SessionMetricTiles(
        elapsedDisplay: switch (phase) {
          PracticeRunPhase.preparingCamera => 'Setup',
          PracticeRunPhase.readiness => 'Ready',
          PracticeRunPhase.countdown => '3-2-1',
          PracticeRunPhase.active => 'Live',
          PracticeRunPhase.completed => 'Done',
          PracticeRunPhase.error => 'Error',
          PracticeRunPhase.idle => 'Idle',
        },
        rubricChild: Text(
          assessment == null
              ? '— / 12'
              : '${assessment.total} / ${RubricScale.maxTotal}',
          key: const ValueKey('template-practice-total'),
          style: AppTheme.headingMedium.copyWith(
            fontSize: 22,
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        performanceBar: TrainingPerformanceBar(total: assessment?.total),
        rubricBreakdown: RubricCriteriaTiles(assessment: assessment),
      ),
      statusContent: confirmed
          ? _CompletionState(controller: _controller)
          : (phase == PracticeRunPhase.readiness ||
                (phase == PracticeRunPhase.countdown && readiness.frozen))
          ? ReadinessChecklistPanel(
              items: readiness.displayItems,
              progress: readiness.stableProgress,
              stable: readiness.stable,
              complete: readiness.complete,
              frozen: readiness.frozen,
              streamStale: readiness.streamStale,
              recoverableMessage: readiness.recoverableMessage,
              readyCount: readiness.readyCount,
            )
          : TrainingStatusRow(
              detection: resolveDetectionStatus(
                sessionActive: phase == PracticeRunPhase.active,
                bottleDetected: feedback?.bottleDetected,
              ),
              propLabel: 'Bottle',
              postureLabel: postureDisplayLabel(feedback?.postureStatus),
            ),
      supportingContent: phase == PracticeRunPhase.active && !confirmed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (feedback != null) ...[
                  Text(feedback.feedback, style: AppTheme.body),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _HoldProgress(progress: _controller.holdProgress),
              ],
            )
          : null,
      actionArea: _buildActions(),
    );
  }

  Widget _buildActions() {
    if (_controller.holdConfirmed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_controller.saveErrorMessage != null) ...[
            TrainingActionArea(
              key: const ValueKey('template-practice-retry-save'),
              kind: TrainingActionKind.start,
              startLabel: 'Save classroom result',
              onPressed: () => unawaited(_controller.retrySave()),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: Button(
                  key: const ValueKey('template-practice-again'),
                  onPressed: () => unawaited(_controller.tryAgain()),
                  child: const Text('Try again'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TrainingActionArea(
                  kind: TrainingActionKind.finish,
                  startLabel: 'Done',
                  onPressed: () => unawaited(_leave()),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (_controller.phase == PracticeRunPhase.readiness) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrainingActionArea(
            kind: TrainingActionKind.start,
            startLabel: 'Start practice',
            onPressed: _controller.canStartPractice
                ? () => unawaited(_controller.confirmReadiness())
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          TrainingActionArea(
            kind: TrainingActionKind.cancel,
            startLabel: 'Stop',
            onPressed: () => unawaited(_controller.stopPractice()),
          ),
        ],
      );
    }

    if (_controller.phase == PracticeRunPhase.active ||
        _controller.phase == PracticeRunPhase.countdown ||
        _controller.phase == PracticeRunPhase.preparingCamera) {
      return TrainingActionArea(
        kind: TrainingActionKind.finish,
        startLabel: 'Stop',
        onPressed: () => unawaited(_controller.stopPractice()),
      );
    }

    return TrainingActionArea(
      kind: TrainingActionKind.start,
      startLabel: 'Start Wrist Stall',
      isLoading: _controller.connecting,
      onPressed: () => unawaited(_controller.startSession()),
    );
  }
}

class _CompletionState extends StatelessWidget {
  const _CompletionState({required this.controller});

  final TemplateScoredPracticeController controller;

  @override
  Widget build(BuildContext context) {
    final saved = controller.resultSaved;
    final saveError = controller.saveErrorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wrist Stall completed',
          key: const ValueKey('template-practice-success'),
          style: AppTheme.body.copyWith(
            color: AppColors.success,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          saved
              ? 'Classroom result saved. No global XP was awarded.'
              : saveError ?? 'Saving the classroom result…',
          key: ValueKey(
            saved
                ? 'template-practice-saved'
                : saveError == null
                ? 'template-practice-saving'
                : 'template-practice-save-error',
          ),
          style: AppTheme.caption.copyWith(
            color: saveError == null
                ? context.elixTextSecondary
                : AppColors.error,
          ),
        ),
      ],
    );
  }
}

class _HoldProgress extends StatelessWidget {
  const _HoldProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hold progress',
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ProgressBar(value: (progress.clamp(0.0, 1.0) * 100)),
      ],
    );
  }
}
