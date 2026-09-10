import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/gamification_rules.dart';
import '../../core/constants/music_tracks.dart';
import '../../core/progression/progression_access.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/assignment_attempt.dart';
import '../../data/models/classroom_exceptions.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/recognition_event.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/settings_service.dart';
import '../../services/startup_diagnostics.dart';
import '../../services/trainee_progression_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../../services/websocket_service.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
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

class LivePracticeScreenState extends State<LivePracticeScreen> {
  late final WebSocketService _ws;
  late final bool _ownsWebSocket;
  final _music = PracticeMusicService();
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
  bool _leaving = false;
  bool _quitDialogOpen = false;
  bool _stopInFlight = false;
  bool _startInFlight = false;
  bool _activityAutoStartRequested = false;
  bool _activityReservationReleased = false;
  bool _reservationReleaseInFlight = false;
  SubmissionRecordingController? _recording;

  /// True while a WebSocket prepare/activate command is awaiting ack.
  bool _commandInFlight = false;
  bool _freestyleActivationInFlight = false;
  bool _freestyleSummaryOpen = false;

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
    unawaited(_recording?.releaseActivityAttempt() ?? Future<void>.value());
    _recording?.dispose();
    _feedbackSub?.cancel();
    _previewSub?.cancel();
    _recognitionSub?.cancel();
    _frameBytes.dispose();
    _music.dispose();
    _sfx.dispose();
    _freestyle.removeListener(_onFreestyleChanged);
    _freestyle.dispose();
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

  @visibleForTesting
  FreestyleSessionController get debugFreestyle => _freestyle;

  @visibleForTesting
  PracticeRunController get debugRun => _run;

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

  bool get _isPlayground => widget.teacherCreatedAssignment == null;

