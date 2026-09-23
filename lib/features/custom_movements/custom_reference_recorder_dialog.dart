import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../data/models/movement_template.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/teacher_activity_assessment.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../services/websocket_service.dart';
import '../../services/settings_service.dart';
import '../../services/camera_device_service.dart';
import '../practice/widgets/training_status_row.dart';
import '../settings/widgets/camera_source_preference.dart';

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
  final ValueNotifier<Uint8List?> _preview = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<PreviewFrame?> _presentation =
      ValueNotifier<PreviewFrame?>(null);
  bool _initializing = true;
  bool _ready = false;
  bool _active = false;
  bool _recording = false;
  bool _busy = false;
  bool _cameraSelectionBusy = false;
  int? _personCount;
  bool _referenceContaminated = false;
  int _referenceCount = 0;
  String? _sessionToRelease;
  int? _countdown;
  String? _error;
  String? _cameraName;
  String _quality = 'Position yourself and the selected prop in view.';

  bool get _canStartReference =>
      !_initializing &&
      !_busy &&
      !_cameraSelectionBusy &&
      !_recording &&
      _personCount == 1 &&
      (_ready || _active);

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    _previewSubscription = _socket.previewStream.listen((frame) {
      if (!mounted || _initializing) return;
      _presentation.value = frame;
      if (!frame.hasJpeg) return;
      _preview.value = frame.jpegBytes;
    });
    _feedbackSubscription = _socket.feedbackStream.listen((feedback) {
      if (!mounted || _initializing) return;
      setState(() {
        _ready = feedback.readinessStable == true;
        _personCount = feedback.personCount;
        if (_recording &&
            (feedback.referenceInvalid == true ||
                (feedback.personCount != null && feedback.personCount! >= 2))) {
          _referenceContaminated = true;
        }
        if (!_ready && !_recording) _quality = feedback.feedback;
      });
    });
    await _prepareSession();
  }

  Future<void> _prepareSession() async {
    setState(() {
      _initializing = true;
      _ready = false;
      _personCount = null;
      _referenceContaminated = false;
      _error = null;
      _cameraName = null;
      _quality = 'Position yourself and the selected prop in view.';
      _preview.value = null;
      _presentation.value = null;
    });
    try {
      final settings = context.read<SettingsService>();
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('Backend unavailable');
      if (!mounted) return;
      final sessionId = _socket.beginPracticeAttempt();
      _sessionToRelease = sessionId;
      final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
      if (!mounted) return;
      _requireAccepted(
        await _socket.sendPrepare(
          movement: 'Custom Movement',
          difficulty: widget.difficulty,
          prop: widget.prop,
          sessionId: sessionId,
          sessionMode: 'custom_capture',
          cameraDeviceId: cameraDeviceId,
          legacyCameraIndex: cameraDeviceId == null
              ? settings.pendingLegacyCameraIndex
              : null,
          // Capture observes Hands and Pose while recording, but readiness
          // only requires the camera and selected prop. The three accepted
          // demonstrations determine which landmark modalities are reliable.
          readinessSpec: const TeacherActivityReadinessSpec(),
        ),
      );
      _requireAccepted(await _socket.sendBeginReadiness(sessionId: sessionId));
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraName = settings.selectedCameraDisplayName;
      });
    } catch (_) {
      await _stopSessionBestEffort();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error =
            'ELIXR could not prepare the selected camera. Choose a camera here and try again.';
      });
    }
  }

  Future<void> _switchCamera(String? _) async {
    if (_initializing ||
        _busy ||
        _active ||
        _recording ||
        _referenceCount > 0) {
      return;
    }
    setState(() {
      _initializing = true;
      _ready = false;
      _personCount = null;
      _referenceContaminated = false;
      _quality = 'Position yourself and the selected prop in view.';
      _preview.value = null;
      _presentation.value = null;
    });
    try {
      await _releaseCamera();
      if (!mounted) return;
      await _prepareSession();
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Could not release the current camera. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _cameraSelectionBusy = false);
    }
  }

  Future<void> _startRecording() async {
    if (!_canStartReference) return;
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
        _referenceContaminated = false;
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
        if (ack.errorCode == 'multiple_people_detected') {
          if (mounted) {
            setState(() {
              _recording = false;
              _error =
                  'Reference rejected because multiple people were detected. Keep only one performer in frame and record it again.';
            });
          }
          return;
        }
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
        if (_ownsSocket) await _socket.disconnect();
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
      await _releaseCamera();
    } catch (_) {
      // Best-effort teardown; disconnect below clears local lifecycle state.
    }
    if (_ownsSocket) await _socket.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  void _requireAccepted(CommandAck ack) {
    if (!ack.accepted) {
      throw StateError(ack.errorCode ?? ack.message ?? 'Command rejected');
    }
  }

  Future<void> _stopSessionBestEffort() async {
    try {
      await _releaseCamera();
    } catch (_) {
      // Disconnect/dispose remains the final local lifecycle cleanup.
    }
  }

  Future<void> _releaseCamera() async {
    final sessionId = _sessionToRelease ?? _socket.currentSessionId;
    if (sessionId == null) return;
    _requireAccepted(await _socket.stopPracticeSession(sessionId: sessionId));
    _sessionToRelease = null;
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
    final mirrored = context.watch<SettingsService>().cameraMirrored;
    final size = MediaQuery.sizeOf(context);
    return ContentDialog(
      constraints: BoxConstraints(
        maxWidth: (size.width - 48).clamp(0.0, 1320.0),
        maxHeight: (size.height - 64).clamp(0.0, 820.0),
      ),
      title: const Text('Record movement references'),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final workspace = _CameraWorkspace(
            frameListenable: _preview,
            mirrored: mirrored,
            countdown: _countdown,
            recording: _recording,
            cameraName: _cameraName,
            prop: widget.prop,
          );
          final status = ValueListenableBuilder<PreviewFrame?>(
            valueListenable: _presentation,
            builder: (context, presentation, _) => _RecorderStatusPanel(
              referenceCount: _referenceCount,
              ready: _ready,
              active: _active,
              personReady: _personCount == 1,
              initializing: _initializing,
              recording: _recording,
              quality: _quality,
              error: _error,
              multiplePeople: _personCount != null && _personCount! >= 2,
              referenceContaminated: _referenceContaminated,
              prop: widget.prop,
              presentation: presentation,
            ),
          );
          final canEditCameraSource =
              !_initializing &&
              !_busy &&
              !_cameraSelectionBusy &&
              _countdown == null &&
              !_active &&
              !_recording &&
              _referenceCount == 0;
          final setup = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Record 3 complete demonstrations to build your assessment template.',
              ),
              const SizedBox(height: AppSpacing.sm),
              CameraSourcePreference(
                settings: context.watch<SettingsService>(),
                cameras: context.watch<CameraDeviceService>(),
                compact: true,
                enabled: canEditCameraSource,
                onSelectionBusyChanged: (busy) {
                  if (mounted) setState(() => _cameraSelectionBusy = busy);
                },
                onSelectionSaved: _switchCamera,
              ),
              if (widget.prop == TrainingProp.bottle) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'For visible turns, keep orange tape on the bottle top and yellow tape on the base in view. Hidden or extremely fast turns may remain uncertain.',
                ),
              ],
            ],
          );
          if (compact) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  setup,
                  const SizedBox(height: AppSpacing.md),
                  AspectRatio(aspectRatio: 16 / 9, child: workspace),
                  const SizedBox(height: AppSpacing.md),
                  status,
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              setup,
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: workspace,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 3, child: status),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        Button(onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
        if (_error != null && !_recording && _referenceCount == 0)
          Button(
            onPressed: _initializing || _busy
                ? null
                : () => _switchCamera(null),
            child: const Text('Retry camera setup'),
          ),
        if (_referenceCount > 0 && !_recording)
          Button(
            onPressed: _busy ? null : _discardLast,
            child: const Text('Discard last'),
          ),
        FilledButton(
          key: const ValueKey('custom-reference-record'),
          onPressed: _recording
              ? _initializing || _busy
                    ? null
                    : _stopRecording
              : _canStartReference
              ? _startRecording
              : null,
          child: Text(_recording ? 'Finish reference' : 'Record Reference'),
        ),
      ],
    );
  }
}

