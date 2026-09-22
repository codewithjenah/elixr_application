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
import '../practice/widgets/training_action_area.dart';
import '../practice/widgets/training_arena_layout.dart';
import '../practice/widgets/training_camera_workspace.dart';
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
  });

  final CustomMovement movement;
  final CustomMovementRevision revision;
  final CustomMovementRepository repository;
  final GroupAssignment? assignment;
  final String? traineeUid;
  final ClassroomAssignmentRepository? classroomRepository;
  final WebSocketService? webSocket;

  @override
  State<CustomMovementPracticeScreen> createState() =>
      _CustomMovementPracticeScreenState();
}

class _CustomMovementPracticeScreenState
    extends State<CustomMovementPracticeScreen> {
  late final WebSocketService _socket;
  late final bool _ownsSocket;
  StreamSubscription<PreviewFrame>? _previewSubscription;
  StreamSubscription<PracticeFeedback>? _feedbackSubscription;
  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<PreviewFrame?> _presentation =
      ValueNotifier<PreviewFrame?>(null);
  bool _preparing = true;
  bool _ready = false;
  bool _active = false;
  bool _busy = false;
  int? _countdown;
  String? _error;
  bool _isSetupError = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    _previewSubscription = _socket.previewStream.listen((frame) {
      if (!mounted) return;
      _presentation.value = frame;
      if (!frame.hasJpeg) return;
      _preview.value = frame.jpegBytes;
    });
    _feedbackSubscription = _socket.feedbackStream.listen((feedback) {
      if (!mounted) return;

      // Preview JPEGs and their presentation state are delivered through the
      // separate ValueNotifier path. Feedback remains authoritative only for
      // the readiness gate.
      final readinessChanged =
          !_active && _ready != (feedback.readinessStable == true);
      if (readinessChanged) {
        setState(() {
          if (!_active) _ready = feedback.readinessStable == true;
        });
      }
    });
    await _prepareSession();
  }

  Future<void> _prepareSession() async {
    final settings = context.read<SettingsService>();
    if (mounted) {
      setState(() {
        _preparing = true;
        _ready = false;
        _active = false;
        _error = null;
        _isSetupError = false;
        _presentation.value = null;
      });
    }
    try {
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('backend unavailable');
      final sessionId = _socket.beginPracticeAttempt();
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
      if (mounted) setState(() => _preparing = false);
    } catch (_) {
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = 'Could not prepare the camera and movement model.';
          _isSetupError = true;
        });
      }
    }
  }

  Future<void> _start() async {
    if (_busy || !_ready || _active) return;
    setState(() {
      _busy = true;
      _error = null;
      _isSetupError = false;
      _result = null;
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
      if (mounted) setState(() => _active = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start practice. Retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy || !_active) return;
    setState(() => _busy = true);
    try {
      final stopped = await _socket.sendStopCustomCapture();
      if (!stopped.accepted) throw StateError(stopped.errorCode ?? 'invalid');
      final ack = await _socket.sendFinishCustomAssessment();
      final assessment = ack.customAssessment;
      if (!ack.accepted || assessment == null) {
        throw StateError(ack.errorCode ?? 'assessment failed');
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
      if (assignment != null) {
        final total = (assessment['total'] as num?)?.toInt();
        final level = assessment['performance_level'] as String?;
        final scores = componentScores.map(
          (key, value) => MapEntry(key, value.toInt()),
        );
        if (total == null ||
            level == null ||
            widget.traineeUid == null ||
            widget.classroomRepository == null) {
          throw StateError('Incomplete assignment result');
        }
        await widget.classroomRepository!.saveCustomMovementAssignmentAttempt(
          assignment: assignment,
          traineeId: widget.traineeUid!,
          total: total,
          performanceLevel: level,
          componentScores: scores,
        );
      } else if (percent != null) {
        await widget.repository.savePersonalResult(
          ownerUid: widget.movement.ownerUid,
          movementId: widget.movement.id,
          revisionId: widget.revision.id,
          totalScore: percent,
          componentScores: componentScores,
          feedback: feedback,
        );
      }
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _active = false;
          _ready = false;
          _presentation.value = null;
          _result = assessment;
        });
      }
    } catch (_) {
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _active = false;
          _ready = false;
          _presentation.value = null;
          _error =
              'The performance could not be assessed. Reposition and retry.';
          _isSetupError = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tryAgain() async {
    if (_busy || _preparing) return;
    setState(() {
      _result = null;
      _error = null;
      _isSetupError = false;
    });
    await _prepareSession();
  }

  void _requireAccepted(CommandAck ack) {
    if (!ack.accepted) {
      throw StateError(ack.errorCode ?? ack.message ?? 'Command rejected');
    }
  }

  Future<void> _stopSessionBestEffort() async {
    try {
      await _socket.stopPracticeSession();
    } catch (_) {
      // Disconnect/dispose remains the final local lifecycle cleanup.
    }
  }

  @override
  void dispose() {
    unawaited(_previewSubscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    _preview.dispose();
    _presentation.dispose();
    if (_ownsSocket) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final mirrored = context.watch<SettingsService>().cameraMirrored;
    final instruction = widget.movement.description.trim().isEmpty
        ? 'Perform the movement as demonstrated in your saved references.'
        : widget.movement.description;
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
                final header = TrainingSessionHeader(
                  onBack: () {
                    if (!_busy) context.pop();
                  },
                  title: widget.movement.name,
                  statusPill: widget.movement.difficulty,
                  statusPillColor: trainingDifficultyColor(
                    widget.movement.difficulty,
                  ),
                  instruction: instruction,
                  connectionState: _socket.connectionState,
                  connecting: _preparing,
                  wideLayout: desktop || compact,
                );
                final camera = TrainingCameraWorkspace(
                  frameListenable: _preview,
                  mirrored: mirrored,
                  connectionState: _socket.connectionState,
                  connecting: _preparing,
                  isSessionActive: _active,
                  isPreparingCamera: _preparing,
                  accentBorder:
                      _preparing ||
                      (!_ready && result == null && _error == null),
                  readyAura: _ready && !_active && _countdown == null,
                  idleTitle: 'Movement Assessment',
                  idleSubtitle:
                      'Complete setup, then perform your recorded movement.',
                  idleCaption:
                      'Keep the required body, hands, and selected prop visible.',
                  errorMessage: _socket.errorMessage,
                  sessionError: _isSetupError ? _error : null,
                  onRetry: _tryAgain,
                  onCountdownComplete: () {},
                  overlays: _countdown == null
                      ? null
                      : _CustomCountdownOverlay(value: _countdown!),
                );
                final panel = _buildSessionPanel(result);
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

  TrainingSessionPanel _buildSessionPanel(Map<String, dynamic>? result) {
    final phase = _panelPhase(result);
    final detectionObserving =
        !_preparing && result == null && _error == null && !_isSetupError;
    final propLabel = widget.movement.propType.displayLabel;
    final setupText = _preparing
        ? 'Checking setup…'
        : _active
        ? 'Perform the full movement, then finish when you are done.'
        : _ready
        ? 'Your setup is stable. Start when ready.'
        : widget.revision.template.readinessGuidance;
    return TrainingSessionPanel(
      phase: phase,
      expandVertically: true,
      metrics: result == null
          ? TrainingReadyBrief(
              title: _preparing
                  ? 'Preparing camera'
                  : _active
                  ? 'Assessment in progress'
                  : _ready
                  ? 'Ready to practice'
                  : 'Setup check',
              body: setupText,
            )
          : _CustomAssessmentResult(result: result),
      statusContent: result != null
          ? _CustomResultStatus(assignment: widget.assignment != null)
          : ValueListenableBuilder<PreviewFrame?>(
              valueListenable: _presentation,
              builder: (context, presentation, _) => TrainingStatusRow(
                detection: resolvePresentationDetectionStatus(
                  sessionObserving: detectionObserving,
                  propPresentationState: presentation?.propPresentationState,
                ),
                propLabel: propLabel,
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
            ),
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
        ],
      ),
      compactStatusNote: _error == null
          ? null
          : Text(
              _error!,
              style: AppTheme.bodySecondary.copyWith(color: AppColors.error),
            ),
      actionArea: TrainingActionArea(
        kind: _active ? TrainingActionKind.finish : TrainingActionKind.start,
        startLabel: result != null
            ? 'Practice Again'
            : _error != null
            ? (_isSetupError ? 'Retry Setup' : 'Practice Again')
            : 'Start Practice',
        isLoading: _busy || _preparing,
        onPressed: _busy || _preparing
            ? null
            : _active
            ? _finish
            : (result != null || _error != null)
            ? _tryAgain
            : _ready
            ? _start
            : null,
      ),
    );
  }

  TrainingSessionPhase _panelPhase(Map<String, dynamic>? result) {
    if (_error != null && _isSetupError) {
      return TrainingSessionPhase.cameraError;
    }
    if (result != null) return TrainingSessionPhase.completed;
    if (_active) return TrainingSessionPhase.inProgress;
    if (_countdown != null) return TrainingSessionPhase.getReady;
    if (_preparing) return TrainingSessionPhase.preparingCamera;
    return _ready ? TrainingSessionPhase.ready : TrainingSessionPhase.readiness;
  }

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
