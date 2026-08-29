import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/constants/music_tracks.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/movement.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'just_dance/movement_rotation_controller.dart';
import 'just_dance/movement_setlist_dialog.dart';
import 'practice_run_phase.dart';
import 'submission_recording_controller.dart';
import 'widgets/movement_rotation_overlay.dart';
import 'widgets/submission_recording_panel.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_camera_workspace.dart';
import 'widgets/training_session_header.dart';
import 'widgets/training_session_panel.dart';
import 'widgets/training_status_row.dart';

/// Free-form live practice: camera streams with detection overlays but the
/// user is not locked to a movement and no scoring/feedback is shown.
class LivePracticeScreen extends StatefulWidget {
  const LivePracticeScreen({
    super.key,
    this.teacherCreatedAssignment,
    @visibleForTesting this.websocketService,
  });

  final TeacherCreatedAssignmentPractice? teacherCreatedAssignment;

  /// Test injection. Production constructs [WebSocketService] in [createState].
  @visibleForTesting
  final WebSocketService? websocketService;

  @override
  State<LivePracticeScreen> createState() => LivePracticeScreenState();
}

class TeacherCreatedAssignmentPractice {
  const TeacherCreatedAssignmentPractice({required this.assignment});

  final GroupAssignment assignment;

  String get title => assignment.displayTitle;
  String get instructions => assignment.displayInstructions ?? '';
  TrainingProp get prop => assignment.allowedProp ?? TrainingProp.bottle;
  static const backendMovementName = 'Free Practice';
}

@visibleForTesting
String livePracticePrepareFailureMessage(Object error) {
  if (error is CommandTimeoutException) {
    return 'Camera preparation timed out. Check the backend and try again.';
  }
  if (error is CommandDisconnectedException) {
    return 'Lost connection to the backend during camera preparation. Check the backend and try again.';
  }
  if (error is CommandAckMismatchException) {
    return 'Camera preparation was out of sync with the backend. Try starting again.';
  }
  if (error is StateError &&
      error.message.contains('command is already pending')) {
    return 'Camera preparation failed. Check the backend and try again.';
  }
  return 'Camera preparation failed. Check the backend and try again.';
}

class LivePracticeScreenState extends State<LivePracticeScreen> {
  late final WebSocketService _ws;
  late final bool _ownsWebSocket;
  final _music = PracticeMusicService();
  final _sfx = PracticeSfxService();
  final _run = PracticeRunController();
  late final MovementRotationController _rotation;

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  StreamSubscription<PreviewFrame>? _previewSub;
  final ValueNotifier<Uint8List?> _frameBytes = ValueNotifier<Uint8List?>(null);
  PracticeFeedback? _latestFeedback;
  bool _bottleDetected = false;
  bool _connecting = false;
  String? _sessionError;
  bool _leaving = false;
  bool _startInFlight = false;
  SubmissionRecordingController? _recording;

  /// True while a WebSocket prepare/activate command is awaiting ack.
  bool _commandInFlight = false;

  static const _wideBreakpoint = 1100.0;
  static const _panelWidth = 370.0;