class _CameraWorkspace extends StatelessWidget {
  const _CameraWorkspace({
    required this.frameListenable,
    required this.mirrored,
    required this.countdown,
    required this.recording,
    required this.cameraName,
    required this.prop,
  });

  final ValueListenable<Uint8List?> frameListenable;
  final bool mirrored;
  final int? countdown;
  final bool recording;
  final String? cameraName;
  final TrainingProp prop;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<Uint8List?>(
              valueListenable: frameListenable,
              builder: (context, frame, _) => frame == null
                  ? const Center(child: ProgressRing())
                  : Transform.flip(
                      key: const ValueKey('custom-reference-camera-frame'),
                      flipX: mirrored,
                      child: Image.memory(
                        frame,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: _CameraPill(
                label: recording ? 'Recording' : 'Live',
                color: recording ? Colors.red : Colors.green,
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: _CameraPill(label: prop.displayLabel),
            ),
            if (cameraName != null)
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _CameraPill(label: cameraName!),
                ),
              ),
            if (countdown != null)
              Center(
                child: Text(
                  '$countdown',
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
  );
}

class _CameraPill extends StatelessWidget {
  const _CameraPill({required this.label, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.7)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color ?? Colors.white, fontSize: 12),
    ),
  );
}

class _RecorderStatusPanel extends StatelessWidget {
  const _RecorderStatusPanel({
    required this.referenceCount,
    required this.ready,
    required this.active,
    required this.personReady,
    required this.initializing,
    required this.recording,
    required this.quality,
    required this.error,
    required this.multiplePeople,
    required this.referenceContaminated,
    required this.prop,
    required this.presentation,
  });
  final int referenceCount;
  final bool ready;
  final bool active;
  final bool personReady;
  final bool initializing;
  final bool recording;
  final String quality;
  final String? error;
  final bool multiplePeople;
  final bool referenceContaminated;
  final TrainingProp prop;
  final PreviewFrame? presentation;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.smPlus),
    decoration: BoxDecoration(
      color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: FluentTheme.of(context).resources.cardStrokeColorDefault,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '3 references',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var index = 0; index < MovementTemplate.minimumReferences; index++)
          _ReferenceStep(
            index: index,
            count: referenceCount,
            recording: recording,
          ),
        const SizedBox(height: AppSpacing.sm),
        _RecorderVisionStatus(
          detection: resolvePresentationDetectionStatus(
            sessionObserving: !initializing,
            propPresentationState: presentation?.propPresentationState,
          ),
          propLabel: prop.displayLabel,
          handLabel: modalityPresentationLabel(
            label: 'Hand',
            required: true,
            presentationState: presentation?.handsPresentationState,
          ),
          bodyLabel: modalityPresentationLabel(
            label: 'Body',
            required: true,
            presentationState: presentation?.posePresentationState,
          ),
        ),
        if (error == null &&
            !multiplePeople &&
            !(recording && referenceContaminated)) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            initializing
                ? 'Preparing camera'
                : recording
                ? 'Recording reference ${referenceCount + 1} of 3'
                : (active || ready) && personReady
                ? referenceCount == 0
                      ? 'Ready to record'
                      : 'Reference saved — record the next one'
                : 'Getting into position',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(quality, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (error == null &&
            (multiplePeople || (recording && referenceContaminated))) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: const Text('Multiple people detected'),
            content: Text(
              recording || referenceContaminated
                  ? 'This reference cannot be accepted. Finish it, then retry with only one performer in frame.'
                  : 'Only one person can be in frame while recording a reference.',
            ),
            severity: InfoBarSeverity.warning,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoBar(
            title: const Text('Recording issue'),
            content: Text(error!),
            severity: InfoBarSeverity.error,
          ),
        ],
      ],
    ),
  );
}

