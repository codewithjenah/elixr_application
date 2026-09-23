import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elixr_video_player.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/models/ws_protocol.dart';
import '../../../services/settings_service.dart';
import '../../../services/camera_device_service.dart';
import '../../../services/websocket_service.dart';
import '../../settings/widgets/camera_source_preference.dart';

typedef TeacherDemoRecordUpload =
    Future<TeacherActivityVideoMetadata> Function({
      required File localFile,
      required Duration duration,
      required TeacherActivityDemoSource source,
    });

Future<TeacherActivityVideoMetadata?> showTeacherDemoRecordingDialog(
  BuildContext context, {
  required TeacherDemoRecordUpload upload,
  @visibleForTesting WebSocketService? webSocket,
}) => ElixDialog.show<TeacherActivityVideoMetadata>(
  context,
  title: 'Record demonstration with ELIXR',
  subtitle: 'Record up to 60 seconds, then preview, retake, or save.',
  icon: FluentIcons.video,
  maxWidth: 760,
  maxHeight: MediaQuery.sizeOf(context).height * .9,
  scrollableContent: true,
  barrierDismissible: false,
  content: _TeacherDemoRecordingDialog(upload: upload, webSocket: webSocket),
);

class _TeacherDemoRecordingDialog extends StatefulWidget {
  const _TeacherDemoRecordingDialog({required this.upload, this.webSocket});

  final TeacherDemoRecordUpload upload;
  final WebSocketService? webSocket;

  @override
  State<_TeacherDemoRecordingDialog> createState() =>
      _TeacherDemoRecordingDialogState();
}

