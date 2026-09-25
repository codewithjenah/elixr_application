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
import '../../services/websocket_service.dart';
import '../../services/settings_service.dart';
import '../../services/camera_device_service.dart';
import '../settings/widgets/camera_source_preference.dart';
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
  });

  final CustomMovement movement;
  final CustomMovementRevision revision;
  final CustomMovementRepository repository;
  final GroupAssignment? assignment;
  final String? traineeUid;
  final ClassroomAssignmentRepository? classroomRepository;
  final WebSocketService? webSocket;

  /// Allows routed personal practice to return to its canonical origin without
  /// changing the pop behavior used by assignment and teacher flows.
  final VoidCallback? onExit;

  @override
  State<CustomMovementPracticeScreen> createState() =>
      _CustomMovementPracticeScreenState();
}

enum _CustomPracticePhase {
  preparing,
  setupChecking,
  readyToStart,
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
  _CustomPracticePhase _phase = _CustomPracticePhase.preparing;
  bool _busy = false;
  bool _cameraSelectionBusy = false;
  int? _countdown;
  Map<String, dynamic>? _result;
  _CustomPracticeFailure? _failure;
  String? _resultSaveWarning;
  String? _sessionToRelease;
  DateTime? _practiceStartedAt;
  DateTime? _recordingDeadline;
  Timer? _recordingTimer;
  int _remainingSeconds = _captureDuration.inSeconds;

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    unawaited(_prepare());
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
      if (_phase == _CustomPracticePhase.setupChecking ||
          _phase == _CustomPracticePhase.readyToStart) {
        final nextPhase = feedback.readinessStable == true
            ? _CustomPracticePhase.readyToStart
            : _CustomPracticePhase.setupChecking;
        if (nextPhase != _phase) setState(() => _phase = nextPhase);
      }
      if (feedback.customAssessmentProgress != null) {
        _assessmentProgress.value = feedback;
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
    if (mounted) {
      setState(() {
        _phase = _CustomPracticePhase.preparing;
        _failure = null;
        _result = null;
        _resultSaveWarning = null;
        _countdown = null;
        _remainingSeconds = _captureDuration.inSeconds;
        _recordingDeadline = null;
        _recordingTimer?.cancel();
        _recordingTimer = null;
        _readinessFeedback.value = null;
        _assessmentProgress.value = null;
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
        setState(
          () => _phase = _readinessFeedback.value?.readinessStable == true
              ? _CustomPracticePhase.readyToStart
              : _CustomPracticePhase.setupChecking,
        );
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

  Future<void> _start() async {
    if (_busy || _phase != _CustomPracticePhase.readyToStart) return;
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.countdown;
      _failure = null;
      _result = null;
      _resultSaveWarning = null;
    });
    try {
      _requireAccepted(await _socket.sendConfirmReadiness());
      for (var value = 3; value >= 1; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
      _requireAccepted(await _socket.sendActivate());
      _requireAccepted(
        await _socket.sendStartCustomCapture(durationSeconds: 30),
      );
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.recording;
          _practiceStartedAt = DateTime.now();
          _recordingDeadline = DateTime.now().add(_captureDuration);
          _remainingSeconds = _captureDuration.inSeconds;
        });
        _recordingTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _updateRecordingTime(),
        );
      }
    } catch (error) {
      // Activation may already have succeeded before capture startup fails.
      // Release the backend session before showing a failed state with no
      // active-session controls.
      await _stopSessionBestEffort();
      _recordingTimer?.cancel();
      _recordingTimer = null;
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
    if (_busy || _phase != _CustomPracticePhase.recording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.processing;
      _failure = null;
      _resultSaveWarning = null;
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
      final percent = (assessment['score_percent'] as num?)?.toDouble();
      final rawComponents = assessment['component_scores'];
      final componentScores = <String, double>{};
      if (rawComponents is Map) {
        for (final entry in rawComponents.entries) {
          if (entry.key is String && entry.value is num) {
            componentScores[entry.key as String] = (entry.value as num)
                .toDouble();
          }
        }
      }
      final feedback = assessment['feedback'] is List
          ? (assessment['feedback'] as List).whereType<String>().toList()
          : <String>[];
      final assignment = widget.assignment;
      final total = (assessment['total'] as num?)?.toInt();
      final level = assessment['performance_level'] as String?;
      if (assignment != null &&
          (total == null ||
              level == null ||
              widget.traineeUid == null ||
              widget.classroomRepository == null)) {
        throw const _CustomPracticeFailure(
          message:
              'The assessment result was incomplete. Start another practice attempt.',
          category: _CustomFailureCategory.operation,
        );
      }
      if (assignment == null && percent == null) {
        throw const _CustomPracticeFailure(
          message:
              'The assessment result was incomplete. Start another practice attempt.',
          category: _CustomFailureCategory.operation,
        );
      }

      String? resultSaveWarning;
      if (assignment != null) {
        final scores = componentScores.map(
          (key, value) => MapEntry(key, value.toInt()),
        );
        try {
          await widget.classroomRepository!.saveCustomMovementAssignmentAttempt(
            assignment: assignment,
            traineeId: widget.traineeUid!,
            total: total!,
            performanceLevel: level!,
            componentScores: scores,
          );
        } catch (_) {
          // Assessment succeeded; keep its result visible and report the save issue.
          resultSaveWarning =
              'Assessment complete, but the classroom result could not be saved.';
        }
      } else if (percent != null) {
        try {
          final sessionId = widget.repository.allocateSessionId();
          await widget.repository.savePersonalResult(
            ownerUid: widget.movement.ownerUid,
            movementId: widget.movement.id,
            revisionId: widget.revision.id,
            totalScore: percent,
            componentScores: componentScores,
            feedback: feedback,
            sessionId: sessionId,
            movementName: widget.movement.name,
            difficulty: widget.movement.difficulty,
            propType: widget.movement.propType,
            durationSeconds: DateTime.now()
                .difference(_practiceStartedAt ?? DateTime.now())
                .inSeconds
                .clamp(0, 86400)
                .toInt(),
            referenceImageStoragePath:
                widget.movement.referenceImageStoragePath,
          );
        } catch (_) {
          // A repository failure must not be mislabeled as assessment failure.
          resultSaveWarning =
              'Assessment complete, but the personal result could not be saved.';
        }
      }
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.completed;
          _presentation.value = null;
          _result = assessment;
          _resultSaveWarning = resultSaveWarning;
        });
      }
    } catch (error) {
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _phase = _CustomPracticePhase.failed;
          _presentation.value = null;
          _failure = _failureFor(error, fallback: _assessmentFailureMessage);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tryAgain() async {
    if (_busy ||
        _cameraSelectionBusy ||
        (_phase != _CustomPracticePhase.completed &&
            _phase != _CustomPracticePhase.failed)) {
      return;
    }
    setState(() {
      _busy = true;
      _phase = _CustomPracticePhase.preparing;
      _result = null;
      _failure = null;
      _resultSaveWarning = null;
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
      if (mounted) setState(() => _busy = false);
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
    final remaining =
        (deadline.difference(DateTime.now()).inMilliseconds / 1000)
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
      _phase == _CustomPracticePhase.readyToStart ||
      (_phase == _CustomPracticePhase.failed && _failure?.isSetup == true);

  Future<void> _stopSessionBestEffort() async {
    try {
      await _releaseCamera();
    } catch (_) {
      // Disconnect/dispose remains the final local lifecycle cleanup.
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() => _busy = true);
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _stopSessionBestEffort();
    if (_ownsSocket) await _socket.disconnect();
    if (!mounted) return;
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
    } else {
      context.pop();
    }
  }

  @override
  void dispose() {
    unawaited(_previewSubscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    _recordingTimer?.cancel();
    _preview.dispose();
    _presentation.dispose();
    _readinessFeedback.dispose();
    _assessmentProgress.dispose();
    if (_ownsSocket) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
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
                      (_phase == _CustomPracticePhase.setupChecking &&
                          result == null),
                  readyAura: _phase == _CustomPracticePhase.readyToStart,
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
                      ? null
                      : _CustomCountdownOverlay(value: _countdown!),
                );
                final panel = _buildSessionPanel(
                  result,
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

  TrainingSessionPanel _buildSessionPanel(
    Map<String, dynamic>? result, {
    required String instruction,
    required bool desktop,
  }) {
    final showInstructions = switch (_phase) {
      _CustomPracticePhase.preparing ||
      _CustomPracticePhase.setupChecking ||
      _CustomPracticePhase.readyToStart => true,
      _ => false,
    };
    final setupPhase =
        _phase == _CustomPracticePhase.setupChecking ||
        _phase == _CustomPracticePhase.readyToStart;
    final detectionObserving = switch (_phase) {
      _CustomPracticePhase.setupChecking ||
      _CustomPracticePhase.readyToStart ||
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
      _CustomPracticePhase.readyToStart => const TrainingReadyBrief(
        title: 'Ready to Practice',
        body: 'Your setup is stable. Start when you are ready.',
      ),
      _CustomPracticePhase.countdown => TrainingReadyBrief(
        title: 'Get ready${_countdown == null ? '' : ' · $_countdown'}',
        body: 'Practice will begin when the countdown finishes.',
      ),
      _CustomPracticePhase.recording => TrainingReadyBrief(
        title: 'Recording · ${_formatRemaining()} max',
        body:
            'Move through the full saved pattern. ELIXR will finish when it detects the sequence, or at the 30-second limit.',
      ),
      _CustomPracticePhase.processing => const TrainingReadyBrief(
        title: 'Analyzing performance…',
        body:
            'ELIXR is comparing this performance with the learned movement pattern.',
      ),
      _CustomPracticePhase.completed =>
        result == null
            ? const TrainingReadyBrief(
                title: 'Assessment complete',
                body: 'Your movement score is ready.',
              )
            : _CustomAssessmentResult(result: result),
      _CustomPracticePhase.failed => TrainingReadyBrief(
        title: 'Practice needs attention',
        body: _failure?.showsCameraRecovery == true
            ? 'See the camera status for the reason and retry guidance.'
            : 'Review the message below, then try again.',
      ),
    };
    final statusContent = result != null
        ? _CustomResultStatus(assignment: widget.assignment != null)
        : _phase == _CustomPracticePhase.processing
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
                  stable: _phase == _CustomPracticePhase.readyToStart,
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
      _CustomPracticePhase.setupChecking ||
      _CustomPracticePhase.readyToStart => 'Start Practice',
      _CustomPracticePhase.countdown => 'Get Ready…',
      _CustomPracticePhase.recording => 'Completes automatically',
      _CustomPracticePhase.processing => 'Analyzing performance…',
      _CustomPracticePhase.completed => 'Practice Again',
      _CustomPracticePhase.failed =>
        _failure?.isSetup == true ? 'Retry Setup' : 'Practice Again',
    };
    final canRunAction = !_busy && !_cameraSelectionBusy;
    final action = switch (_phase) {
      _CustomPracticePhase.readyToStart => canRunAction ? _start : null,
      _CustomPracticePhase.recording => null,
      _CustomPracticePhase.completed ||
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
                if (mounted) setState(() => _cameraSelectionBusy = busy);
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
          : _resultSaveWarning == null
          ? null
          : Text(
              _resultSaveWarning!,
              style: AppTheme.bodySecondary.copyWith(color: AppColors.warning),
            ),
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
    _CustomPracticePhase.readyToStart => TrainingSessionPhase.ready,
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

class _CustomAssessmentResult extends StatelessWidget {
  const _CustomAssessmentResult({required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) {
    final components = result['component_scores'] as Map? ?? const {};
    final feedback = (result['feedback'] as List? ?? const [])
        .whereType<String>();
    return Container(
      key: const ValueKey('custom-assessment-result'),
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: AppTheme.practiceSectionSurface(
        context,
        accent: AppColors.success,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AUTOMATIC ASSESSMENT',
            style: AppTheme.caption.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(result['score_percent'] as num?)?.round() ?? 0}%',
            style: AppTheme.metric(context, color: AppColors.primary),
          ),
          Text(
            'Rubric ${(result['total'] as num?)?.toInt() ?? 0} / 12 · ${result['performance_level'] ?? ''}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in components.entries)
            _ResultLine(
              label: _componentLabel(entry.key.toString()),
              value: entry.value,
            ),
          for (final message in feedback)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _componentLabel(String key) => switch (key) {
    'body_technique' => 'Body technique',
    'hand_technique' => 'Hand technique',
    'prop_path' => 'Prop path',
    'timing' => 'Timing',
    'control_stability' => 'Control / stability',
    _ => key,
  };
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.label, required this.value});
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ),
        Text(
          '$value',
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
        ),
      ],
    ),
  );
}

class _CustomResultStatus extends StatelessWidget {
  const _CustomResultStatus({required this.assignment});
  final bool assignment;
  @override
  Widget build(BuildContext context) => Text(
    assignment
        ? 'Classroom result saved · No global XP'
        : 'Personal result only · No global XP',
    style: AppTheme.bodySecondary.copyWith(color: context.elixTextSecondary),
  );
}