class _RecorderVisionStatus extends StatelessWidget {
  const _RecorderVisionStatus({
    required this.detection,
    required this.propLabel,
    this.handLabel,
    this.bodyLabel,
  });

  final TrainingDetectionStatus detection;
  final String propLabel;
  final String? handLabel;
  final String? bodyLabel;

  @override
  Widget build(BuildContext context) {
    final prop = switch (detection) {
      TrainingDetectionStatus.detected => '$propLabel detected',
      TrainingDetectionStatus.coasted => 'Tracking ${propLabel.toLowerCase()}',
      TrainingDetectionStatus.searching =>
        'Searching for ${propLabel.toLowerCase()}',
      TrainingDetectionStatus.inactive => 'Detection inactive',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prop, style: const TextStyle(fontSize: 12)),
        if (handLabel != null)
          Text(handLabel!, style: const TextStyle(fontSize: 12)),
        if (bodyLabel != null)
          Text(bodyLabel!, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _ReferenceStep extends StatelessWidget {
  const _ReferenceStep({
    required this.index,
    required this.count,
    required this.recording,
  });
  final int index;
  final int count;
  final bool recording;
  @override
  Widget build(BuildContext context) {
    final complete = index < count;
    final current = !complete && index == count;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            complete
                ? FluentIcons.completed
                : current
                ? FluentIcons.circle_ring
                : FluentIcons.circle_ring,
            size: 16,
            color: complete ? Colors.green : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Reference ${index + 1}${complete
                  ? ' · Saved'
                  : current && recording
                  ? ' · Recording'
                  : current
                  ? ' · Next'
                  : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
