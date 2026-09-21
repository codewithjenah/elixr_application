import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/movement_template.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/teacher_activity_assessment.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../services/websocket_service.dart';

class CustomReferenceRecorderDialog extends StatefulWidget {
  const CustomReferenceRecorderDialog({
    super.key,
    required this.difficulty,
    required this.prop,
    this.webSocket,
  });

  final String difficulty;
  final TrainingProp prop;
  final WebSocketService? webSocket;

  static Future<MovementTemplate?> show(
    BuildContext context, {
    required String difficulty,
    required TrainingProp prop,
  }) => showDialog<MovementTemplate>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        CustomReferenceRecorderDialog(difficulty: difficulty, prop: prop),
  );

  @override
  State<CustomReferenceRecorderDialog> createState() =>
      _CustomReferenceRecorderDialogState();
}

class _CustomReferenceRecorderDialogState
    extends State<CustomReferenceRecorderDialog> {
  late final WebSocketService _socket;
  late final bool _ownsSocket;
  StreamSubscription<PreviewFrame>? _previewSubscription;
  StreamSubscription<PracticeFeedback>? _feedbackSubscription;
  Uint8List? _preview;
  bool _initializing = true;
  bool _ready = false;
  bool _active = false;
  bool _recording = false;
  bool _busy = false;
  int _referenceCount = 0;
  int? _countdown;
  String? _error;
  String _quality = 'Position yourself and the selected prop in view.';

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _previewSubscription = _socket.previewStream.listen((frame) {
      if (!mounted || !frame.hasJpeg) return;
      setState(() => _preview = frame.jpegBytes);
    });
    _feedbackSubscription = _socket.feedbackStream.listen((feedback) {
      if (!mounted) return;
      setState(() {
        _ready = feedback.readinessStable == true;
        if (!_ready) _quality = feedback.feedback;
      });
    });
    try {
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('Backend unavailable');
      final sessionId = _socket.beginPracticeAttempt();
      _requireAccepted(
        await _socket.sendPrepare(
          movement: 'Custom Movement',
          difficulty: widget.difficulty,
          prop: widget.prop,
          sessionId: sessionId,
          sessionMode: 'custom_capture',
          readinessSpec: const TeacherActivityReadinessSpec(
            hands: ActivityHandRequirement.twoHands,
            body: ActivityBodyRequirement.upperBody,
          ),
        ),
      );
      _requireAccepted(await _socket.sendBeginReadiness(sessionId: sessionId));
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (_) {
      unawaited(_stopSessionBestEffort());
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera preparation failed. Check the backend and camera.';
      });
    }
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_active) {
        _requireAccepted(await _socket.sendConfirmReadiness());
        for (var value = 3; value >= 1; value--) {
          if (!mounted) return;
          setState(() => _countdown = value);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!mounted) return;
        setState(() => _countdown = null);
        _requireAccepted(await _socket.sendActivate());
        _active = true;
      } else {
        for (var value = 3; value >= 1; value--) {
          if (!mounted) return;
          setState(() => _countdown = value);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!mounted) return;
        setState(() => _countdown = null);
      }
      _requireAccepted(
        await _socket.sendStartCustomCapture(durationSeconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _quality = 'Recording the full movement…';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not start recording. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      final ack = await _socket.sendStopCustomCapture();
      if (!ack.accepted) {
        throw StateError(ack.message ?? ack.errorCode ?? 'invalid reference');
      }
      final count = ack.referenceCount ?? (_referenceCount + 1);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _referenceCount = count;
        _quality = ack.message ?? 'Reference accepted.';
      });
      if (count >= MovementTemplate.minimumReferences) {
        final built = await _socket.sendBuildCustomTemplate();
        final template = MovementTemplate.tryFrom(built.movementTemplate);
        if (!built.accepted || template == null || !template.isReady) {
          throw StateError('Template creation failed');
        }
        await _stopSessionBestEffort();
        if (mounted) Navigator.of(context).pop(template);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'This reference was not usable. Reposition and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardLast() async {
    if (_busy || _recording || _referenceCount == 0) return;
    setState(() => _busy = true);
    try {
      final ack = await _socket.sendDiscardCustomReference();
      if (!ack.accepted) throw StateError('discard rejected');
      if (mounted) {
        setState(() {
          _referenceCount = ack.referenceCount ?? (_referenceCount - 1);
          _quality = 'Last reference discarded. Record it again.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not discard the reference.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _socket.stopPracticeSession();
    } catch (_) {
      // Best-effort teardown; disconnect below clears local lifecycle state.
    }
    if (mounted) Navigator.of(context).pop();
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
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
      title: const Text('Record reference demonstrations'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Perform the complete movement three times. ELIXR uses body, hand, and prop motion—not the video itself—to build your reference.',
          ),
          const SizedBox(height: 12),
          AspectRatio(
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
          const SizedBox(height: 12),
          Row(
            children: List.generate(MovementTemplate.minimumReferences, (
              index,
            ) {
              final complete = index < _referenceCount;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: complete
                        ? Colors.green.withValues(alpha: 0.12)
                        : FluentTheme.of(
                            context,
                          ).resources.cardBackgroundFillColorDefault,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        complete ? FluentIcons.accept : FluentIcons.circle_ring,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text('Reference ${index + 1}${complete ? ' ✓' : ''}'),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(_quality),
          if (_error != null) ...[
            const SizedBox(height: 8),
            InfoBar(
              title: const Text('Recording issue'),
              content: Text(_error!),
              severity: InfoBarSeverity.error,
            ),
          ],
        ],
      ),
      actions: [
        Button(onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
        if (_referenceCount > 0 && !_recording)
          Button(
            onPressed: _busy ? null : _discardLast,
            child: const Text('Discard last'),
          ),
        FilledButton(
          key: const ValueKey('custom-reference-record'),
          onPressed: _initializing || _busy || (!_ready && !_active)
              ? null
              : (_recording ? _stopRecording : _startRecording),
          child: Text(_recording ? 'Finish reference' : 'Record Reference'),
        ),
      ],
    );
  }
}
