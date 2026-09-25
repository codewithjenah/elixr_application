import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/gamification_rules.dart';
import '../../core/progression/progression_access.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elix_toast.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/classroom_exceptions.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/recognition_event.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/custom_movement.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../data/repositories/firebase_custom_movement_repository.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../services/auth_service.dart';
import '../../services/camera_device_service.dart';
import '../../services/app_background_music_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/settings_service.dart';
import '../../services/startup_diagnostics.dart';
import '../../services/trainee_progression_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../../services/websocket_service.dart';
import '../settings/widgets/camera_source_preference.dart';
import 'camera_recovery_presentation.dart';
import 'freestyle/freestyle_models.dart';
import 'freestyle/freestyle_session_controller.dart';
import 'practice_run_phase.dart';
import 'submission_recording_controller.dart';
import 'training_quit_guard.dart';
import 'widgets/freestyle_overlay.dart';
import 'widgets/freestyle_summary_sheet.dart';
import 'widgets/readiness_checklist_panel.dart';
import 'widgets/submission_recording_panel.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_arena_layout.dart';
import 'widgets/training_camera_workspace.dart';
import 'widgets/training_session_header.dart';
import 'widgets/training_session_panel.dart';
import 'widgets/training_status_row.dart';

/// Freestyle Playground and teacher-created assignment practice share this
/// camera workspace. Playground is an unscored observation session.
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

  static const cameraAspectRatio = TrainingArenaLayout.cameraAspectRatio;

  @override
  State<LivePracticeScreen> createState() => LivePracticeScreenState();
}

class TeacherCreatedAssignmentPractice {
  const TeacherCreatedAssignmentPractice({
    required this.assignment,
    this.reservedActivityAttempt,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt? reservedActivityAttempt;

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

/// Keeps assignment-start failures actionable without exposing Firestore rule
/// details or classroom data in the UI.
@visibleForTesting
String livePracticeAssignmentStartFailureMessage(Object error) {
  if (error is ClassroomException) {
    return switch (error.code) {
      ClassroomError.deadlinePassed =>
        'This assignment is past its deadline and can no longer be started.',
      ClassroomError.inactive =>
        'This classroom assignment is no longer active.',
      ClassroomError.forbidden =>
        'You no longer have permission to start this classroom assignment.',
      ClassroomError.malformed || ClassroomError.identityMismatch =>
        'This classroom assignment has invalid data. Ask your teacher to review it.',
      ClassroomError.invalidState =>
        'This assignment cannot be started in its current submission state.',
      _ => 'Could not start this classroom assignment. Try again.',
    };
  }
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'You no longer have permission to start this classroom assignment.';
  }
  return 'Could not start this classroom assignment. Try again.';
}

bool _isTerminalAssignmentStartFailure(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return true;
  }
  if (error is! ClassroomException) return false;
  if (error.serverCode == 'attempts_exhausted' ||
      error.serverCode == 'graded' ||
      error.serverCode == 'deadline_passed' ||
      error.serverCode == 'forbidden') {
    return true;
  }
  return switch (error.code) {
    ClassroomError.deadlinePassed ||
    ClassroomError.inactive ||
    ClassroomError.forbidden ||
    ClassroomError.malformed ||
    ClassroomError.identityMismatch ||
    ClassroomError.invalidState ||
    ClassroomError.attemptLimitConflict => true,
    _ => false,
  };
}

class LivePracticeScreenState extends State<LivePracticeScreen> {
  late final WebSocketService _ws;
  late final bool _ownsWebSocket;
  late final PracticeMusicService _music;
  bool _musicInitialized = false;
  final _sfx = PracticeSfxService();
  final _run = PracticeRunController();
  late final FreestyleSessionController _freestyle;
  StreamSubscription<PracticeFeedback>? _feedbackSub;
  StreamSubscription<PreviewFrame>? _previewSub;
  StreamSubscription<RecognitionEvent>? _recognitionSub;
  final ValueNotifier<Uint8List?> _frameBytes = ValueNotifier<Uint8List?>(null);
  PracticeFeedback? _latestFeedback;
  bool _bottleDetected = false;
  bool _connecting = false;
  String? _sessionError;
  String? _sessionErrorCode;
  String? _startError;
  bool _assignmentStartBlocked = false;
  final CameraFallbackWarningTracker _fallbackWarningTracker =
      CameraFallbackWarningTracker();
  bool _leaving = false;
  bool _quitDialogOpen = false;
  bool _stopInFlight = false;
  bool _startInFlight = false;
  bool _choosingCamera = false;
  int _startGeneration = 0;
  bool _activityAutoStartRequested = false;
  bool _cameraSelectionBusy = false;
  bool _recordingAutoStartRequested = false;
  SubmissionRecordingController? _recording;
  Future<void>? _webSocketStopFuture;

  /// True while a WebSocket prepare/activate command is awaiting ack.
  bool _commandInFlight = false;
  bool _freestyleActivationInFlight = false;
  bool _freestyleSummaryOpen = false;
  TrainingProp _endlessProp = TrainingProp.bottle;
  int _requestedTargetGeneration = 0;
  late final CustomMovementRepository _customMovementRepository =
      FirebaseCustomMovementRepository();
  List<EndlessTarget> _endlessPoolSnapshot = const [];
  FreestyleSessionPhase _lastRenderedFreestylePhase =
      FreestyleSessionPhase.idle;

  static const _wideBreakpoint = AppSpacing.practiceDesktopBreakpoint;
  static const _compactBreakpoint = AppSpacing.practiceCompactBreakpoint;
  static const _maxContentWidth = AppSpacing.practiceMaxContentWidth;

  @override
  void initState() {
    super.initState();
    _ownsWebSocket = widget.websocketService == null;
    _ws = widget.websocketService ?? WebSocketService();
    _freestyle = FreestyleSessionController();
    _freestyle.addListener(_onFreestyleChanged);
    _ws.addListener(_onWsStateChanged);
    _run.addListener(_onRunChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _previewSub = _ws.previewStream.listen(_onPreviewFrame);
    _recognitionSub = _ws.recognitionStream.listen(_onRecognitionEvent);
    if (widget.websocketService == null || !_ws.isConnected) {
      _connect();
    }
    _sfx.preload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_musicInitialized) {
      _musicInitialized = true;
      final settings = context.read<SettingsService>();
      _music = PracticeMusicService(
        settings: settings,
        appBackgroundMusic: context.read<AppBackgroundMusicService?>(),
      );
      _sfx.bindSettings(settings);
    }
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
      onRecordingModeStarted: _run.pauseElapsed,
      onRecordingModeEnded: _run.resumeElapsed,
    )..addListener(_onRecordingChanged);
    final reserved = assignment.reservedActivityAttempt;
    if (reserved != null) {
      _recording!.latestSubmission = reserved;
    }
    unawaited(_recording!.refreshLatestSubmission());
  }