  void _onFreestyleChanged() {
    if (!mounted || !_isPlayground) return;
    if (_freestyle.isPaused) {
      _run.pauseElapsed();
    } else {
      _run.resumeElapsed();
    }
    setState(() {});
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
      setState(
        () => _sessionError =
            'Backend connection lost. Restart Freestyle to continue.',
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

  Future<void> _stopWebSocketSession() async {
    await _recording?.abandonLocalClip();
    await _recording?.releaseActivityAttempt();
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
      if (_isTeacherActivityV2 && feedback.readinessStable == false) {
        _run.onActivationRejected();
        unawaited(_releaseReservationAfterReadinessLoss());
        setState(() {
          _sessionError =
              'Readiness was lost. Hold the required setup steady to restart the countdown.';
        });
      }
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
    await _sfx.setVolume(settings.soundEnabled ? settings.musicVolume : 0.0);
    await _sfx.playCountdown();
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
    if (!_isTeacherActivityV2 ||
        _commandInFlight ||
        _reservationReleaseInFlight) {
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
      if (_activityReservationReleased) {
        await _recording?.reserveActivityAttempt();
        if (!mounted || generation != _run.lifecycleGeneration) return;
        _activityReservationReleased = false;
      }
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
      await _sfx.setVolume(settings.soundEnabled ? settings.musicVolume : 0.0);
      await _sfx.playCountdown();
    } catch (_) {
      if (!mounted || generation != _run.lifecycleGeneration) return;
      _run.onConfirmReadinessRejected();
      setState(() {
        _sessionError = 'Readiness confirmation failed. Try again.';
      });
    } finally {
      _commandInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _releaseReservationAfterReadinessLoss() async {
    if (_reservationReleaseInFlight) return;
    _reservationReleaseInFlight = true;
    try {
      await _recording?.releaseActivityAttempt();
      if (!mounted) return;
      _activityReservationReleased = true;
    } finally {
      _reservationReleaseInFlight = false;
      if (mounted) {
        setState(() {});
        _onActivityReadinessStable();
      }
    }
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
    await _resetInterruptedAttempt();
    if (!mounted || _leaving) return;
    await SettingsScreen.show(
      context,
      initialSection: SettingsSection.practice,
    );
  }

  Future<void> _startSession() async {
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    if (_startInFlight || _leaving || _stopInFlight || _freestyleSummaryOpen) {
      return;
    }
    if (_commandInFlight) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    if (widget.teacherCreatedAssignment == null) {
      final progression = context.read<TraineeProgressionService>();
      final tutorials = context.read<TutorialProgressService>();
      if (!progression.isReady || !tutorials.isInitialized) {
        setState(() {
          _sessionError =
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
        if (submission == null) {
          throw const ClassroomException(
            ClassroomError.invalidState,
            'No reserved Activity attempt is available.',
          );
        }
        if (submission.status != AssignmentAttemptStatus.inProgress) {
          if (!mounted) return;
          setState(() {
            _sessionError = submission.status == AssignmentAttemptStatus.checked
                ? 'This assignment has already been checked.'
                : 'This submission is waiting for your teacher to check it.';
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
        if (!mounted) return;
        setState(() {
          _sessionError = livePracticeAssignmentStartFailureMessage(error);
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
    if (assignment == null) {
      final generation = _freestyle.start();
      if (generation == null) {
        setState(() {
          _sessionError = 'Could not start Freestyle. Try again.';
        });
        return;
      }
      await _prepareFreestyle(generation, settings);
      return;
    }
    _ws.beginPracticeAttempt();
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    setState(() {});

    final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
    if (!mounted || _leaving) return;
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
          _sessionErrorCode = ack.errorCode;
          _clearFrame();
        });
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
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
      _commandInFlight = false;
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
        prop: TrainingProp.bottleAndShaker,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
        sessionMode: 'freestyle',
        allowedMovements: _freestyleAllowlist(),
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
      }
    } catch (error) {
      if (!mounted || generation != _freestyle.generation) return;
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
      _commandInFlight = false;
      if (mounted) setState(() {});
    }
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
      _run.enterActive();
      final settings = context.read<SettingsService>();
      await _music.setVolume(
        settings.soundEnabled ? settings.musicVolume : 0.0,
      );
      _music.start(resolveTrack(settings.selectedMusicTrackId));
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

  Future<void> _pauseFreestyle() async {
    final generation = _freestyle.generation;
    if (!_freestyle.pause(generation)) return;
    try {
      await _ws.sendPause();
    } on Object catch (error) {
      debugPrint('Freestyle pause command failed: $error');
    }
  }

  Future<void> _resumeFreestyle() async {
    final generation = _freestyle.generation;
    if (!_freestyle.resume(generation)) return;
    try {
      final ack = await _ws.sendResume();
      if (!mounted || generation != _freestyle.generation) return;
      if (!ack.accepted) {
        _freestyle.pause(generation);
        setState(() {});
      }
    } on Object catch (error) {
      debugPrint('Freestyle resume command failed: $error');
      if (generation == _freestyle.generation) {
        _freestyle.pause(generation);
        if (mounted) setState(() {});
      }
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
      await FreestyleSummarySheet.show(
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
      _sfx.stop();
      final settings = context.read<SettingsService>();
      final track = resolveTrack(settings.selectedMusicTrackId);
      final volume = settings.soundEnabled ? settings.musicVolume : 0.0;
      await _music.setVolume(volume);
      _music.start(track);
      if (_isTeacherActivityV2) {
        await _recording?.beginActivityRecordingNow();
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
                  title: assignment?.title ?? 'Playground',
                  statusPill: assignment == null
                      ? 'NO SCORING'
                      : 'TEACHER REVIEWED',
                  statusPillColor: AppColors.primarySoft,
                  instruction: assignment == null
                      ? 'Freestyle is unscored and is not saved to your practice history. ELIXR will recognize techniques as you perform them.'
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
                      ? 'Freestyle Playground'
                      : 'Practice Arena',
                  idleSubtitle: assignment == null
                      ? 'Press Start Freestyle when you are ready.'
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
                          onPause: () => unawaited(_pauseFreestyle()),
                          onResume: () => unawaited(_resumeFreestyle()),
                          onQuit: () => unawaited(_onCancelPressed()),
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
                final panel = TrainingSessionPanel(
                  phase: _panelPhase(),
                  expandVertically: isDesktop,
                  metrics: idlePanel
                      ? TrainingReadyBrief(
                          title: assignment == null
                              ? 'Freestyle Playground'
                              : 'Ready to practice',
                          body: assignment == null
                              ? 'Freestyle is unscored and is not saved to your practice history. Move freely while ELIXR recognizes techniques.'
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
                        ? 'Freestyle is unscored and is not saved to your practice history.'
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
                  compactStatusNote:
                      (_sessionError ?? _run.errorMessage) != null
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
                        ? 'Start Freestyle'
                        : (_isTeacherActivityV2
                              ? 'Preparing attempt…'
                              : 'Start assignment practice'),
                    onPressed: switch (actionKind) {
                      TrainingActionKind.finish =>
                        _isPlayground ? _finishFreestyle : _stopSession,
                      TrainingActionKind.cancel => _onCancelPressed,
                      TrainingActionKind.retry || TrainingActionKind.start =>
                        _ws.isConnected ? _startSession : _connect,
                    },
                    isLoading:
                        actionKind == TrainingActionKind.cancel ||
                            actionKind == TrainingActionKind.finish
                        ? false
                        : (_connecting || _startInFlight || _commandInFlight),
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
