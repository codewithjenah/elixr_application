import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
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
import '../../../services/websocket_service.dart';

typedef TeacherDemoRecordUpload =
    Future<TeacherActivityVideoMetadata> Function({
      required File localFile,
      required Duration duration,
      required TeacherActivityDemoSource source,
    });

Future<TeacherActivityVideoMetadata?> showTeacherDemoRecordingDialog(
  BuildContext context, {
  required TeacherDemoRecordUpload upload,
}) => ElixDialog.show<TeacherActivityVideoMetadata>(
  context,
  title: 'Record demonstration with ELIXR',
  subtitle: 'Record up to 60 seconds, then preview, retake, or save.',
  icon: FluentIcons.video,
  maxWidth: 760,
  maxHeight: MediaQuery.sizeOf(context).height * .9,
  scrollableContent: true,
  barrierDismissible: false,
  content: _TeacherDemoRecordingDialog(upload: upload),
);

class _TeacherDemoRecordingDialog extends StatefulWidget {
  const _TeacherDemoRecordingDialog({required this.upload});

  final TeacherDemoRecordUpload upload;

  @override
  State<_TeacherDemoRecordingDialog> createState() =>
      _TeacherDemoRecordingDialogState();
}

class _TeacherDemoRecordingDialogState
    extends State<_TeacherDemoRecordingDialog> {
  static const _maximumSeconds = 60;
  final WebSocketService _websocket = WebSocketService();
  final ElixrPlaybackSession _playback = ElixrPlaybackSession();
  StreamSubscription<PreviewFrame>? _previewSubscription;
  Timer? _timer;
  Uint8List? _frame;
  SubmissionRecordResult? _clip;
  bool _preparing = true;
  bool _recording = false;
  bool _busy = false;
  int _elapsedSeconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final settings = context.read<SettingsService>();
    try {
      await _websocket.connect();
      if (!_websocket.isConnected) {
        throw StateError(_websocket.errorMessage ?? 'Backend unavailable.');
      }
      _previewSubscription = _websocket.previewStream.listen((preview) {
        if (!mounted || !preview.hasJpeg) return;
        setState(() => _frame = preview.jpegBytes);
      });
      _websocket.beginPracticeAttempt();
      final cameraDeviceId = await settings.loadSelectedCameraDeviceId();
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
      if (mounted) setState(() => _preparing = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _error =
              'ELIXR could not prepare the selected camera. Check the backend and camera settings, then try again.';
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (_preparing || _busy || _recording || _clip != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ack = await _websocket.sendStartSubmissionRecord(
        durationSeconds: _maximumSeconds,
      );
      if (!ack.accepted) {
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
    _websocket.dispose();
  }

  @override
  void dispose() {
    unawaited(_tearDown());
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
                  : _frame == null
                  ? Center(
                      child: _preparing
                          ? const ProgressRing()
                          : const Icon(FluentIcons.video, size: 36),
                    )
                  : Image.memory(_frame!, fit: BoxFit.contain),
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
                  onPressed: _preparing || _busy || _error != null
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