  void _onRecordingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recording?.removeListener(_onRecordingChanged);
    _run.removeListener(_onRunChanged);
    unawaited(_recording?.releaseActivityAttempt() ?? Future<void>.value());
    _recording?.dispose();
    _feedbackSub?.cancel();
    _previewSub?.cancel();
    _recognitionSub?.cancel();
    _frameBytes.dispose();
    if (_musicInitialized) _music.dispose();
    _sfx.dispose();
    _freestyle.removeListener(_onFreestyleChanged);
    _freestyle.dispose();
    _ws.removeListener(_onWsStateChanged);
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

  @visibleForTesting
  FreestyleSessionController get debugFreestyle => _freestyle;

  @visibleForTesting
  PracticeRunController get debugRun => _run;

  @visibleForTesting
  Future<void> debugConfirmActivityReadiness() => _confirmActivityReadiness();

  @visibleForTesting
  Future<void> debugBeginSessionAfterCountdown() =>
      _beginSessionAfterCountdown();

  @visibleForTesting
  SubmissionRecordingController? get debugRecording => _recording;

  List<({String movement, TrainingProp prop})> _freestyleAllowlist() {
    final progression = context.read<TraineeProgressionService>();
    final tutorials = context.read<TutorialProgressService>();
    return [
      for (final variant in personalReadyVariants(
        currentLevel: progression.currentLevelOrNull,
        tutorialCompleted: (candidate) => tutorials.isInitialized
            ? tutorials.hasCompletedLesson(
                candidate.movementName,
                candidate.trainingProp,
              )
            : false,
      ))
        (movement: variant.movementName, prop: variant.trainingProp),
    ];
  }

  Future<List<EndlessTarget>> _endlessPool() async {
    final official = endlessPoolFromReady(_freestyleAllowlist(), _endlessProp);
    final ownerUid = context.read<AuthService>().currentUser?.id;
    if (ownerUid == null || ownerUid.isEmpty) return official;
    try {
      final roots = await _customMovementRepository
          .watchOwnedMovements(ownerUid: ownerUid)
          .first
          .timeout(const Duration(seconds: 5));
      final eligible = roots.where(
        (movement) =>
            movement.isOwnedBy(ownerUid) &&
            movement.isActive &&
            movement.propType == _endlessProp &&
            movement.activeRevisionId.isNotEmpty,
      );
      final revisions = (await Future.wait(
        eligible.map((movement) async {
          try {
            return await _customMovementRepository
                .getRevision(
                  movementId: movement.id,
                  revisionId: movement.activeRevisionId,
                )
                .timeout(const Duration(seconds: 5));
          } on Object catch (error) {
            debugPrint(
              'Endless excluded custom movement ${movement.id}: $error',
            );
            return null;
          }
        }),
      )).whereType<CustomMovementRevision>().toList();
      final custom = eligibleCustomEndlessTargets(
        movements: roots,
        revisions: revisions,
        ownerUid: ownerUid,
        selectedProp: _endlessProp,
      );
      return [
        ...official,
        ...custom,
        if (custom.isNotEmpty && !official.any((target) => target.isTossCatch))
          EndlessTarget(
            movement: 'Toss & Catch',
            prop: _endlessProp,
            difficulty: 'Medium',
            kind: EndlessTargetKind.tossCatch,
          ),
      ];
    } on Object catch (error) {
      debugPrint('Endless custom movement loading failed: $error');
      return official;
    }
  }

  bool get _isPlayground => widget.teacherCreatedAssignment == null;

  void _onFreestyleChanged() {
    if (!mounted || !_isPlayground) return;
    if (_freestyle.isPaused) {
      _run.pauseElapsed();
    } else {
      _run.resumeElapsed();
    }
    if (_freestyle.phase == FreestyleSessionPhase.active &&
        _freestyle.targetGeneration > _requestedTargetGeneration) {
      unawaited(_setEndlessTarget(_freestyle.generation));
    }
    if (_freestyle.phase != _lastRenderedFreestylePhase) {
      _lastRenderedFreestylePhase = _freestyle.phase;
      setState(() {});
    }
  }