  @override
  void initState() {
    super.initState();
    _ownsWebSocket = widget.websocketService == null;
    _ws = widget.websocketService ?? WebSocketService();
    final settings = context.read<SettingsService>();
    _rotation = MovementRotationController(
      movements: _resolveMovements(settings.justDanceMovementNames),
      intervalSeconds: settings.justDanceIntervalSeconds,
    );
    _ws.addListener(_onWsStateChanged);
    _run.addListener(_onRunChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _previewSub = _ws.previewStream.listen(_onPreviewFrame);
    if (widget.websocketService == null || !_ws.isConnected) {
      _connect();
    }
    _sfx.preload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final assignment = widget.teacherCreatedAssignment;
    if (_recording != null || assignment == null) return;
    final traineeId = context.read<AuthService>().currentUser?.id;
    if (traineeId == null) return;
    _recording = SubmissionRecordingController(
      websocket: _ws,
      classroom: context.read<ClassroomAssignmentRepository>(),
      submissions: context.read<AssignmentSubmissionRepository>(),
      assignment: assignment.assignment,
      traineeId: traineeId,
    )..addListener(_onRecordingChanged);
    unawaited(_recording!.refreshLatestSubmission());
  }

  void _onRecordingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recording?.removeListener(_onRecordingChanged);
    _recording?.dispose();
    _feedbackSub?.cancel();
    _previewSub?.cancel();
    _frameBytes.dispose();
    _music.dispose();
    _sfx.dispose();
    _rotation.dispose();
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    _run.dispose();
    if (_ownsWebSocket) {
      _ws.dispose();
    }
    super.dispose();
  }

  @visibleForTesting
  Future<void> debugStartSession() => _startSession();

  @visibleForTesting
  WebSocketService get debugWebSocket => _ws;

  /// Maps persisted setlist names to catalog [Movement]s, preserving the
  /// chosen rotation order and silently dropping any unknown names.
  List<Movement> _resolveMovements(List<String> names) {
    final byName = {
      for (final movement in movementCatalog) movement.name: movement,
    };
    return [
      for (final name in names)
        if (byName.containsKey(name)) byName[name]!,
    ];
  }

  Future<void> _openSetlistDialog() async {
    final saved = await MovementSetlistDialog.show(context);
    if (saved != true || !mounted) return;
    final settings = context.read<SettingsService>();
    _rotation.updateSetlist(
      _resolveMovements(settings.justDanceMovementNames),
      intervalSeconds: settings.justDanceIntervalSeconds,
    );
  }

  void _onWsStateChanged() {
    if (mounted) setState(() {});
  }

  void _onRunChanged() {
    if (mounted) setState(() {});
  }

  void _publishFrame(Uint8List? bytes) {
    if (bytes != null) {
      _frameBytes.value = bytes;
    }
  }

  void _clearFrame() {
    _frameBytes.value = null;
  }

  Future<void> _stopWebSocketSession() async {
    await _recording?.abandonLocalClip();
    try {
      await _ws.stopPracticeSession();
    } on CommandTimeoutException {
      // Expected when the backend is slow or unavailable.
    } on CommandAckMismatchException {
      // Stop ack did not match; session identity was already cleared.
    } on CommandDisconnectedException {
      // Expected during navigation or dispose.
    }
  }

  void _onPreviewFrame(PreviewFrame frame) {
    if (!mounted) return;
    if (!frame.hasJpeg) return;

    _publishFrame(frame.jpegBytes);

    if (_run.isPreparingCamera) {
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      final startCountdown = _run.onPreviewFeedback(
        hasJpegFrame: true,
        isFatal: false,
      );
      if (startCountdown) {
        unawaited(_startCountdownOverlay());
      }
      return;
    }

    if (_sessionError != null && (_run.isCountdown || _run.isTrainingActive)) {
      setState(() => _sessionError = null);
    }
  }

  void _onFeedback(PracticeFeedback feedback) {
    if (!mounted) return;

    if (feedback.isSessionFatal) {
      _music.stop();
      _sfx.stop();
      _rotation.stop();
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: feedback.feedback,
      );
      unawaited(_stopWebSocketSession());
      _clearFrame();
      setState(() {
        _sessionError = feedback.feedback;
        _latestFeedback = null;
      });
      return;
    }

    if (_run.isPreparingCamera) {
      _publishFrame(feedback.frameJpegBytes);
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      final startCountdown = _run.onPreviewFeedback(
        hasJpegFrame: feedback.frameJpegBytes != null,
        isFatal: false,
      );
      if (startCountdown) {
        unawaited(_startCountdownOverlay());
      }
      return;
    }

