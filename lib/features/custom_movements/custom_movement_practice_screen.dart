import 'dart:async';
import 'dart:math' as math;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/custom_movement.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/session_evidence_repository.dart';
import '../../services/app_background_music_service.dart';
import '../../services/audio_player_handle.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/websocket_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/camera_device_service.dart';
import '../settings/widgets/camera_source_preference.dart';
import '../practice/session_evidence_consent.dart';
import '../practice/session_summary_sheet.dart';
import 'custom_movement_result_dialog.dart';
import '../practice/widgets/training_action_area.dart';
import '../practice/widgets/training_arena_layout.dart';
import '../practice/widgets/training_camera_workspace.dart';
import '../practice/widgets/readiness_checklist_panel.dart';
import '../practice/widgets/training_session_header.dart';
import '../practice/widgets/training_session_panel.dart';
import '../practice/widgets/training_status_row.dart';

class CustomMovementPracticeScreen extends StatefulWidget {
  const CustomMovementPracticeScreen({
    super.key,
    required this.movement,
    required this.revision,
    required this.repository,
    this.assignment,
    this.traineeUid,
    this.classroomRepository,
    this.webSocket,
    this.onExit,
    this.sessionService,
    this.classroomAttemptsRemaining,
    @visibleForTesting this.now = DateTime.now,
    @visibleForTesting this.musicPlayer,
    @visibleForTesting this.sfxPlayer,
  });

  final CustomMovement movement;
  final CustomMovementRevision revision;
  final CustomMovementRepository repository;
  final GroupAssignment? assignment;
  final String? traineeUid;
  final ClassroomAssignmentRepository? classroomRepository;
  final WebSocketService? webSocket;

  /// Session-evidence preference owner. Defaults to the provided
  /// [SessionService]; injectable for tests.
  final SessionService? sessionService;

  /// Allows routed personal practice to return to its canonical origin without
  /// changing the pop behavior used by assignment and teacher flows.
  final VoidCallback? onExit;

  /// Remaining classroom attempts when this run started; null means
  /// unlimited. Only gates the local Practice Again affordance - the server
  /// remains authoritative for the attempt limit.
  final int? classroomAttemptsRemaining;

  /// Wall clock for the recording deadline; injectable so tests can expire it.
  final DateTime Function() now;

  /// Native player overrides for the owned practice audio services; tests
  /// inject fakes so no audio device is opened.
  final AudioPlayerHandle? musicPlayer;
  final AudioPlayerHandle? sfxPlayer;

  @override
  State<CustomMovementPracticeScreen> createState() =>
      _CustomMovementPracticeScreenState();
}

enum _CustomPracticePhase {
  preparing,
  setupChecking,
  countdown,
  recording,
  processing,
  completed,
  failed,
}

enum _CustomFailureCategory { setup, tracking, operation }

class _CustomPracticeFailure implements Exception {
  const _CustomPracticeFailure({required this.message, required this.category});

  final String message;
  final _CustomFailureCategory category;

  bool get isSetup => category == _CustomFailureCategory.setup;
  bool get showsCameraRecovery => isSetup;
}

class _CustomCommandRejected implements Exception {
  const _CustomCommandRejected(this.code, this.message);

  final String code;
  final String? message;
}