  void _onWsStateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_isPlayground &&
        !_ws.isConnected &&
        _freestyle.phase != FreestyleSessionPhase.idle &&
        !_freestyle.isComplete) {
      _freestyle.cancelToIdle();
      _run.cancelToIdle();
      unawaited(_music.stop());
      unawaited(_sfx.stop());
      setState(
        () => _sessionError =
            'Backend connection lost. Restart Endless Mode to continue.',
      );
      return;
    }
    final isActivity =
        widget.teacherCreatedAssignment?.assignment.activityAssessment != null;
    if (isActivity &&
        !_activityAutoStartRequested &&
        _ws.isConnected &&
        _run.phase == PracticeRunPhase.idle) {
      _activityAutoStartRequested = true;
      unawaited(_startSession());
    }
  }

  void _onRunChanged() {
    if (!mounted) return;
    setState(() {});
    if (_run.consumeAutoStartDue()) {
      _onActivityReadinessStable();
    }
  }

  void _publishFrame(Uint8List? bytes) {
    if (bytes != null) {
      _frameBytes.value = bytes;
    }
  }

  void _clearFrame() {
    _frameBytes.value = null;
  }

  Future<void> _stopWebSocketSession() {
    final pending = _webSocketStopFuture;
    if (pending != null) return pending;

    late final Future<void> tracked;
    tracked = _performWebSocketStop().whenComplete(() {
      if (identical(_webSocketStopFuture, tracked)) {
        _webSocketStopFuture = null;
      }
    });
    _webSocketStopFuture = tracked;
    return tracked;
  }

  Future<void> _performWebSocketStop() async {
    await _recording?.abandonLocalClip();
    await _recording?.cancelActivityAttempt();
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
        if (_isPlayground) {
          _onFreestylePreviewReady();
        } else if (_isTeacherActivityV2) {
          _run.enterReadiness();
          unawaited(_beginActivityReadiness());
        } else {
          unawaited(_startCountdownOverlay());
        }
      }
      return;
    }

    if (_sessionError != null && (_run.isCountdown || _run.isTrainingActive)) {
      setState(() => _sessionError = null);
    }
  }

  void _onRecognitionEvent(RecognitionEvent event) {
    if (!mounted || !_isPlayground) return;
    _freestyle.applyEvent(_freestyle.generation, event);
  }

  void _onFreestylePreviewReady() {
    final generation = _freestyle.generation;
    if (!_freestyle.markPrepared(generation)) return;
    unawaited(_activateFreestyle(generation));
  }

  void _onFeedback(PracticeFeedback feedback) {
    if (!mounted) return;

    if (feedback.isSessionFatal) {
      _music.stop();
      _sfx.stop();
      if (_isPlayground) _freestyle.cancelToIdle();
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: feedback.feedback,
      );
      unawaited(_stopWebSocketSession());
      _clearFrame();
      setState(() {
        _sessionError = feedback.feedback;
        _sessionErrorCode = feedback.errorCode;
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
        if (_isPlayground) {
          _onFreestylePreviewReady();
        } else if (_isTeacherActivityV2) {
          _run.enterReadiness();
          unawaited(_beginActivityReadiness());
        } else {
          unawaited(_startCountdownOverlay());
        }
      }
      return;
    }

    if (_run.isReadiness) {
      _publishFrame(feedback.frameJpegBytes);
      if (!_run.readinessFrozen) {
        _run.applyReadinessFeedback(
          items: feedback.readinessItems ?? const [],
          complete: feedback.readinessComplete ?? false,
          stable: feedback.readinessStable ?? false,
          progress: feedback.readinessStableProgress ?? 0,
        );
      }
      return;
    }

    if (_run.isCountdown) {
      _publishFrame(feedback.frameJpegBytes);
      if (_isPlayground) {
        _freestyle.applyLiveState(
          generation: _freestyle.generation,
          state: feedback.recognitionState,
          recognizedDisplay: feedback.recognizedDisplay,
          detectedProp: feedback.detectedPropType,
        );
      }
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      // Accepted confirm_readiness freezes the approved setup for this
      // attempt. Late readying fields can race with countdown feedback and
      // must not demote the run or release its reserved Activity attempt.
      return;
    }

    if (!_run.isTrainingActive) return;

    _publishFrame(feedback.frameJpegBytes);
    if (_isPlayground) {
      _freestyle.applyLiveState(
        generation: _freestyle.generation,
        state: feedback.recognitionState,
        recognizedDisplay: feedback.recognizedDisplay,
        detectedProp: feedback.detectedPropType,
      );
    }
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
    await _sfx.playCountdown(
      volume: settings.soundEnabled ? settings.musicVolume : 0.0,
    );
    if (!mounted || !_run.isPreparingCamera) return;
    if (!_run.countdownTriggered) return;
    _run.enterCountdown();
  }

  bool get _isTeacherActivityV2 =>
      widget.teacherCreatedAssignment?.assignment.activityAssessment != null;

  Future<void> _beginActivityReadiness() async {
    final generation = _run.lifecycleGeneration;
    try {
      final ack = await _ws.sendBeginReadiness();
      if (!mounted || generation != _run.lifecycleGeneration) return;
      if (!ack.accepted) {
        throw StateError(
          ack.message ?? ack.errorCode ?? 'Readiness check was rejected.',
        );
      }
    } catch (error) {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage:
            'Readiness check failed. Check the backend and try again.',
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError =
            'Readiness check failed. Check the backend and try again.';
      });
    }
  }

  void _onActivityReadinessStable() {
    if (!_isTeacherActivityV2 || _commandInFlight) {
      return;
    }
    final stable = _run.readiness.stable || (_run.readinessStable == true);
    if (!_run.requestStartPractice(readinessStable: stable)) return;
    unawaited(_confirmActivityReadiness());
  }

  Future<void> _confirmActivityReadiness() async {
    final generation = _run.lifecycleGeneration;
    _commandInFlight = true;
    try {
      final ack = await _ws.sendConfirmReadiness();
      if (!mounted || generation != _run.lifecycleGeneration) return;
      if (!ack.accepted) {
        _run.onConfirmReadinessRejected(
          errorCode: ack.errorCode,
          message: ack.message,
        );
        return;
      }
      if (!_run.onConfirmReadinessAccepted()) return;
      final settings = context.read<SettingsService>();
      await _sfx.playCountdown(
        volume: settings.soundEnabled ? settings.musicVolume : 0.0,
      );
    } on CommandTimeoutException {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      _run.onConfirmReadinessRejected(
        errorCode: 'command_timeout',
        message:
            'Readiness confirmation timed out. Keep the required setup visible to try again.',
      );
    } on CommandDisconnectedException {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      _failActivityReadinessSession(
        errorCode: 'connection_lost',
        message:
            'Lost connection to the camera service during readiness confirmation.',
      );
    } on CommandAckMismatchException catch (error) {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      _failActivityReadinessSession(
        errorCode: error.errorCode,
        message:
            'Readiness confirmation was out of sync with the camera service.',
      );
    } catch (_) {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      if (!_ws.isConnected) {
        _failActivityReadinessSession(
          errorCode: 'connection_lost',
          message:
              'Lost connection to the camera service during readiness confirmation.',
        );
        return;
      }
      _run.onConfirmReadinessRejected(
        message:
            'Readiness confirmation failed. Keep the required setup visible.',
      );
    } finally {
      _commandInFlight = false;
      if (mounted) setState(() {});
    }
  }

  void _failActivityReadinessSession({
    required String errorCode,
    required String message,
  }) {
    _run.onPreviewFeedback(
      hasJpegFrame: false,
      isFatal: true,
      fatalMessage: message,
    );
    unawaited(_stopWebSocketSession());
    _clearFrame();
    setState(() {
      _sessionErrorCode = errorCode;
      _sessionError = message;
      _latestFeedback = null;
    });
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _ws.connect();
    } catch (error, stackTrace) {
      debugPrint('Practice connection failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _sessionError =
              'Could not connect to the camera service. Check that it is running, then try again.';
        });
      }
    } finally {
      _connecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resetInterruptedAttempt() async {
    _startGeneration++;
    _commandInFlight = false;
    _startInFlight = false;
    _freestyleActivationInFlight = false;
    _freestyle.cancelToIdle();
    _run.cancelToIdle();
    await _stopWebSocketSession();
    await _music.stop();
    await _sfx.stop();
    if (!mounted) return;
    setState(() {
      _clearFrame();
      _latestFeedback = null;
      _bottleDetected = false;
      _sessionError = null;
      _sessionErrorCode = null;
    });
  }

  Future<void> _retrySession() async {
    if (_leaving || _connecting) return;
    await _resetInterruptedAttempt();
    if (!mounted || _leaving) return;
    await _connect();
    if (!mounted || !_ws.isConnected) return;
    await _startSession();
  }

  Future<void> _chooseCamera() async {
    if (_choosingCamera || _leaving) return;
    _choosingCamera = true;
    if (mounted) setState(() {});
    try {
      // An Activity auto-starts on connection. Keep it stopped while the user
      // makes a new choice, then resume only from the explicit Start action.
      _activityAutoStartRequested = true;
      if (_isTeacherActivityV2 &&
          (_run.isPreparingCamera || _run.isReadiness)) {
        _startGeneration++;
        _commandInFlight = false;
        _startInFlight = false;
        _run.cancelToIdle();
        try {
          await _ws.stopPracticeSession();
        } catch (_) {
          // Closing the socket below still tears down the backend session.
        }
        if (!mounted || _leaving) return;
        setState(() {
          _clearFrame();
          _latestFeedback = null;
          _bottleDetected = false;
          _sessionError = null;
          _sessionErrorCode = null;
        });
      } else {
        await _resetInterruptedAttempt();
      }
      if (!mounted || _leaving) return;
      // Closing the owning socket also releases a backend session if its stop
      // acknowledgment was lost while preparation was being cancelled.
      await _ws.disconnect();
      if (!mounted || _leaving) return;
      await _connect();
      if (!mounted || _leaving) return;
      await context.read<CameraDeviceService>().refresh(forceRefresh: true);
    } finally {
      _choosingCamera = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _beginSelectedCameraSession() async {
    if (_cameraSelectionBusy || _choosingCamera) return;
    if (!_ws.isConnected) {
      await _connect();
      if (!mounted || !_ws.isConnected) return;
    }
    await _startSession();
  }

  Future<void> _startSession() async {
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    if (_startInFlight ||
        _leaving ||
        _stopInFlight ||
        _webSocketStopFuture != null ||
        _freestyleSummaryOpen) {
      return;
    }
    if (_commandInFlight || _cameraSelectionBusy || _choosingCamera) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    if (widget.teacherCreatedAssignment == null) {
      final progression = context.read<TraineeProgressionService>();
      final tutorials = context.read<TutorialProgressService>();
      if (!progression.isReady || !tutorials.isInitialized) {
        setState(() {
          _startError =
              'Progression is still loading. Wait a moment, then start Freestyle.';
        });
        return;
      }
    }

    final assignment = widget.teacherCreatedAssignment;
    if (assignment != null) {
      final traineeId = context.read<AuthService>().currentUser?.id;
      if (traineeId == null) {
        setState(() {
          _startError = 'Sign in as a trainee to practice this assignment.';
          _assignmentStartBlocked = true;
        });
        return;
      }
    }

    final startGeneration = ++_startGeneration;
    _startInFlight = true;
    if (mounted) setState(() {});

    try {
      await _runStartSessionBody(assignment, startGeneration);
    } finally {
      if (startGeneration == _startGeneration) {
        _startInFlight = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _runStartSessionBody(
    TeacherCreatedAssignmentPractice? assignment,
    int startGeneration,
  ) async {
    final settings = context.read<SettingsService>();
    if (assignment != null) {
      final traineeId = context.read<AuthService>().currentUser?.id;
      if (traineeId == null || _leaving || !mounted) return;
      final assignmentRepo = context.read<ClassroomAssignmentRepository>();
      try {
        final submission = assignment.assignment.activityAssessment == null
            ? await assignmentRepo.getOrCreateTeacherReviewSubmission(
                traineeId: traineeId,
                assignment: assignment.assignment,
              )
            : (await assignmentRepo
                      .watchAttemptsForTrainee(traineeId: traineeId)
                      .first)
                  .where(
                    (attempt) =>
                        attempt.assignmentId == assignment.assignment.id &&
                        attempt.activityAssessmentSnapshot != null,
                  )
                  .fold<AssignmentAttempt?>(
                    null,
                    (latest, attempt) =>
                        latest == null ||
                            (attempt.createdAt ?? DateTime(1970)).isAfter(
                              latest.createdAt ?? DateTime(1970),
                            )
                        ? attempt
                        : latest,
                  );
        if (!mounted || _leaving || startGeneration != _startGeneration) return;
        if (submission == null) {
          throw const ClassroomException(
            ClassroomError.invalidState,
            'No reserved Activity attempt is available.',
          );
        }
        if (submission.status != AssignmentAttemptStatus.inProgress) {
          if (!mounted) return;
          setState(() {
            _startError = submission.status == AssignmentAttemptStatus.checked
                ? 'This assignment has already been checked.'
                : 'This submission is waiting for your teacher to check it.';
            _assignmentStartBlocked = true;
          });
          return;
        }
      } catch (error, stackTrace) {
        debugPrint(
          'LivePractice assignment start failed: '
          'assignment=${assignment.assignment.id} trainee=$traineeId '
          'error_type=${error.runtimeType} error=$error',
        );
        if (error is FirebaseException && error.code == 'permission-denied') {
          debugPrint(
            'LivePractice assignment start permission-denied: verify the '
            'trainee has an approved membership and the assignment is active; '
            'if both are valid, deploy the current Firestore rules that allow '
            'canonical teacher_review_submission in_progress creation.',
          );
        }
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted || startGeneration != _startGeneration) return;
        setState(() {
          _startError = livePracticeAssignmentStartFailureMessage(error);
          _assignmentStartBlocked = _isTerminalAssignmentStartFailure(error);
        });
        return;
      }
    }

    if (!mounted || _leaving || startGeneration != _startGeneration) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    _startError = null;
    _assignmentStartBlocked = false;
    _sessionError = null;
    _clearFrame();
    _latestFeedback = null;
    _bottleDetected = false;
    if (assignment == null) {
      final pool = await _endlessPool();
      if (!mounted || _leaving || startGeneration != _startGeneration) return;
      if (pool.isEmpty) {
        setState(
          () => _startError =
              'Complete a tutorial or add an active custom ${_endlessProp.displayLabel} movement before starting.',
        );
        return;
      }
      _requestedTargetGeneration = 0;
      _endlessPoolSnapshot = pool;
      final generation = _freestyle.start(pool: pool);
      if (generation == null) {
        setState(() {
          _sessionError = 'Could not start Endless Mode. Try again.';
        });
        return;
      }
      await _prepareFreestyle(generation, settings);
      return;
    }
    _ws.beginPracticeAttempt();
    _recordingAutoStartRequested = false;
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    final runGeneration = _run.lifecycleGeneration;
    setState(() {});

    final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
    if (!mounted || _leaving || runGeneration != _run.lifecycleGeneration) {
      return;
    }
    if (!_run.isPreparingCamera) return;

    _ws.startupDiagnostics.annotate(
      sessionMode: 'guided',
      movement: TeacherCreatedAssignmentPractice.backendMovementName,
      camera: cameraDiagnosticIdentity(
        deviceId: cameraDeviceId,
        identityStable:
            cameraDeviceId != null && !cameraDeviceId.startsWith('opencv:'),
      ),
    );

    // Internal Free Practice vision mode: camera + prop detection only.
    // Teacher-created titles must never be sent as prepare.movement.
    _commandInFlight = true;
    try {
      final ack = await _ws.sendPrepare(
        movement: TeacherCreatedAssignmentPractice.backendMovementName,
        difficulty: 'Easy',
        prop: assignment.prop,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
        allowSubmissionRecording: true,
        readinessSpec: assignment.assignment.activityAssessment?.readiness,
      );
      if (!mounted || _leaving || runGeneration != _run.lifecycleGeneration) {
        return;
      }
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
          _sessionErrorCode = ack.errorCode;
          _clearFrame();
        });
      } else {
        _showCameraFallbackWarning(ack);
      }
    } catch (error, stackTrace) {
      if (!mounted || runGeneration != _run.lifecycleGeneration) return;
      if (!_run.isPreparingCamera) return;
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
        _sessionErrorCode = error is CommandTimeoutException
            ? 'prepare_timeout'
            : null;
        _clearFrame();
      });
    } finally {
      if (runGeneration == _run.lifecycleGeneration) _commandInFlight = false;
    }
  }

  void _onPreparationTimeout() {
    if (!mounted) return;
    if (_isPlayground) _freestyle.cancelToIdle();
    unawaited(_stopWebSocketSession());
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    setState(() {
      _sessionError = _run.errorMessage;
      _sessionErrorCode = 'prepare_timeout';
      _clearFrame();
    });
  }

  Future<void> _prepareFreestyle(
    int generation,
    SettingsService settings,
  ) async {
    if (!mounted || _leaving || generation != _freestyle.generation) return;
    _ws.beginPracticeAttempt();
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    final runGeneration = _run.lifecycleGeneration;
    final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
    if (!mounted ||
        _leaving ||
        generation != _freestyle.generation ||
        runGeneration != _run.lifecycleGeneration ||
        !_run.isPreparingCamera) {
      return;
    }
    _ws.startupDiagnostics.annotate(
      sessionMode: 'freestyle',
      movement: TeacherCreatedAssignmentPractice.backendMovementName,
      camera: cameraDiagnosticIdentity(
        deviceId: cameraDeviceId,
        identityStable:
            cameraDeviceId != null && !cameraDeviceId.startsWith('opencv:'),
      ),
    );
    _commandInFlight = true;
    try {
      final ack = await _ws.sendPrepare(
        movement: TeacherCreatedAssignmentPractice.backendMovementName,
        difficulty: 'Easy',
        prop: _endlessProp,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
        sessionMode: 'endless',
        allowedMovements: [
          for (final target in _endlessPoolSnapshot)
            if (target.kind == EndlessTargetKind.movement)
              (movement: target.movement, prop: target.prop),
        ],
      );
      if (!mounted ||
          generation != _freestyle.generation ||
          runGeneration != _run.lifecycleGeneration ||
          !_run.isPreparingCamera) {
        return;
      }
      if (!ack.accepted) {
        final message =
            ack.message ??
            ack.errorCode ??
            'Freestyle preparation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        _freestyle.cancelToIdle();
        unawaited(_stopWebSocketSession());
        setState(() => _sessionError = message);
      } else {
        _showCameraFallbackWarning(ack);
      }
    } catch (error) {
      if (!mounted ||
          generation != _freestyle.generation ||
          runGeneration != _run.lifecycleGeneration) {
        return;
      }
      final message = livePracticePrepareFailureMessage(error);
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      _freestyle.cancelToIdle();
      unawaited(_stopWebSocketSession());
      setState(() => _sessionError = message);
    } finally {
      if (generation == _freestyle.generation &&
          runGeneration == _run.lifecycleGeneration) {
        _commandInFlight = false;
        if (mounted) setState(() {});
      }
    }
  }

  void _showCameraFallbackWarning(CommandAck ack) {
    final message = _fallbackWarningTracker.takeMessage(ack);
    if (message == null) return;
    ElixToast.showWarning(context, message: message);
  }

  Future<void> _activateFreestyle(int generation) async {
    if (_freestyleActivationInFlight ||
        !mounted ||
        generation != _freestyle.generation ||
        _freestyle.phase != FreestyleSessionPhase.ready ||
        _freestyle.isPaused) {
      return;
    }
    _freestyleActivationInFlight = true;
    _run.enterCountdown();
    try {
      if (!await _setEndlessTarget(generation)) return;
      final ack = await _ws.sendActivate();
      if (!mounted || generation != _freestyle.generation) {
        return;
      }
      if (!ack.accepted) {
        final message =
            ack.message ??
            ack.errorCode ??
            'Freestyle activation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        _freestyle.cancelToIdle();
        unawaited(_stopWebSocketSession());
        setState(() => _sessionError = message);
        return;
      }
      if (!_freestyle.markActive(generation)) return;
      _freestyle.confirmTarget(generation, _freestyle.targetGeneration);
      _run.enterActive();
      final settings = context.read<SettingsService>();
      await _music.start(
        selectedTrackId: settings.selectedMusicTrackId,
        customTracks: settings.customMusicTracks,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _freestyle.generation) return;
      debugPrint(
        'Freestyle activation failed: type=${error.runtimeType} '
        'generation=$generation sessionId=${_ws.currentSessionId} '
        'sessionState=${_ws.sessionActive
            ? 'active'
            : _ws.sessionPrepared
            ? 'prepared'
            : 'idle'} '
        'lastProtocolError=${_ws.lastProtocolError?.errorCode} '
        '${_ws.lastProtocolError?.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: 'Freestyle activation failed. Try starting again.',
      );
      _freestyle.cancelToIdle();
      unawaited(_stopWebSocketSession());
      setState(
        () =>
            _sessionError = 'Freestyle activation failed. Try starting again.',
      );
    } finally {
      _freestyleActivationInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _setEndlessTarget(int generation) async {
    final target = _freestyle.currentTarget;
    final targetGeneration = _freestyle.targetGeneration;
    if (!mounted ||
        generation != _freestyle.generation ||
        target == null ||
        targetGeneration <= _requestedTargetGeneration) {
      return false;
    }
    _requestedTargetGeneration = targetGeneration;
    try {
      if (target.kind == EndlessTargetKind.customMovement) {
        final ownerUid = context.read<AuthService>().currentUser?.id;
        final root = ownerUid == null
            ? null
            : await _customMovementRepository
                  .getOwnedMovement(
                    movementId: target.customMovementId!,
                    ownerUid: ownerUid,
                  )
                  .timeout(const Duration(seconds: 5));
        final revision = root == null
            ? null
            : await _customMovementRepository
                  .getRevision(
                    movementId: root.id,
                    revisionId: root.activeRevisionId,
                  )
                  .timeout(const Duration(seconds: 5));
        if (root == null ||
            !root.isActive ||
            root.activeRevisionId != target.revisionId ||
            root.propType != target.prop ||
            revision == null ||
            revision.movementId != root.id ||
            revision.ownerUid != ownerUid ||
            revision.ownerRole != root.ownerRole ||
            (target.template != null &&
                jsonEncode(revision.template.toMap()) !=
                    jsonEncode(target.template!.toMap())) ||
            target.template == null) {
          throw StateError('Custom movement is no longer available');
        }
      }
      if (!mounted ||
          generation != _freestyle.generation ||
          targetGeneration != _freestyle.targetGeneration) {
        return false;
      }
      final ack = await _ws.sendSetEndlessTarget(
        targetGeneration: targetGeneration,
        movement: target.isTossCatch ? null : target.movement,
        prop: target.prop,
        customMovementId: target.customMovementId,
        revisionId: target.revisionId,
        customMovementTemplate: target.template?.toMap(),
      );
      if (!mounted ||
          generation != _freestyle.generation ||
          targetGeneration != _freestyle.targetGeneration) {
        return false;
      }
      if (!ack.accepted) throw StateError(ack.errorCode ?? 'Target rejected');
      if (_freestyle.phase == FreestyleSessionPhase.active) {
        _freestyle.confirmTarget(generation, targetGeneration);
      }
      return true;
    } catch (error) {
      if (mounted && generation == _freestyle.generation) {
        debugPrint('Endless target command failed: $error');
        if (target.kind == EndlessTargetKind.customMovement &&
            _freestyle.excludeCurrentTarget(generation, targetGeneration) &&
            _freestyle.currentTarget != null) {
          return false;
        }
        _freestyle.cancelToIdle();
        _run.cancelToIdle();
        unawaited(_stopWebSocketSession());
        setState(
          () => _sessionError = 'Could not set Endless target. Start again.',
        );
      }
      return false;
    }
  }

  Future<void> _pauseFreestyle() async {
    final generation = _freestyle.generation;
    if (!_freestyle.pause(generation)) return;
    try {
      final ack = await _ws.sendPause();
      if (mounted && generation == _freestyle.generation && !ack.accepted) {
        _freestyle.resume(generation);
      }
    } on Object catch (error) {
      debugPrint('Freestyle pause command failed: $error');
    }
  }

  Future<void> _resumeFreestyle() async {
    final generation = _freestyle.generation;
    if (!_freestyle.isPaused) return;
    try {
      final ack = await _ws.sendResume();
      if (!mounted || generation != _freestyle.generation) return;
      if (ack.accepted) _freestyle.resume(generation);
    } on Object catch (error) {
      debugPrint('Freestyle resume command failed: $error');
    }
  }

  Future<void> _finishFreestyle() async {
    if (_leaving || _quitDialogOpen || _stopInFlight || _freestyleSummaryOpen) {
      return;
    }
    if (!_freestyle.isActive) return;
    final generation = _freestyle.generation;
    final stats = _freestyle.stats;
    final durationSeconds = _run.elapsedSeconds;
    if (!_freestyle.beginEnding(generation)) return;
    _stopInFlight = true;
    try {
      await _stopWebSocketSession();
      unawaited(_music.stop());
      unawaited(_sfx.stop());
      _commandInFlight = false;
      _startInFlight = false;
      _run.markCompleted();
      _freestyle.markCompleted(generation);
      if (!mounted || _leaving) return;
      _freestyleSummaryOpen = true;
      final playAgain = await FreestyleSummarySheet.show(
        context,
        stats: stats,
        durationSeconds: durationSeconds,
        onDone: () {},
      );
      if (!mounted || _leaving) return;
      _freestyle.cancelToIdle();
      _run.cancelToIdle();
      setState(() {
        _clearFrame();
        _latestFeedback = null;
        _bottleDetected = false;
        _sessionError = null;
      });
      if (playAgain == true) {
        // The old session was stopped and its generation invalidated above.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_beginSelectedCameraSession());
        });
      }
    } finally {
      _freestyleSummaryOpen = false;
      _stopInFlight = false;
    }
  }

  Future<void> _beginSessionAfterCountdown() async {
    if (!mounted) return;
    // Playground owns activation from the first usable JPEG via
    // _activateFreestyle and must not inherit this generic countdown owner.
    if (_isPlayground) return;
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
      final settings = context.read<SettingsService>();
      if (!_isPlayground && !_recordingAutoStartRequested) {
        _recordingAutoStartRequested = true;
        await _recording?.beginRecordingNow();
      }
      _sfx.stop();
      await _music.start(
        selectedTrackId: settings.selectedMusicTrackId,
        customTracks: settings.customMusicTracks,
      );
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
    _run.cancelToIdle();
    await _stopWebSocketSession();
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    _commandInFlight = false;
    _startInFlight = false;
    _freestyle.cancelToIdle();
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
    if (_leaving || _quitDialogOpen || _stopInFlight) return;
    _stopInFlight = true;
    try {
      if (_run.isPreparingCamera ||
          _run.isReadiness ||
          _run.isCountdown ||
          _run.isError) {
        await _cancelPreActive();
        return;
      }

      await _stopWebSocketSession();
      if (_leaving || !mounted) return;
      _run.cancelToIdle();
      unawaited(_music.stop());
      unawaited(_sfx.stop());
      _commandInFlight = false;
      _startInFlight = false;
      _freestyle.cancelToIdle();
      if (mounted) {
        setState(() {
          _clearFrame();
          _latestFeedback = null;
          _bottleDetected = false;
          _sessionError = null;
        });
      }
    } finally {
      _stopInFlight = false;
    }
  }

  TrainingQuitCopy get _quitCopy => widget.teacherCreatedAssignment == null
      ? TrainingQuitCopy.playground
      : TrainingQuitCopy.assignment;

  bool get _shouldConfirmAbandon => trainingShouldConfirmAbandon(
    runPhase: _run.phase,
    playgroundPhase: _isPlayground
        ? _freestyle.phase
        : FreestyleSessionPhase.idle,
    recordingPhase: _recording?.phase ?? SubmissionRecordingPhase.idle,
  );

  Future<void> _confirmAbandonThen(Future<void> Function() onConfirmed) async {
    if (_leaving || _quitDialogOpen || _stopInFlight) return;
    _quitDialogOpen = true;
    try {
      final confirmed = await showTrainingQuitDialog(context, copy: _quitCopy);
      if (confirmed && mounted && !_leaving && !_stopInFlight) {
        await onConfirmed();
      }
    } finally {
      _quitDialogOpen = false;
    }
  }

  Future<void> _onCancelPressed() async {
    if (_leaving || _quitDialogOpen || _stopInFlight) return;
    if (!_shouldConfirmAbandon) {
      await _cancelPreActive();
      return;
    }
    await _confirmAbandonThen(_cancelPreActive);
  }

  Future<void> _onBack() async {
    if (_leaving || _stopInFlight) return;
    if (!_shouldConfirmAbandon) {
      await _leave();
      return;
    }
    await _confirmAbandonThen(_leave);
  }

  Future<void> _leave() async {
    if (_leaving || _stopInFlight) return;
    _leaving = true;
    final router = GoRouter.of(context);
    final location = widget.teacherCreatedAssignment == null
        ? AppRoutePaths.dashboard
        : AppRoutePaths.assignmentDetail(
            widget.teacherCreatedAssignment!.assignment.id,
          );
    final feedbackSub = _feedbackSub;
    final previewSub = _previewSub;
    final recognitionSub = _recognitionSub;
    _feedbackSub = null;
    _previewSub = null;
    _recognitionSub = null;
    unawaited(feedbackSub?.cancel() ?? Future<void>.value());
    unawaited(previewSub?.cancel() ?? Future<void>.value());
    unawaited(recognitionSub?.cancel() ?? Future<void>.value());
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    await _stopWebSocketSession();
    if (_ownsWebSocket) await _ws.disconnect();
    _run.cancelToIdle();
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    _commandInFlight = false;
    _startInFlight = false;
    _freestyle.cancelToIdle();
    router.go(location);
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
      PracticeRunPhase.readiness => TrainingSessionPhase.readiness,
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
      padding: EdgeInsets.zero,
      content: SizedBox.expand(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm + 2,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.min(
                  constraints.maxWidth,
                  _maxContentWidth,
                );
                final isDesktop = contentWidth >= _wideBreakpoint;
                final isCompact =
                    contentWidth >= _compactBreakpoint && !isDesktop;
                final assignment = widget.teacherCreatedAssignment;
                final header = TrainingSessionHeader(
                  onBack: _onBack,
                  title: assignment?.title ?? 'Endless Mode',
                  statusPill: assignment == null
                      ? 'RUN SCORE ONLY'
                      : 'TEACHER REVIEWED',
                  statusPillColor: AppColors.primarySoft,
                  instruction: assignment == null
                      ? 'Complete the current movement before time runs out. The run score stays on this device.'
                      : (assignment.instructions.isEmpty
                            ? 'Practice this Teacher Activity. Your Teacher reviews the recording.'
                            : assignment.instructions),
                  connectionState: _ws.connectionState,
                  connecting: _connecting,
                  wideLayout: isDesktop || isCompact,
                );
                final progressionHud = assignment == null
                    ? _PlaygroundProgressionHud(
                        progression: context.watch<TraineeProgressionService>(),
                      )
                    : null;
                final camera = TrainingCameraWorkspace(
                  frameListenable: _frameBytes,
                  mirrored: context.watch<SettingsService>().cameraMirrored,
                  connectionState: _ws.connectionState,
                  connecting: _connecting,
                  isSessionActive: isCameraLive && !_run.isPreparingCamera,
                  isPreparingCamera: _run.isPreparingCamera,
                  accentBorder:
                      _run.isPreparingCamera ||
                      _run.isReadiness ||
                      _run.isCountdown,
                  readyAura:
                      _run.readiness.stable ||
                      (_isPlayground &&
                          _freestyle.liveState == RecognitionState.confirmed),
                  idleTitle: assignment == null
                      ? 'Endless Mode'
                      : 'Practice Arena',
                  idleSubtitle: assignment == null
                      ? 'Select a prop, then start your sequence.'
                      : 'Press Start assignment practice when you are ready.',
                  idleCaption: assignment == null
                      ? 'Keep your upper body, hands, and bottle or shaker visible.'
                      : 'Keep your upper body, hands, and bottle visible.',
                  errorMessage: _ws.errorMessage,
                  sessionError: _sessionError ?? _run.errorMessage,
                  recoveryPresentation:
                      (_sessionError ?? _run.errorMessage) != null ||
                          _ws.connectionState == WebSocketConnectionState.error
                      ? CameraRecoveryPresentation.fromFailure(
                          errorCode: _sessionErrorCode,
                          diagnosticMessage:
                              _sessionError ??
                              _run.errorMessage ??
                              _ws.errorMessage,
                          connectionFailed:
                              _ws.connectionState ==
                              WebSocketConnectionState.error,
                        )
                      : null,
                  onRetry: _retrySession,
                  onChooseCamera: _chooseCamera,
                  onOpenSetupHelp: () => showCameraRecoverySetupHelp(context),
                  // The shared overlay owns countdown completion for Guided
                  // Practice and Teacher Activity only. Playground activates
                  // from the first usable JPEG without a Get Ready clock.
                  countdownActive: !_isPlayground && _run.isCountdown,
                  onCountdownComplete: _beginSessionAfterCountdown,
                  overlayFeedback: isTrainingActive
                      ? null
                      : (isCameraLive ? _latestFeedback : null),
                  showFeedbackMessage: false,
                  overlays:
                      assignment == null &&
                          _freestyle.phase != FreestyleSessionPhase.idle &&
                          !_freestyle.isComplete
                      ? FreestyleOverlay(
                          controller: _freestyle,
                          elapsedSeconds: _run.elapsedSeconds,
                          onPause: () => unawaited(_pauseFreestyle()),
                          onResume: () => unawaited(_resumeFreestyle()),
                          onQuit: () => unawaited(_finishFreestyle()),
                          connectionLost:
                              !_ws.isConnected && _freestyle.hasWorkToLose,
                        )
                      : null,
                  statusItems: [
                    if (isTrainingActive && assignment != null)
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

                final idlePanel =
                    _run.phase == PracticeRunPhase.idle ||
                    _run.phase == PracticeRunPhase.completed;
                final showCameraSelector =
                    !_run.isCameraSessionLive &&
                    !_startInFlight &&
                    !_choosingCamera &&
                    !_connecting &&
                    !_stopInFlight &&
                    _webSocketStopFuture == null;
                final canChoosePreActiveCamera =
                    _isTeacherActivityV2 &&
                    (_run.isPreparingCamera || _run.isReadiness) &&
                    !_choosingCamera &&
                    !_stopInFlight;
                final panel = TrainingSessionPanel(
                  phase: _panelPhase(),
                  expandVertically: isDesktop,
                  metrics: idlePanel
                      ? TrainingReadyBrief(
                          title: assignment == null
                              ? 'Endless Mode'
                              : 'Ready to practice',
                          body: assignment == null
                              ? 'Follow the current target. Misses advance the sequence; the run continues until you end it.'
                              : 'Start assignment practice when the camera is ready. This attempt is teacher-reviewed, not scored.',
                        )
                      : LivePracticeElapsedMetric(
                          elapsedDisplay: _formatDuration(
                            _recording?.phase ==
                                    SubmissionRecordingPhase.recording
                                ? _recording!.elapsedSeconds
                                : _run.elapsedSeconds,
                          ),
                        ),
                  statusContent:
                      (_run.isReadiness ||
                          (_run.isCountdown && _run.readiness.frozen))
                      ? ReadinessChecklistPanel(
                          items: _run.readiness.displayItems,
                          progress: _run.readiness.stableProgress,
                          stable: _run.readiness.stable,
                          complete: _run.readiness.complete,
                          frozen: _run.readiness.frozen,
                          streamStale: _run.readiness.streamStale,
                          recoverableMessage: _run.readiness.recoverableMessage,
                          readyCount: _run.readiness.readyCount,
                        )
                      : TrainingStatusRow(
                          detection: resolveDetectionStatus(
                            sessionActive: isTrainingActive,
                            bottleDetected: isTrainingActive
                                ? (_isPlayground
                                      ? _freestyle.detectedProp != null
                                      : _bottleDetected)
                                : null,
                          ),
                          propLabel: _isPlayground
                              ? switch (_freestyle.detectedProp) {
                                  TrainingProp.bottle => 'Bottle',
                                  TrainingProp.shaker => 'Shaker',
                                  TrainingProp.bottleAndShaker => 'Prop',
                                  null => 'Prop',
                                }
                              : 'Bottle',
                        ),
                  notice: Text(
                    assignment == null
                        ? 'Run score is session only. Mastery and XP are unchanged.'
                        : 'Teacher-created practice is not scored and does not award XP.',
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  supportingContent:
                      !showCameraSelector &&
                          !canChoosePreActiveCamera &&
                          (assignment == null || _recording == null)
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (assignment == null && showCameraSelector) ...[
                              Text(
                                'Run prop',
                                style: AppTheme.body.copyWith(
                                  color: context.elixTextPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ComboBox<TrainingProp>(
                                value: _endlessProp,
                                items: const [
                                  ComboBoxItem(
                                    value: TrainingProp.bottle,
                                    child: Text('Bottle'),
                                  ),
                                  ComboBoxItem(
                                    value: TrainingProp.shaker,
                                    child: Text('Cocktail Shaker'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _endlessProp = value);
                                  }
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            if (assignment != null && _recording != null)
                              SubmissionRecordingPanel(
                                controller: _recording!,
                                cameraReady: isTrainingActive,
                              ),
                            if (showCameraSelector) ...[
                              CameraSourcePreference(
                                settings: context.watch<SettingsService>(),
                                cameras: context.watch<CameraDeviceService>(),
                                compact: true,
                                onSelectionBusyChanged: (busy) {
                                  if (mounted) {
                                    setState(() => _cameraSelectionBusy = busy);
                                  }
                                },
                              ),
                            ],
                            if (canChoosePreActiveCamera)
                              Button(
                                onPressed: _chooseCamera,
                                child: const Text('Change camera'),
                              ),
                          ],
                        ),
                  compactStatusNote:
                      (_startError ?? _sessionError ?? _run.errorMessage) !=
                          null
                      ? Text(
                          _startError ?? _sessionError ?? _run.errorMessage!,
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
                        ? 'Start Endless Mode'
                        : (_assignmentStartBlocked
                              ? 'Attempt unavailable'
                              : 'Start assignment practice'),
                    onPressed: switch (actionKind) {
                      TrainingActionKind.finish =>
                        _isPlayground ? _finishFreestyle : _stopSession,
                      TrainingActionKind.cancel => _onCancelPressed,
                      TrainingActionKind.retry || TrainingActionKind.start =>
                        _assignmentStartBlocked ||
                                _cameraSelectionBusy ||
                                _choosingCamera
                            ? null
                            : _beginSelectedCameraSession,
                    },
                    isLoading:
                        actionKind == TrainingActionKind.cancel ||
                            actionKind == TrainingActionKind.finish
                        ? false
                        : (_connecting ||
                              _startInFlight ||
                              _choosingCamera ||
                              _commandInFlight ||
                              _cameraSelectionBusy),
                  ),
                );

                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    if (progressionHud != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      progressionHud,
                    ],
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, workspaceConstraints) {
                          final workspace = TrainingArenaWorkspace(
                            desktop: isDesktop,
                            contentWidth: contentWidth,
                            workspaceHeight: workspaceConstraints.maxHeight,
                            camera: camera,
                            panel: panel,
                          );
                          if (isDesktop) return workspace;
                          return SingleChildScrollView(child: workspace);
                        },
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth <= _maxContentWidth) {
                  return body;
                }
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: _maxContentWidth, child: body),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaygroundProgressionHud extends StatelessWidget {
  const _PlaygroundProgressionHud({required this.progression});

  final TraineeProgressionService progression;

  @override
  Widget build(BuildContext context) {
    if (!progression.isReady) {
      return Text(
        'Level progress loading…',
        style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
      );
    }
    final level = progression.level;
    final into = GamificationRules.xpIntoLevel(progression.totalXp);
    final perLevel = GamificationRules.xpPerLevel;
    return Text(
      'Level $level · $into / $perLevel XP',
      style: AppTheme.caption.copyWith(
        color: context.elixTextSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