    if (_run.isCountdown) {
      _publishFrame(feedback.frameJpegBytes);
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      return;
    }

    if (!_run.isTrainingActive) return;

    _publishFrame(feedback.frameJpegBytes);
    final visibleChanged =
        _bottleDetected != feedback.bottleDetected ||
        !feedback.freePracticeVisibleEquals(_latestFeedback) ||
        _sessionError != null;
    if (visibleChanged) {
      setState(() {
        _sessionError = null;
        _bottleDetected = feedback.bottleDetected;
        _latestFeedback = feedback;
      });
    } else {
      _latestFeedback = feedback;
    }
  }

  Future<void> _startCountdownOverlay() async {
    final settings = context.read<SettingsService>();
    await _sfx.setVolume(settings.soundEnabled ? settings.musicVolume : 0.0);
    await _sfx.playCountdown();
    if (!mounted || !_run.isPreparingCamera) return;
    if (!_run.countdownTriggered) return;
    _run.enterCountdown();
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await _ws.connect();
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _startSession() async {
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    if (_startInFlight || _leaving) return;
    if (_commandInFlight) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    final assignment = widget.teacherCreatedAssignment;
    if (assignment != null) {
      final traineeId = context.read<AuthService>().currentUser?.id;
      if (traineeId == null) {
        setState(() {
          _sessionError = 'Sign in as a trainee to practice this assignment.';
        });
        return;
      }
    }

    _startInFlight = true;
    if (mounted) setState(() {});

    try {
      await _runStartSessionBody(assignment);
    } finally {
      _startInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _runStartSessionBody(
    TeacherCreatedAssignmentPractice? assignment,
  ) async {
    final settings = context.read<SettingsService>();
    if (assignment != null) {
      final traineeId = context.read<AuthService>().currentUser?.id;
      if (traineeId == null || _leaving || !mounted) return;
      final assignmentRepo = context.read<ClassroomAssignmentRepository>();
      try {
        final submission = await assignmentRepo
            .getOrCreateTeacherReviewSubmission(
              traineeId: traineeId,
              assignment: assignment.assignment,
            );
        if (submission.status != AssignmentAttemptStatus.inProgress) {
          if (!mounted) return;
          setState(() {
            _sessionError = submission.status == AssignmentAttemptStatus.checked
                ? 'This assignment has already been checked.'
                : 'This submission is waiting for your teacher to check it.';
          });
          return;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _sessionError =
              'Could not start this classroom assignment. Try again.';
        });
        return;
      }
    }

    if (!mounted || _leaving) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    _sessionError = null;
    _clearFrame();
    _latestFeedback = null;
    _bottleDetected = false;
    _ws.beginPracticeAttempt();
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    setState(() {});

    final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
    if (!mounted || _leaving) return;
    if (!_run.isPreparingCamera) return;

    // Internal Free Practice vision mode: camera + prop detection only.
    // Teacher-created titles must never be sent as prepare.movement.
    _commandInFlight = true;
    try {
      final ack = await _ws.sendPrepare(
        movement: TeacherCreatedAssignmentPractice.backendMovementName,
        difficulty: 'Easy',
        prop: assignment?.prop ?? TrainingProp.bottle,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
        allowSubmissionRecording: assignment != null,
      );
      if (!mounted || _leaving) return;
      if (!_run.isPreparingCamera) return;

      if (!ack.accepted) {
        final message =
            ack.message ?? ack.errorCode ?? 'Camera preparation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _clearFrame();
        });
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint(
        'LivePractice prepare failed: $error\n'
        'lastProtocolError=${_ws.lastProtocolError?.errorCode} '
        '${_ws.lastProtocolError?.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      final message = livePracticePrepareFailureMessage(error);
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError = message;
        _clearFrame();
      });
    } finally {
      _commandInFlight = false;
    }
  }

  void _onPreparationTimeout() {
    if (!mounted) return;
    unawaited(_stopWebSocketSession());
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    setState(() {
      _sessionError = _run.errorMessage;
      _clearFrame();
    });
  }

  Future<void> _beginSessionAfterCountdown() async {
    if (!mounted) return;
    if (!_run.isCountdown) return;
    if (_commandInFlight) return;
    if (!_ws.isConnected) {
      _run.cancelToIdle();
      _connect();
      return;
    }

    _commandInFlight = true;
    try {
      final ack = await _ws.sendActivate();
      if (!mounted) return;
      if (!_run.isCountdown) return;

      if (!ack.accepted) {
        final message =
            ack.message ?? ack.errorCode ?? 'Session activation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _clearFrame();
        });
        return;
      }

      _run.enterActive();
      _sfx.stop();
      final settings = context.read<SettingsService>();
      final track = resolveTrack(settings.selectedMusicTrackId);
      final volume = settings.soundEnabled ? settings.musicVolume : 0.0;
      await _music.setVolume(volume);
      _music.start(track);
      if (widget.teacherCreatedAssignment == null) {
        _rotation.start();
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      final message = error is CommandTimeoutException
          ? 'Session activation timed out. Try starting again.'
          : 'Session activation failed. Try starting again.';
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError = message;
        _clearFrame();
      });
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> _cancelPreActive() async {
    await _stopWebSocketSession();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    _rotation.stop();
    if (mounted) {
      setState(() {
        _clearFrame();
        _latestFeedback = null;
        _bottleDetected = false;
        _sessionError = null;
      });
    }
  }

  Future<void> _stopSession() async {
    if (_run.isPreparingCamera || _run.isCountdown || _run.isError) {
      await _cancelPreActive();
      return;
    }

    await _stopWebSocketSession();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    _rotation.stop();
    if (mounted) {
      setState(() {
        _clearFrame();
        _latestFeedback = null;
        _bottleDetected = false;
        _sessionError = null;
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final router = GoRouter.of(context);
    await _feedbackSub?.cancel();
    _feedbackSub = null;
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    await _stopWebSocketSession();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    _rotation.stop();
    router.go(
      widget.teacherCreatedAssignment == null
          ? AppRoutePaths.dashboard
          : AppRoutePaths.assignedMovements,
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  TrainingActionKind _actionKind() {
    return switch (_run.phase) {
      PracticeRunPhase.active => TrainingActionKind.finish,
      PracticeRunPhase.preparingCamera ||
      PracticeRunPhase.readiness ||
      PracticeRunPhase.countdown => TrainingActionKind.cancel,
      PracticeRunPhase.error => TrainingActionKind.retry,
      PracticeRunPhase.idle ||
      PracticeRunPhase.completed => TrainingActionKind.start,
    };
  }

  TrainingSessionPhase _panelPhase() {
    return switch (_run.phase) {
      PracticeRunPhase.idle => TrainingSessionPhase.ready,
      PracticeRunPhase.preparingCamera => TrainingSessionPhase.preparingCamera,
      PracticeRunPhase.readiness => TrainingSessionPhase.preparingCamera,
      PracticeRunPhase.countdown => TrainingSessionPhase.getReady,
      PracticeRunPhase.active => TrainingSessionPhase.inProgress,
      PracticeRunPhase.completed => TrainingSessionPhase.completed,
      PracticeRunPhase.error => TrainingSessionPhase.cameraError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isTrainingActive = _run.isTrainingActive;
    final isCameraLive = _run.isCameraSessionLive;
    final hasConnectionError =
        _ws.connectionState == WebSocketConnectionState.error;
    final actionKind = _actionKind();

    return ElixScaffoldPage(
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              final assignment = widget.teacherCreatedAssignment;
              final header = TrainingSessionHeader(
                onBack: _leave,
                title: assignment?.title ?? 'Playground',
                statusPill: assignment == null
                    ? 'NO SCORING'
                    : 'TEACHER REVIEWED',
                statusPillColor: AppColors.primarySoft,
                instruction: assignment == null
                    ? 'Follow the set, or freestyle — nothing is scored or '
                          'locked.'
                    : (assignment.instructions.isEmpty
                          ? 'Practice this teacher-created movement. ELIXR does not score it automatically.'
                          : assignment.instructions),
                connectionState: _ws.connectionState,
                connecting: _connecting,
                wideLayout: wide,
                trailing: assignment == null
                    ? Button(
                        onPressed: _openSetlistDialog,
                        child: const Text('Build Your Set'),
                      )
                    : null,
              );
              final camera = TrainingCameraWorkspace(
                frameListenable: _frameBytes,
                mirrored: context.watch<SettingsService>().cameraMirrored,
                connectionState: _ws.connectionState,
                connecting: _connecting,
                isSessionActive: isCameraLive && !_run.isPreparingCamera,
                isPreparingCamera: _run.isPreparingCamera,
                errorMessage: _ws.errorMessage,
                sessionError: _sessionError ?? _run.errorMessage,
                onRetry: _connect,
                countdownActive: _run.isCountdown,
                onCountdownComplete: _beginSessionAfterCountdown,
                overlayFeedback: isTrainingActive
                    ? null
                    : (isCameraLive ? _latestFeedback : null),
                showFeedbackMessage: false,
                overlays: isTrainingActive && assignment == null
                    ? MovementRotationOverlay(controller: _rotation)
                    : null,
                statusItems: [
                  if (isTrainingActive)
                    TrainingCameraStatusItem(
                      label: _bottleDetected
                          ? 'Bottle detected'
                          : 'Searching for bottle',
                      color: _bottleDetected
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                ],
              );

              final panel = TrainingSessionPanel(
                phase: _panelPhase(),
                metrics: LivePracticeElapsedMetric(
                  elapsedDisplay: _formatDuration(_run.elapsedSeconds),
                ),
                statusContent: TrainingStatusRow(
                  detection: resolveDetectionStatus(
                    sessionActive: isTrainingActive,
                    bottleDetected: isTrainingActive ? _bottleDetected : null,
                  ),
                ),
                notice: Text(
                  assignment == null
                      ? 'No score or session history will be saved.'
                      : 'Teacher-created practice is not scored and does not award XP.',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                supportingContent: assignment != null && _recording != null
                    ? SubmissionRecordingPanel(
                        controller: _recording!,
                        cameraReady: isTrainingActive,
                      )
                    : null,
                compactStatusNote: (_sessionError ?? _run.errorMessage) != null
                    ? Text(
                        _sessionError ?? _run.errorMessage!,
                        style: AppTheme.bodySecondary.copyWith(
                          color: AppColors.error,
                        ),
                      )
                    : (hasConnectionError
                          ? Text(
                              _ws.errorMessage ??
                                  'Backend offline. Start the Python server first.',
                              style: AppTheme.bodySecondary.copyWith(
                                color: AppColors.error,
                              ),
                            )
                          : null),
                actionArea: TrainingActionArea(
                  kind: actionKind,
                  startLabel: assignment == null
                      ? 'Start Playground'
                      : 'Start assignment practice',
                  onPressed: switch (actionKind) {
                    TrainingActionKind.finish => _stopSession,
                    TrainingActionKind.cancel => _cancelPreActive,
                    TrainingActionKind.retry || TrainingActionKind.start =>
                      _ws.isConnected ? _startSession : _connect,
                  },
                  isLoading: _connecting || _startInFlight || _commandInFlight,
                ),
              );

              if (wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: camera),
                          const SizedBox(width: AppSpacing.lg),
                          SizedBox(width: _panelWidth, child: panel),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final cameraHeight = math.max(
                280.0,
                constraints.maxHeight * 0.42,
              );
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    SizedBox(height: cameraHeight, child: camera),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(height: 320, child: panel),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