class _CustomMovementPracticeScreenState
    extends State<CustomMovementPracticeScreen> {
  static const _captureDuration = Duration(seconds: 30);
  static const _setupFailureMessage =
      'Could not prepare the camera and movement model.';
  static const _startFailureMessage =
      'ELIXR could not start practice. Retry the session.';
  static const _assessmentFailureMessage =
      'ELIXR could not complete the assessment. Start another practice attempt.';
  static const _incompleteResultMessage =
      'The assessment result was incomplete. Start another practice attempt.';
  static const _classroomSaveFailureMessage =
      'Assessment complete, but the classroom result could not be saved. '
      'Return to the assignment to check your attempts before trying again.';

  /// Upper bound on exit cleanup. Anything still pending afterwards is
  /// closed by [dispose], which drops the owned backend transport.
  static const _exitCleanupTimeout = Duration(seconds: 3);

  late final WebSocketService _socket;
  late final bool _ownsSocket;
  StreamSubscription<PreviewFrame>? _previewSubscription;
  StreamSubscription<PracticeFeedback>? _feedbackSubscription;
  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<PreviewFrame?> _presentation =
      ValueNotifier<PreviewFrame?>(null);
  final ValueNotifier<PracticeFeedback?> _readinessFeedback =
      ValueNotifier<PracticeFeedback?>(null);
  final ValueNotifier<PracticeFeedback?> _assessmentProgress =
      ValueNotifier<PracticeFeedback?>(null);
  final ValueNotifier<_CustomLiveCue?> _liveCue = ValueNotifier(null);
  Timer? _liveCueTimer;
  int _lastCueSequence = 0;
  _CustomPracticePhase _phase = _CustomPracticePhase.preparing;
  bool _busy = false;

  /// Idempotent exit guard, separate from [_busy] so an in-flight operation
  /// can never block leaving the screen.
  bool _leaving = false;
  bool _cameraSelectionBusy = false;
  int? _countdown;
  _CustomPracticeFailure? _failure;
  String? _sessionToRelease;
  int? _classroomAttemptsRemaining;

  /// One-shot readiness auto-start gate for the current preparation cycle.
  /// Reset only by a new preparation or a recoverable confirm rejection.
  bool _autoStartConsumed = false;

  /// Backend completion-confirming frame, captured before capture teardown.
  Uint8List? _completionEvidenceJpegBytes;
  DateTime? _practiceStartedAt;
  DateTime? _recordingDeadline;
  Timer? _recordingTimer;
  int _remainingSeconds = _captureDuration.inSeconds;

  /// Same practice audio ownership as official practice: one music channel
  /// and one SFX channel for the lifetime of this screen.
  late final PracticeMusicService _music;
  bool _musicInitialized = false;
  late final PracticeSfxService _sfx = PracticeSfxService(
    player: widget.sfxPlayer,
  );

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    _classroomAttemptsRemaining = widget.classroomAttemptsRemaining;
    unawaited(_sfx.preload());
    unawaited(_prepare());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_musicInitialized) return;
    _musicInitialized = true;
    final settings = context.read<SettingsService>();
    _music = PracticeMusicService(
      settings: settings,
      appBackgroundMusic: context.read<AppBackgroundMusicService?>(),
      player: widget.musicPlayer,
    );
    _sfx.bindSettings(settings);
  }

  /// Ends any practice music and one-shot SFX for the current attempt and
  /// hands audio back to app background music.
  void _stopPracticeAudio() {
    if (_musicInitialized) unawaited(_music.stop());
    unawaited(_sfx.stop());
  }

  Future<void> _prepare() async {
    _previewSubscription = _socket.previewStream.listen((frame) {
      if (!mounted || _phase == _CustomPracticePhase.preparing) return;
      _presentation.value = frame;
      if (!frame.hasJpeg) return;
      _preview.value = frame.jpegBytes;
    });
    _feedbackSubscription = _socket.feedbackStream.listen((feedback) {
      if (!mounted) return;

      // Preview JPEGs stay on their isolated presentation path. Readiness is
      // backend-authoritative and updates only the setup checklist.
      if (feedback.readinessItems != null || feedback.readinessStable != null) {
        _readinessFeedback.value = feedback;
      }
      // Readiness only matters during setup; late readiness loss after the
      // attempt was accepted never demotes or restarts it.
      if (_phase == _CustomPracticePhase.setupChecking) {
        if (feedback.readinessStable == true) {
          _maybeAutoStart();
        } else {
          setState(() {});
        }
      }
      if (feedback.customAssessmentProgress != null) {
        // The backend attaches evidence only to the completion-confirming
        // frame. Retain it before the async stop/teardown below.
        if (_phase == _CustomPracticePhase.recording) {
          _completionEvidenceJpegBytes ??= feedback.evidenceJpegBytes;
        }
        _assessmentProgress.value = feedback;
        final cueSequence = feedback.customAssessmentCueSequence;
        final cue = feedback.customAssessmentCue;
        if (_phase == _CustomPracticePhase.recording &&
            cue != null &&
            cueSequence != null &&
            cueSequence > _lastCueSequence) {
          _lastCueSequence = cueSequence;
          _showLiveCue(cue, cueSequence);
        }
        if (feedback.customAssessmentProgress == 'completed' &&
            _phase == _CustomPracticePhase.recording &&
            !_busy) {
          unawaited(_finish());
        }
      }
    });
    await _prepareSession();
  }

  Future<void> _prepareSession() async {
    final settings = context.read<SettingsService>();
    // Setup and readiness never play practice music; a retry or camera
    // switch must not carry the previous attempt's music forward.
    if (_musicInitialized) unawaited(_music.stop());
    if (mounted) {
      setState(() {
        _phase = _CustomPracticePhase.preparing;
        _failure = null;
        _autoStartConsumed = false;
        _completionEvidenceJpegBytes = null;
        _countdown = null;
        _remainingSeconds = _captureDuration.inSeconds;
        _recordingDeadline = null;
        _recordingTimer?.cancel();
        _recordingTimer = null;
        _readinessFeedback.value = null;
        _assessmentProgress.value = null;
        _clearLiveCue();
        _lastCueSequence = 0;
        _preview.value = null;
        _presentation.value = null;
      });
    }
    try {
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('backend unavailable');
      final sessionId = _socket.beginPracticeAttempt();
      _sessionToRelease = sessionId;
      final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
      if (!mounted) return;
      _requireAccepted(
        await _socket.sendPrepare(
          movement: 'Custom Movement',
          difficulty: widget.movement.difficulty,
          prop: widget.movement.propType,
          sessionId: sessionId,
          sessionMode: 'custom_assessment',
          cameraDeviceId: cameraDeviceId,
          legacyCameraIndex: cameraDeviceId == null
              ? settings.pendingLegacyCameraIndex
              : null,
          customMovementTemplate: widget.revision.template.toMap(),
          readinessSpec: widget.revision.template.readinessSpec,
        ),
      );
      _requireAccepted(await _socket.sendBeginReadiness(sessionId: sessionId));
      if (mounted) {
        setState(() => _phase = _CustomPracticePhase.setupChecking);
        // Readiness may already have become stable before this ack.
        _maybeAutoStart();
      }
    } catch (error) {
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _failure = _failureFor(
            error,
            fallback: _setupFailureMessage,
            isSetup: true,
          );
        });
      }
    }
  }

  /// Starts the attempt once per preparation cycle, as soon as the
  /// backend-authoritative readiness is stable. There is no manual start.
  void _maybeAutoStart() {
    if (!mounted ||
        _leaving ||
        _autoStartConsumed ||
        _busy ||
        _cameraSelectionBusy ||
        _phase != _CustomPracticePhase.setupChecking ||
        _readinessFeedback.value?.readinessStable != true) {
      return;
    }
    _autoStartConsumed = true;
    unawaited(_start());
  }

  static bool _isRecoverableReadinessRejection(String? code) =>
      code == 'readiness_not_stable' ||
      code == 'readiness_stale' ||
      code == 'single_performer_required';

  Future<void> _start() async {
    if (_busy || _phase != _CustomPracticePhase.setupChecking) return;
    final settings = context.read<SettingsService>();
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.countdown;
      _failure = null;
    });
    try {
      final confirm = await _socket.sendConfirmReadiness();
      if (!mounted) return;
      if (!confirm.accepted &&
          _isRecoverableReadinessRejection(confirm.errorCode)) {
        // Setup changed before acceptance: keep calibrating and re-arm the
        // gate for the next fresh stable readiness report.
        _readinessFeedback.value = null;
        _autoStartConsumed = false;
        setState(() => _phase = _CustomPracticePhase.setupChecking);
        return;
      }
      _requireAccepted(confirm);
      // The countdown SFX accompanies the existing visual 3-2-1 below,
      // exactly as official practice plays it on entering countdown.
      unawaited(
        _sfx.playCountdown(
          volume: settings.soundEnabled ? settings.musicVolume : 0.0,
        ),
      );
      for (var value = 3; value >= 1; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
      _requireAccepted(await _socket.sendActivate());
      _clearLiveCue();
      _lastCueSequence = 0;
      _requireAccepted(
        await _socket.sendStartCustomCapture(durationSeconds: 30),
      );
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.recording;
          _practiceStartedAt = widget.now();
          _recordingDeadline = _practiceStartedAt!.add(_captureDuration);
          _remainingSeconds = _captureDuration.inSeconds;
        });
        _recordingTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _updateRecordingTime(),
        );
        // Music starts only once the accepted attempt is recording.
        if (!_leaving) {
          unawaited(_sfx.stop());
          unawaited(
            _music.start(
              selectedTrackId: settings.selectedMusicTrackId,
              customTracks: settings.customMusicTracks,
            ),
          );
        }
      }
    } catch (error) {
      _stopPracticeAudio();
      // Activation may already have succeeded before capture startup fails.
      // Release the backend session before showing a failed state with no
      // active-session controls.
      await _stopSessionBestEffort();
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _clearLiveCue();
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _countdown = null;
          _failure = _failureFor(error, fallback: _startFailureMessage);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_phase == _CustomPracticePhase.recording &&
            _assessmentProgress.value?.customAssessmentProgress ==
                'completed') {
          unawaited(_finish());
        }
      }
    }
  }

  Future<void> _finish() async {
    if (_busy || _leaving || _phase != _CustomPracticePhase.recording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _stopPracticeAudio();
    ({
      CustomAssessmentSnapshot assessment,
      Uint8List? evidence,
      int durationSeconds,
    })?
    completed;
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.processing;
      _failure = null;
    });
    try {
      _requireAccepted(await _socket.sendStopCustomCapture());
      final ack = await _socket.sendFinishCustomAssessment();
      final assessment = ack.customAssessment;
      _requireAccepted(ack);
      if (assessment == null) {
        throw const _CustomPracticeFailure(
          message:
              'ELIXR did not return an assessment result. Start another practice attempt.',
          category: _CustomFailureCategory.operation,
        );
      }
      final snapshot = CustomAssessmentSnapshot.tryFrom(assessment);
      final classroomIncomplete =
          widget.assignment != null &&
          (snapshot?.total == null ||
              snapshot?.performanceLevel == null ||
              widget.traineeUid == null ||
              widget.classroomRepository == null);
      if (snapshot == null || classroomIncomplete) {
        throw const _CustomPracticeFailure(
          message: _incompleteResultMessage,
          category: _CustomFailureCategory.operation,
        );
      }
      // Freeze this attempt before teardown: persistence and the result
      // dialog use only this immutable snapshot, for personal and classroom
      // runs alike.
      completed = (
        assessment: snapshot,
        evidence: _completionEvidenceJpegBytes,
        durationSeconds: _elapsedPracticeSeconds(),
      );
      await _stopSessionBestEffort();
      if (mounted) {
        _clearLiveCue();
        setState(() {
          _phase = _CustomPracticePhase.completed;
          _presentation.value = null;
        });
      }
    } catch (error) {
      completed = null;
      await _stopSessionBestEffort();
      if (mounted) {
        _clearLiveCue();
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _presentation.value = null;
          _failure = _failureFor(error, fallback: _assessmentFailureMessage);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final result = completed;
    if (result == null ||
        !mounted ||
        _leaving ||
        _phase != _CustomPracticePhase.completed) {
      return;
    }
    if (widget.assignment == null) {
      await _presentPersonalResult(
        assessment: result.assessment,
        evidence: result.evidence,
        durationSeconds: result.durationSeconds,
      );
    } else {
      await _presentClassroomResult(
        assessment: result.assessment,
        durationSeconds: result.durationSeconds,
      );
    }
  }

  int _elapsedPracticeSeconds() => widget
      .now()
      .difference(_practiceStartedAt ?? widget.now())
      .inSeconds
      .clamp(0, 86400)
      .toInt();

  /// Persists one completed personal attempt and presents its result.
  ///
  /// Persistence starts here, before the dialog is shown, under one reserved
  /// session ID that every retry reuses.
  Future<void> _presentPersonalResult({
    required CustomAssessmentSnapshot assessment,
    required Uint8List? evidence,
    required int durationSeconds,
  }) async {
    final ownerUid = widget.movement.ownerUid;
    final usableEvidence =
        evidence != null &&
            SessionEvidenceRepository.acceptsJpegSize(evidence.lengthInBytes)
        ? evidence
        : null;
    Uint8List? retainedEvidence;
    if (usableEvidence != null) {
      // Same consent semantics as official practice: an explicit opt-out is
      // respected; an unset preference asks once and records the decision.
      final preferences =
          widget.sessionService ?? context.read<SessionService>();
      var enabled = await preferences.sessionEvidenceEnabled(ownerUid);
      if (!mounted || _leaving) return;
      if (enabled == null) {
        enabled = await askSessionEvidenceConsent(context);
        if (!mounted || _leaving) return;
        await preferences.setSessionEvidenceEnabled(
          userId: ownerUid,
          enabled: enabled,
        );
        if (!mounted) return;
      }
      if (enabled) retainedEvidence = usableEvidence;
    }

    final sessionId = widget.repository.allocateSessionId();
    final saveController = SessionSummarySaveController(
      save: () => widget.repository.savePersonalResult(
        ownerUid: ownerUid,
        movementId: widget.movement.id,
        revisionId: widget.revision.id,
        totalScore: assessment.scorePercent,
        componentScores: assessment.persistedComponentScores,
        feedback: assessment.feedback,
        sessionId: sessionId,
        movementName: widget.movement.name,
        difficulty: widget.movement.difficulty,
        propType: widget.movement.propType,
        durationSeconds: durationSeconds,
        referenceImageStoragePath: widget.movement.referenceImageStoragePath,
        evidenceJpegBytes: retainedEvidence,
      ),
    );
    unawaited(saveController.start());
    SessionSummaryResult? result;
    try {
      result = await CustomMovementResultDialog.show(
        context,
        movementName: widget.movement.name,
        durationSeconds: durationSeconds,
        assessment: assessment,
        saveController: saveController,
        evidenceJpegBytes: usableEvidence,
      );
    } finally {
      saveController.dispose();
    }
    await _handleResultAction(result);
  }

  /// Persists one completed classroom attempt through the existing
  /// reference-match contract, then presents it in the shared result dialog.
  ///
  /// `save_reference_match_attempt` claims a new attempt slot on every call,
  /// so it is not idempotent: it runs exactly once and is never retried from
  /// here. A failed save keeps the result visible and reports the failure.
  Future<void> _presentClassroomResult({
    required CustomAssessmentSnapshot assessment,
    required int durationSeconds,
  }) async {
    final saveController = SessionSummarySaveController(
      save: () =>
          widget.classroomRepository!.saveCustomMovementAssignmentAttempt(
            assignment: widget.assignment!,
            traineeId: widget.traineeUid!,
            total: assessment.total!,
            performanceLevel: assessment.performanceLevel!,
            // Null components are "Not assessed" and must be kept, not
            // dropped or zeroed.
            componentScores: Map.of(assessment.componentScores),
          ),
    );
    SessionSummaryResult? result;
    try {
      // Settle the single save first so Practice Again reflects the attempt
      // this run consumed.
      await saveController.start();
      if (!mounted || _leaving) return;
      final saved = saveController.state == SessionSaveState.saved;
      final remaining = _classroomAttemptsRemaining;
      if (saved && remaining != null) {
        setState(
          () => _classroomAttemptsRemaining = math.max(0, remaining - 1),
        );
      }
      result = await CustomMovementResultDialog.show(
        context,
        movementName: widget.movement.name,
        durationSeconds: durationSeconds,
        assessment: assessment,
        saveController: saveController,
        contextLabel: CustomMovementResultDialog.classroomContextLabel,
        backLabel: CustomMovementResultDialog.classroomBackLabel,
        // A failed save may still have committed server-side (lost
        // response), so the local count is unknown: send the trainee back to
        // the assignment, which shows the authoritative attempts.
        showPracticeAgain: saved && _canPracticeAgain,
        allowSaveRetry: false,
        saveFailureMessage: _classroomSaveFailureMessage,
      );
    } finally {
      saveController.dispose();
    }
    await _handleResultAction(result);
  }

  Future<void> _handleResultAction(SessionSummaryResult? result) async {
    if (!mounted || _leaving) return;
    if (result == SessionSummaryResult.tryAgain) {
      await _tryAgain();
    } else {
      await _leave();
    }
  }

  /// Classroom runs may start another attempt only while one remains.
  bool get _canPracticeAgain =>
      widget.assignment == null ||
      _classroomAttemptsRemaining == null ||
      _classroomAttemptsRemaining! > 0;

  Future<void> _tryAgain() async {
    if (_busy ||
        _leaving ||
        _cameraSelectionBusy ||
        (_phase == _CustomPracticePhase.completed && !_canPracticeAgain) ||
        (_phase != _CustomPracticePhase.completed &&
            _phase != _CustomPracticePhase.failed)) {
      return;
    }
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.preparing;
      _failure = null;
      _readinessFeedback.value = null;
      _assessmentProgress.value = null;
    });
    try {
      await _releaseCamera();
      if (!mounted) return;
      await _prepareSession();
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _failure = _failureFor(
            error,
            fallback: 'Could not release the current camera. Retry setup.',
            isSetup: true,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Stable readiness may have arrived while this retry was busy.
        _maybeAutoStart();
      }
    }
  }

  Future<void> _releaseCamera() async {
    final sessionId = _sessionToRelease ?? _socket.currentSessionId;
    if (sessionId == null) return;
    _requireAccepted(await _socket.stopPracticeSession(sessionId: sessionId));
    _sessionToRelease = null;
  }

  Future<void> _switchCamera(String? _) async {
    if (_busy || !_cameraCanBeChanged) return;
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.preparing;
      _failure = null;
      _readinessFeedback.value = null;
      _preview.value = null;
      _presentation.value = null;
    });
    try {
      await _releaseCamera();
      if (!mounted) return;
      await _prepareSession();
    } catch (error) {
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _failure = _failureFor(
            error,
            fallback: 'Could not release the current camera. Retry setup.',
            isSetup: true,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cameraSelectionBusy = false;
        });
        _maybeAutoStart();
      }
    }
  }

  void _requireAccepted(CommandAck ack) {
    if (!ack.accepted) {
      throw _CustomCommandRejected(
        ack.errorCode ?? 'command_rejected',
        ack.message,
      );
    }
  }

  void _updateRecordingTime() {
    final deadline = _recordingDeadline;
    if (!mounted ||
        _phase != _CustomPracticePhase.recording ||
        deadline == null) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      return;
    }
    final remaining = (deadline.difference(widget.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, _captureDuration.inSeconds);
    if (remaining == 0) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      setState(() => _remainingSeconds = 0);
      unawaited(_finish());
    } else if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _showLiveCue(String cue, int sequence) {
    _liveCueTimer?.cancel();
    _liveCue.value = _CustomLiveCue(cue, sequence);
    _liveCueTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _liveCue.value?.sequence == sequence) {
        _liveCue.value = null;
      }
    });
  }

  void _clearLiveCue() {
    _liveCueTimer?.cancel();
    _liveCueTimer = null;
    _liveCue.value = null;
  }

  String _formatRemaining() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  _CustomPracticeFailure _failureFor(
    Object error, {
    required String fallback,
    bool isSetup = false,
  }) {
    if (error is _CustomPracticeFailure) return error;
    if (error is! _CustomCommandRejected) {
      return _CustomPracticeFailure(
        message: fallback,
        category: isSetup
            ? _CustomFailureCategory.setup
            : _CustomFailureCategory.operation,
      );
    }

    final message = switch (error.code) {
      'track_loss' =>
        'Required movement tracking was lost during the recording. Keep the selected prop and required hand or body visible throughout the full movement, then try again.',
      'missing_modality' =>
        'The assessment did not receive all required tracking inputs. Keep the selected prop and required hand or body visible throughout the full movement, then try again.',
      'prop_not_detected' =>
        'The selected prop was not detected during the attempt. Keep the whole prop inside the camera view while performing the movement.',
      'insufficient_frames' =>
        'The movement was not captured long enough. Perform the full movement before the recording ends.',
      'invalid_timestamps' =>
        'The movement timing could not be read. Start another practice attempt.',
      'insufficient_hand_coverage' =>
        'Hand tracking was lost too often during the movement. Keep your hand visible and try again.',
      'insufficient_orientation' =>
        'Bottle markers were not visible often enough to assess rotation. Improve lighting and keep both ends visible.',
      'custom_capture_not_recording' =>
        'No movement recording was available to assess. Start another practice attempt.',
      'custom_movement_not_detected' =>
        'No movement was detected. Move through the saved sequence while keeping the required inputs visible, then try again.',
      'custom_assessment_incomplete' =>
        'Movement was detected, but the full saved sequence was not completed within 30 seconds. Try again and continue through the ending.',
      'custom_position_not_detected' =>
        'The saved position was not detected. Move into the grip or stall and keep the required inputs visible.',
      'custom_hold_incomplete' =>
        'The position was detected but not held steadily long enough. Hold it for about one second and try again.',
      'invalid_schema' =>
        'The saved movement template could not be read. Reopen the movement and try again.',
      'readiness_not_stable' ||
      'readiness_stale' ||
      'readiness_not_confirmed' =>
        'Setup changed before recording. Keep the required inputs visible, then start again.',
      'camera_unavailable' ||
      'selected_camera_unavailable' ||
      'prepare_timeout' =>
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : fallback,
      'model_load_failed' || 'pipeline_init_failed' || 'pipeline_error' =>
        'ELIXR could not start or complete vision processing. Retry the session.',
      _ =>
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : fallback,
    };
    final category = isSetup
        ? _CustomFailureCategory.setup
        : switch (error.code) {
            'readiness_not_stable' ||
            'readiness_stale' ||
            'readiness_not_confirmed' ||
            'camera_unavailable' ||
            'selected_camera_unavailable' ||
            'prepare_timeout' => _CustomFailureCategory.setup,
            'track_loss' ||
            'prop_not_detected' ||
            'missing_modality' ||
            'insufficient_frames' ||
            'insufficient_hand_coverage' ||
            'insufficient_orientation' => _CustomFailureCategory.tracking,
            _ => _CustomFailureCategory.operation,
          };
    return _CustomPracticeFailure(message: message, category: category);
  }

  bool get _cameraCanBeChanged =>
      _phase == _CustomPracticePhase.setupChecking ||
      (_phase == _CustomPracticePhase.failed && _failure?.isSetup == true);

  Future<void> _stopSessionBestEffort() async {
    try {
      await _releaseCamera();
    } catch (_) {
      // Disconnect/dispose remains the final local lifecycle cleanup.
    }
  }

  /// Leaves the practice screen exactly once.
  ///
  /// Never gated on [_busy]: a failed, disconnected, or still-processing
  /// session must always be escapable. Cleanup is best effort and bounded by
  /// [_exitCleanupTimeout]; `stopPracticeSession` coalesces with any stop
  /// already in flight, so repeated exits never send duplicate stops.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _clearLiveCue();
    _stopPracticeAudio();
    try {
      await _releaseForExit().timeout(_exitCleanupTimeout);
    } on TimeoutException {
      // Navigate anyway; dispose closes whatever is still pending.
    }
    if (!mounted) return;
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
    } else {
      context.pop();
    }
  }

  Future<void> _releaseForExit() async {
    await _stopSessionBestEffort();
    if (_ownsSocket) {
      try {
        await _socket.disconnect();
      } catch (_) {
        // A lost connection has already released its backend session.
      }
    }
  }

  @override
  void dispose() {
    unawaited(_previewSubscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    _recordingTimer?.cancel();
    _liveCueTimer?.cancel();
    _liveCue.dispose();
    _preview.dispose();
    _presentation.dispose();
    _readinessFeedback.dispose();
    _assessmentProgress.dispose();
    // Disposal stops playback and releases the background-music lease.
    if (_musicInitialized) unawaited(_music.dispose());
    unawaited(_sfx.dispose());
    if (_ownsSocket) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mirrored = context.watch<SettingsService>().cameraMirrored;
    final savedInstructions = widget.movement.description.trim();
    final instruction = savedInstructions.isEmpty
        ? 'Execution instructions are unavailable. If you own this movement, edit it to add guidance; otherwise ask the owner to add them before you practice.'
        : savedInstructions;
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
                  AppSpacing.practiceMaxContentWidth,
                );
                final desktop =
                    contentWidth >= AppSpacing.practiceDesktopBreakpoint;
                final compact =
                    contentWidth >= AppSpacing.practiceCompactBreakpoint &&
                    !desktop;
                final isPreparing = _phase == _CustomPracticePhase.preparing;
                final isActive =
                    _phase == _CustomPracticePhase.recording ||
                    _phase == _CustomPracticePhase.processing;
                final header = TrainingSessionHeader(
                  onBack: _leave,
                  title: widget.movement.name,
                  statusPill: widget.movement.difficulty,
                  statusPillColor: trainingDifficultyColor(
                    widget.movement.difficulty,
                  ),
                  instruction: instruction,
                  connectionState: _socket.connectionState,
                  connecting: isPreparing,
                  wideLayout: desktop || compact,
                );
                final camera = TrainingCameraWorkspace(
                  frameListenable: _preview,
                  mirrored: mirrored,
                  connectionState: _socket.connectionState,
                  connecting: isPreparing,
                  isSessionActive: isActive,
                  isPreparingCamera: isPreparing,
                  accentBorder:
                      isPreparing ||
                      _phase == _CustomPracticePhase.setupChecking,
                  readyAura: _phase == _CustomPracticePhase.countdown,
                  idleTitle: 'Movement Assessment',
                  idleSubtitle: 'Complete setup before the timed assessment.',
                  idleCaption:
                      'Keep the required body, hands, and selected prop visible.',
                  errorMessage: _socket.errorMessage,
                  sessionError: _failure?.showsCameraRecovery == true
                      ? _failure?.message
                      : null,
                  onRetry: _tryAgain,
                  onCountdownComplete: () {},
                  overlays: _countdown == null
                      ? ValueListenableBuilder<_CustomLiveCue?>(
                          valueListenable: _liveCue,
                          builder: (context, cue, _) => cue == null
                              ? const SizedBox.shrink()
                              : Positioned(
                                  top: AppSpacing.md,
                                  left: AppSpacing.md,
                                  right: AppSpacing.md,
                                  child: _CustomLiveCueBadge(
                                    cue: cue,
                                    isStatic:
                                        widget
                                            .revision
                                            .template
                                            .movementBehavior ==
                                        'static',
                                  ),
                                ),
                        )
                      : _CustomCountdownOverlay(value: _countdown!),
                );
                final panel = _buildSessionPanel(
                  instruction: instruction,
                  desktop: desktop,
                );
                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, workspaceConstraints) {
                          final workspace = TrainingArenaWorkspace(
                            desktop: desktop,
                            contentWidth: contentWidth,
                            workspaceHeight: workspaceConstraints.maxHeight,
                            camera: camera,
                            panel: panel,
                          );
                          return desktop
                              ? workspace
                              : SingleChildScrollView(child: workspace);
                        },
                      ),
                    ),
                  ],
                );
                return constraints.maxWidth <=
                        AppSpacing.practiceMaxContentWidth
                    ? body
                    : Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: AppSpacing.practiceMaxContentWidth,
                          child: body,
                        ),
                      );
              },
            ),
          ),
        ),
      ),
    );
  }

  TrainingSessionPanel _buildSessionPanel({
    required String instruction,
    required bool desktop,
  }) {
    final showInstructions = switch (_phase) {
      _CustomPracticePhase.preparing ||
      _CustomPracticePhase.setupChecking => true,
      _ => false,
    };
    final setupPhase = _phase == _CustomPracticePhase.setupChecking;
    final detectionObserving = switch (_phase) {
      _CustomPracticePhase.setupChecking ||
      _CustomPracticePhase.countdown ||
      _CustomPracticePhase.recording ||
      _CustomPracticePhase.processing => true,
      _ => false,
    };
    final metrics = switch (_phase) {
      _CustomPracticePhase.preparing => const TrainingReadyBrief(
        title: 'Preparing camera',
        body: 'Initializing the camera and movement assessment.',
      ),
      _CustomPracticePhase.setupChecking => TrainingReadyBrief(
        title: 'Checking setup…',
        body: widget.revision.template.readinessGuidance,
      ),
      _CustomPracticePhase.countdown => TrainingReadyBrief(
        title: 'Get ready${_countdown == null ? '' : ' · $_countdown'}',
        body: 'Practice will begin when the countdown finishes.',
      ),
      _CustomPracticePhase.recording => TrainingReadyBrief(
        title: 'Recording · ${_formatRemaining()} max',
        body: widget.revision.template.movementBehavior == 'static'
            ? 'Move into the saved position and hold steady.'
            : 'Perform the complete saved sequence. ELIXR will finish when the sequence is observed.',
      ),
      _CustomPracticePhase.processing => const TrainingReadyBrief(
        title: 'Analyzing performance…',
        body:
            'ELIXR is comparing this performance with the learned movement pattern.',
      ),
      _CustomPracticePhase.completed => const TrainingReadyBrief(
        title: 'Assessment complete',
        body: 'Your result is shown in the session summary.',
      ),
      _CustomPracticePhase.failed => TrainingReadyBrief(
        title: 'Practice needs attention',
        body: _failure?.showsCameraRecovery == true
            ? 'See the camera status for the reason and retry guidance.'
            : 'Review the message below, then try again.',
      ),
    };
    final statusContent = _phase == _CustomPracticePhase.processing
        ? Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: ProgressRing(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Waiting for the assessment result from ELIXR.',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
            ],
          )
        : _phase == _CustomPracticePhase.recording
        ? ValueListenableBuilder<PracticeFeedback?>(
            valueListenable: _assessmentProgress,
            builder: (context, progress, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  progress?.feedback ?? 'Waiting for movement…',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildDetectionStatus(sessionObserving: detectionObserving),
              ],
            ),
          )
        : setupPhase
        ? ValueListenableBuilder<PracticeFeedback?>(
            valueListenable: _readinessFeedback,
            builder: (context, feedback, _) {
              final items = feedback?.readinessItems;
              if (items != null && items.isNotEmpty) {
                return ReadinessChecklistPanel(
                  items: items,
                  progress: feedback?.readinessStableProgress ?? 0,
                  stable: feedback?.readinessStable ?? false,
                  complete: feedback?.readinessComplete ?? false,
                );
              }
              return _buildDetectionStatus(
                sessionObserving: detectionObserving,
              );
            },
          )
        : _buildDetectionStatus(sessionObserving: detectionObserving);

    final cameraSetupAvailable = _cameraCanBeChanged && !_busy;
    final actionKind = switch (_phase) {
      _CustomPracticePhase.recording => TrainingActionKind.finish,
      _ => TrainingActionKind.start,
    };
    final actionLabel = switch (_phase) {
      _CustomPracticePhase.preparing => 'Preparing…',
      _CustomPracticePhase.setupChecking => 'Hold steady… starts automatically',
      _CustomPracticePhase.countdown => 'Get Ready…',
      _CustomPracticePhase.recording => 'Completes automatically',
      _CustomPracticePhase.processing => 'Analyzing performance…',
      _CustomPracticePhase.completed =>
        _canPracticeAgain ? 'Practice Again' : 'No attempts remaining',
      _CustomPracticePhase.failed =>
        _failure?.isSetup == true ? 'Retry Setup' : 'Practice Again',
    };
    final canRunAction = !_busy && !_cameraSelectionBusy;
    final action = switch (_phase) {
      _CustomPracticePhase.recording => null,
      _CustomPracticePhase.completed =>
        canRunAction && _canPracticeAgain ? _tryAgain : null,
      _CustomPracticePhase.failed => canRunAction ? _tryAgain : null,
      _ => null,
    };

    return TrainingSessionPanel(
      phase: _panelPhase,
      expandVertically: desktop && !showInstructions,
      metrics: showInstructions
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInstructionsSection(context, instruction),
                const SizedBox(height: AppSpacing.sm),
                metrics,
              ],
            )
          : metrics,
      statusContent: statusContent,
      supportingContent: Column(
        children: [
          SessionSetupRow(
            icon: FluentIcons.play_solid,
            label: 'Movement',
            value: widget.movement.name,
          ),
          SessionSetupRow(
            icon: FluentIcons.speed_high,
            label: 'Difficulty',
            value: widget.movement.difficulty,
          ),
          SessionSetupRow(
            icon: FluentIcons.diet_plan_notebook,
            label: 'Prop',
            value: widget.movement.propType.displayLabel,
          ),
          const SessionSetupRow(
            icon: FluentIcons.completed_solid,
            label: 'Assessment',
            value: 'Reference matched',
          ),
          SessionSetupRow(
            icon: FluentIcons.contact,
            label: 'Session',
            value: widget.assignment == null
                ? 'Personal practice'
                : 'Classroom assessment',
          ),
          if (cameraSetupAvailable) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            CameraSourcePreference(
              settings: context.watch<SettingsService>(),
              cameras: context.watch<CameraDeviceService>(),
              compact: true,
              enabled: !_busy && !_cameraSelectionBusy,
              onSelectionBusyChanged: (busy) {
                if (!mounted) return;
                setState(() => _cameraSelectionBusy = busy);
                if (!busy) _maybeAutoStart();
              },
              onSelectionSaved: _switchCamera,
            ),
          ],
        ],
      ),
      compactStatusNote: _failure != null
          ? Text(
              _failure!.message,
              style: AppTheme.bodySecondary.copyWith(color: AppColors.error),
            )
          : null,
      actionArea: TrainingActionArea(
        kind: actionKind,
        startLabel: actionLabel,
        finishLabel: actionLabel,
        isLoading:
            _busy ||
            _phase == _CustomPracticePhase.preparing ||
            _phase == _CustomPracticePhase.countdown ||
            _cameraSelectionBusy,
        onPressed: action,
      ),
    );
  }

  Widget _buildInstructionsSection(BuildContext context, String instruction) {
    return Container(
      key: const ValueKey('custom-movement-instructions'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.practiceSectionSurface(
        context,
        accent: AppColors.primary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How to perform',
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            instruction,
            key: const ValueKey('custom-movement-instructions-text'),
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionStatus({required bool sessionObserving}) {
    return ValueListenableBuilder<PreviewFrame?>(
      valueListenable: _presentation,
      builder: (context, presentation, _) => TrainingStatusRow(
        detection: resolvePresentationDetectionStatus(
          sessionObserving: sessionObserving,
          propPresentationState: presentation?.propPresentationState,
        ),
        propLabel: widget.movement.propType.displayLabel,
        handLabel: modalityPresentationLabel(
          label: 'Hand',
          required: _handsRequired,
          presentationState: presentation?.handsPresentationState,
        ),
        bodyLabel: modalityPresentationLabel(
          label: 'Body',
          required: _poseRequired,
          presentationState: presentation?.posePresentationState,
        ),
      ),
    );
  }

  TrainingSessionPhase get _panelPhase => switch (_phase) {
    _CustomPracticePhase.preparing => TrainingSessionPhase.preparingCamera,
    _CustomPracticePhase.setupChecking => TrainingSessionPhase.readiness,
    _CustomPracticePhase.countdown => TrainingSessionPhase.getReady,
    _CustomPracticePhase.recording => TrainingSessionPhase.recording,
    _CustomPracticePhase.processing => TrainingSessionPhase.processing,
    _CustomPracticePhase.completed => TrainingSessionPhase.completed,
    _CustomPracticePhase.failed =>
      _failure?.isSetup == true
          ? TrainingSessionPhase.cameraError
          : TrainingSessionPhase.failed,
  };

  bool get _handsRequired =>
      widget.revision.template.featureCapabilities['hands'] == true;

  bool get _poseRequired =>
      widget.revision.template.featureCapabilities['pose'] == true;
}

class _CustomCountdownOverlay extends StatelessWidget {
  const _CustomCountdownOverlay({required this.value});
  final int value;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(colors: [Color(0x1A7D4CFF), Color(0x9907060C)]),
    ),
    child: Center(
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 108,
          fontWeight: FontWeight.w900,
          color: AppColors.primary,
          shadows: [
            Shadow(
              color: AppColors.primary.withValues(alpha: .7),
              blurRadius: 28,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CustomLiveCue {
  const _CustomLiveCue(this.kind, this.sequence);
  final String kind;
  final int sequence;
}

class _CustomLiveCueBadge extends StatelessWidget {
  const _CustomLiveCueBadge({required this.cue, required this.isStatic});
  final _CustomLiveCue cue;
  final bool isStatic;

  @override
  Widget build(BuildContext context) {
    final label = switch (cue.kind) {
      'movement_detected' => 'MOVEMENT DETECTED',
      'keep_going' => 'KEEP GOING',
      'finish_sequence' => 'FINISH THE SEQUENCE',
      'release' => 'RELEASE',
      'airborne' => 'AIRBORNE',
      'apex' => 'APEX',
      'catch' => 'CATCH',
      'position_detected' => 'POSITION DETECTED',
      'hold_steady' => 'HOLD STEADY',
      'completed' => isStatic ? 'HOLD COMPLETE' : 'SEQUENCE COMPLETE',
      _ => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    final color = cue.kind == 'completed'
        ? AppColors.success
        : AppColors.primary;
    final highContrast = context.isHighContrast;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('custom-cue-${cue.sequence}'),
            tween: Tween(begin: reduceMotion ? 1 : .88, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 230),
            curve: Curves.easeOut,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: reduceMotion ? 1 : scale.clamp(0.0, 1.0),
                child: child,
              ),
            ),
            child: Container(
              key: const ValueKey('custom-live-cue'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: const Color(0xE6101018),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color, width: highContrast ? 2 : 1.5),
                boxShadow: highContrast
                    ? const []
                    : [
                        BoxShadow(
                          color: color.withValues(alpha: .25),
                          blurRadius: 14,
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.lightning_bolt, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
