import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/custom_movement.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/websocket_service.dart';

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
  Uint8List? _preview;
  bool _preparing = true;
  bool _ready = false;
  bool _active = false;
  bool _busy = false;
  int? _countdown;
  String? _error;
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
      if (mounted && frame.hasJpeg) setState(() => _preview = frame.jpegBytes);
    });
    _feedbackSubscription = _socket.feedbackStream.listen((feedback) {
      if (!mounted || _active) return;
      setState(() => _ready = feedback.readinessStable == true);
    });
    await _prepareSession();
  }

  Future<void> _prepareSession() async {
    if (mounted) {
      setState(() {
        _preparing = true;
        _ready = false;
        _active = false;
        _error = null;
      });
    }
    try {
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('backend unavailable');
      final sessionId = _socket.beginPracticeAttempt();
      _requireAccepted(
        await _socket.sendPrepare(
          movement: 'Custom Movement',
          difficulty: widget.movement.difficulty,
          prop: widget.movement.propType,
          sessionId: sessionId,
          sessionMode: 'custom_assessment',
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
        });
      }
    }
  }

  Future<void> _start() async {
    if (_busy || !_ready || _active) return;
    setState(() {
      _busy = true;
      _error = null;
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
          _result = assessment;
        });
      }
    } catch (_) {
      await _stopSessionBestEffort();
      if (mounted) {
        setState(() {
          _active = false;
          _ready = false;
          _error =
              'The performance could not be assessed. Reposition and retry.';
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
    if (_ownsSocket) _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return ElixScaffoldPage(
      header: PageHeader(
        title: Text(widget.movement.name),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: _busy ? null : () => context.pop(),
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: _preview == null
                      ? const ProgressRing()
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_preview!, fit: BoxFit.contain),
                            if (_countdown != null)
                              Center(
                                child: Text(
                                  '$_countdown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 72,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.movement.description),
                  const SizedBox(height: 12),
                  Text(
                    _preparing
                        ? 'Preparing camera…'
                        : _active
                        ? 'Perform the full movement, then finish.'
                        : _ready
                        ? 'Ready to begin.'
                        : widget.revision.template.readinessGuidance,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('custom-practice-primary'),
                    onPressed: _busy || _preparing
                        ? null
                        : (_active
                              ? _finish
                              : (result != null || _error != null)
                              ? _tryAgain
                              : (_ready ? _start : null)),
                    child: Text(
                      _active
                          ? 'Finish & Assess'
                          : result != null
                          ? 'Practice Again'
                          : _error != null
                          ? 'Retry Setup'
                          : 'Start Practice',
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    InfoBar(
                      title: Text(
                        'Score ${(result['score_percent'] as num?)?.round() ?? 0}%',
                      ),
                      content: Text(
                        'Rubric ${(result['total'] as num?)?.toInt() ?? 0}/12 · ${result['performance_level'] ?? ''}',
                      ),
                      severity: InfoBarSeverity.success,
                    ),
                    const SizedBox(height: 8),
                    for (final line
                        in (result['feedback'] as List? ?? const [])
                            .whereType<String>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(line),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      widget.assignment == null
                          ? 'Personal result only · no global XP or leaderboard progress'
                          : 'Classroom result saved · no global XP or leaderboard progress',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    InfoBar(
                      title: const Text('Practice issue'),
                      content: Text(_error!),
                      severity: InfoBarSeverity.error,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