class _TeacherDemoRecordingDialogState
    extends State<_TeacherDemoRecordingDialog> {
  static const _maximumSeconds = 60;
  late final WebSocketService _websocket;
  late final bool _ownsWebSocket;
  final ElixrPlaybackSession _playback = ElixrPlaybackSession();
  StreamSubscription<PreviewFrame>? _previewSubscription;
  Timer? _timer;
  final ValueNotifier<Uint8List?> _frame = ValueNotifier(null);
  SubmissionRecordResult? _clip;
  bool _preparing = true;
  bool _recording = false;
  bool _captureMayBeActive = false;
  bool _busy = false;
  bool _cameraSelectionBusy = false;
  int _elapsedSeconds = 0;
  String? _error;
  String? _sessionToRelease;

  @override
  void initState() {
    super.initState();
    _ownsWebSocket = widget.webSocket == null;
    _websocket = widget.webSocket ?? WebSocketService();
    _previewSubscription = _websocket.previewStream.listen((preview) {
      if (!mounted || _preparing || !preview.hasJpeg) return;
      _frame.value = preview.jpegBytes;
    });
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _error = null;
      _frame.value = null;
    });
    final settings = context.read<SettingsService>();
    try {
      await _websocket.connect();
      if (!_websocket.isConnected) {
        throw StateError(_websocket.errorMessage ?? 'Backend unavailable.');
      }
      if (!mounted) return;
      _sessionToRelease = _websocket.beginPracticeAttempt();
      final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
      if (!mounted) return;
      final ack = await _websocket.sendPrepare(
        movement: 'Free Practice',
        difficulty: 'Easy',
        prop: TrainingProp.bottle,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
        allowSubmissionRecording: true,
        readinessSpec: const TeacherActivityReadinessSpec(),
      );
      if (!ack.accepted) {
        throw StateError(ack.message ?? ack.errorCode ?? 'Camera unavailable.');
      }
      if (!mounted) return;
      if (mounted) setState(() => _preparing = false);
    } catch (_) {
      try {
        await _releaseCamera();
      } catch (_) {
        // Disconnect during teardown still releases the local connection.
      }
      if (mounted) {
        setState(() {
          _preparing = false;
          _error =
              'ELIXR could not prepare the selected camera. Check the backend and camera settings, then try again.';
        });
      }
    }
  }

  Future<void> _switchCamera(String? _) async {
    if (_preparing ||
        _busy ||
        _recording ||
        _captureMayBeActive ||
        _clip != null) {
      return;
    }
    setState(() {
      _preparing = true;
      _frame.value = null;
    });
    try {
      await _releaseCamera();
      if (!mounted) return;
      await _prepare();
    } catch (_) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = 'Could not release the current camera. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _cameraSelectionBusy = false);
    }
  }

  Future<void> _releaseCamera() async {
    final sessionId = _sessionToRelease ?? _websocket.currentSessionId;
    if (sessionId == null) return;
    final stopped = await _websocket.stopPracticeSession(sessionId: sessionId);
    if (!stopped.accepted) {
      throw StateError(stopped.message ?? stopped.errorCode ?? 'Stop rejected');
    }
    _sessionToRelease = null;
  }

  Future<void> _startRecording() async {
    if (_preparing ||
        _busy ||
        _cameraSelectionBusy ||
        _recording ||
        _captureMayBeActive ||
        _clip != null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A timed-out start may still have reached the backend. Keep camera
      // switching locked until a stop is acknowledged or the dialog closes.
      _captureMayBeActive = true;
      final ack = await _websocket.sendStartSubmissionRecord(
        durationSeconds: _maximumSeconds,
      );
      if (!ack.accepted) {
        _captureMayBeActive = false;
        throw StateError(ack.message ?? ack.errorCode ?? 'Recording failed.');
      }
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsedSeconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSeconds += 1);
        if (_elapsedSeconds >= _maximumSeconds) {
          unawaited(_stopRecording());
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The demo recording could not start.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _busy) return;
    _timer?.cancel();
    _timer = null;
    setState(() => _busy = true);
    try {
      final ack = await _websocket.sendStopSubmissionRecord();
      if (!ack.accepted) {
        throw StateError(ack.message ?? ack.errorCode ?? 'Recording failed.');
      }
      _captureMayBeActive = false;
      final clip = SubmissionRecordResult.fromAck(ack);
      if (clip.contentType != 'video/mp4' ||
          clip.durationMs < 1 ||
          clip.durationMs > _maximumSeconds * 1000 ||
          clip.sizeBytes < 1 ||
          clip.sizeBytes >
              TeacherActivityAssessmentContract.maximumVideoSizeBytes) {
        throw const FormatException('Recorded demonstration is out of bounds.');
      }
      if (!mounted) return;
      setState(() {
        _recording = false;
        _clip = clip;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error = 'The demo recording could not be finalized. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retake() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _playback.release();
    try {
      await _websocket.sendCancelSubmissionRecord();
      if (!mounted) return;
      setState(() {
        _clip = null;
        _elapsedSeconds = 0;
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final clip = _clip;
    if (clip == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final metadata = await widget.upload(
        localFile: File(clip.localPath),
        duration: Duration(milliseconds: clip.durationMs),
        source: TeacherActivityDemoSource.recorded,
      );
      await _playback.release();
      await _websocket.sendCancelSubmissionRecord();
      if (mounted) Navigator.pop(context, metadata);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The demo was recorded but could not be uploaded. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_recording) {
      _timer?.cancel();
      _recording = false;
    }
    await _playback.release();
    await _websocket.sendCancelSubmissionRecord();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _tearDown() async {
    _timer?.cancel();
    await _previewSubscription?.cancel();
    await _playback.release();
    try {
      await _websocket.sendCancelSubmissionRecord();
      await _websocket.sendStop();
    } catch (_) {}
    await _websocket.disconnect();
    if (_ownsWebSocket) _websocket.dispose();
  }

  @override
  void dispose() {
    unawaited(_tearDown());
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    return SizedBox(
      width: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ELIXR uses the selected camera through the Python camera service.',
            style: AppTheme.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          if (!_preparing &&
              !_recording &&
              !_captureMayBeActive &&
              clip == null) ...[
            CameraSourcePreference(
              settings: context.watch<SettingsService>(),
              cameras: context.watch<CameraDeviceService>(),
              compact: true,
              enabled: !_busy,
              onSelectionBusyChanged: (busy) {
                if (mounted) setState(() => _cameraSelectionBusy = busy);
              },
              onSelectionSaved: _switchCamera,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AspectRatio(
            aspectRatio: 4 / 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: clip != null
                  ? ElixrVideoPlayer(
                      source: Uri.file(clip.localPath),
                      mirrored: false,
                      session: _playback,
                    )
                  : ValueListenableBuilder<Uint8List?>(
                      valueListenable: _frame,
                      builder: (context, frame, _) => frame == null
                          ? Center(
                              child: _preparing
                                  ? const ProgressRing()
                                  : const Icon(FluentIcons.video, size: 36),
                            )
                          : Image.memory(
                              frame,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _recording
                ? 'Recording ${_elapsedSeconds.clamp(0, _maximumSeconds)}s / ${_maximumSeconds}s'
                : clip == null
                ? (_preparing ? 'Preparing camera…' : 'Camera ready')
                : 'Preview recording',
            style: AppTheme.body,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            shad.ShadAlert.destructive(
              title: const Text('Camera or recording error'),
              description: Text(_error!),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              shad.ShadButton.ghost(
                onPressed: _busy ? null : _close,
                child: const Text('Cancel'),
              ),
              if (_error != null &&
                  clip == null &&
                  !_recording &&
                  !_captureMayBeActive)
                shad.ShadButton.outline(
                  onPressed: _preparing || _busy
                      ? null
                      : () => _switchCamera(null),
                  child: const Text('Retry camera setup'),
                ),
              if (clip != null)
                shad.ShadButton.outline(
                  onPressed: _busy ? null : _retake,
                  child: const Text('Retake'),
                ),
              if (clip == null && !_recording)
                ElixPrimaryButton(
                  label: 'Start recording',
                  expanded: false,
                  dense: true,
                  onPressed:
                      _preparing ||
                          _busy ||
                          _cameraSelectionBusy ||
                          _captureMayBeActive ||
                          _error != null
                      ? null
                      : _startRecording,
                ),
              if (_recording)
                ElixPrimaryButton(
                  label: _busy ? 'Stopping…' : 'Stop recording',
                  expanded: false,
                  dense: true,
                  isLoading: _busy,
                  onPressed: _busy ? null : _stopRecording,
                ),
              if (clip != null)
                ElixPrimaryButton(
                  label: _busy ? 'Saving…' : 'Use demonstration',
                  expanded: false,
                  dense: true,
                  isLoading: _busy,
                  onPressed: _busy ? null : _save,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
