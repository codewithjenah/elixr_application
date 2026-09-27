import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_back_button.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elixr_video_player.dart';
import '../../data/models/custom_movement.dart';
import '../../data/models/custom_movement_save_diagnostics.dart';
import '../../data/models/movement_template.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/teacher_activity_assessment.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/custom_movement_repository.dart';
import '../../services/camera_device_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import '../settings/widgets/camera_source_preference.dart';
import 'widgets/authoring_wizard_widgets.dart';

class _ReferenceDraft {
  _ReferenceDraft({
    required this.id,
    required this.path,
    required this.durationMs,
    required this.quality,
  });

  final String id;
  final String path;
  final int durationMs;
  final _ReferenceQuality? quality;
  int startMs = 0;
  late int endMs = durationMs;

  /// Movement/hold issue reported for this example by the last template
  /// build (for example `no_meaningful_motion`). Cleared on any edit.
  String? semanticIssue;

  bool get isTrimmed => startMs > 0 || endMs < durationMs;
}

/// A backend authoring rejection already mapped to its user-facing message.
class _ReferenceIssue implements Exception {
  const _ReferenceIssue(this.message);
  final String message;
}

/// One beginner-facing sentence for a backend authoring rejection, using the
/// measured values the backend returns in `reference_quality`. Returns null
/// for codes this screen does not own so callers keep their own fallback.
String? customReferenceIssueMessage(
  String? code,
  Map<String, dynamic>? details, {
  required String movementBehavior,
  required String propLabel,
}) {
  final values = details ?? const <String, dynamic>{};
  num? number(String key) => values[key] is num ? values[key] as num : null;
  String seconds(num ms) => (ms / 1000).toStringAsFixed(1);
  String percent(String key, String fallback) {
    final value = number(key);
    return value == null ? fallback : '${(value * 100).round()}%';
  }

  final isStatic = movementBehavior == 'static';
  final prop = propLabel.toLowerCase();
  final index = number('reference_index');
  final prefix = index == null ? '' : 'Example ${index.toInt() + 1}: ';
  final holdSeconds = seconds(
    MovementTemplate.staticHoldDuration.inMilliseconds,
  );
  final holdHint = isStatic
      ? ' and hold the final position steady for at least $holdSeconds seconds'
      : '';
  final duration = number('duration_ms');
  final samples = number('sample_count');
  final requiredSamples = number('required_sample_count');
  final holdSamples = number('hold_sample_count');
  final requiredHoldSamples = number('required_hold_sample_count');
  final holdDuration = number('hold_duration_ms');
  final gap = number('longest_tracking_gap_ms');
  final handSide =
      values['hand_side'] == 'left' || values['hand_side'] == 'right'
      ? values['hand_side'] as String
      : null;
  final message = switch (code) {
    'reference_duration_too_short' =>
      '${duration == null ? '' : 'This clip is ${seconds(duration)} s. '}'
          'Record at least ${seconds(MovementTemplate.minimumReferenceDuration.inMilliseconds)} second$holdHint.',
    'insufficient_tracking_samples' =>
      isStatic &&
              samples != null &&
              requiredSamples != null &&
              samples >= requiredSamples &&
              holdDuration != null &&
              holdDuration < MovementTemplate.staticHoldDuration.inMilliseconds
          ? 'The final hold was tracked for only ${seconds(holdDuration)} s. '
                'Keep the position steady for at least $holdSeconds s before stopping.'
          : isStatic &&
                samples != null &&
                requiredSamples != null &&
                samples >= requiredSamples &&
                holdSamples != null &&
                requiredHoldSamples != null &&
                holdSamples < requiredHoldSamples
          ? 'The final hold had only ${holdSamples.toInt()} tracked samples '
                '(needs ${requiredHoldSamples.toInt()}). Keep your hand and $prop '
                'visible during the $holdSeconds s hold.'
          : 'Your clip is long enough, but ELIXR captured only '
                '${samples?.toInt() ?? 'a few'} usable tracking samples'
                '${requiredSamples == null ? '' : ' (needs ${requiredSamples.toInt()})'}. '
                'Keep your hand and $prop visible and try again.',
    'insufficient_prop_coverage' =>
      'The $prop was visible in only ${percent('prop_coverage', 'part')} '
          'of the clip. Keep it in view the whole time and try again.',
    'insufficient_hand_coverage' =>
      'Your ${handSide == null ? '' : '$handSide '}hand was tracked in only '
          '${percent('hand_coverage', 'part')} of the clip. '
          'Keep ${handSide == null ? 'at least one hand' : 'that hand'} clearly visible throughout.',
    'excessive_tracking_gap' =>
      'Tracking was lost for ${gap == null ? 'too long' : '${seconds(gap)} s'} '
          'in a row. Keep your hand, body, and $prop visible throughout.',
    'no_meaningful_motion' =>
      'ELIXR can see your hand and $prop, but no clear movement was detected. '
          'Perform the full movement before stopping. Small movements are okay.',
    'inconsistent_dynamic_references' =>
      'Your examples show different movements. Record the same movement each '
          'time; different speeds are fine.',
    'unstable_static_reference' =>
      'The final position was still moving. Hold it steady for at least '
          '$holdSeconds seconds before stopping.',
    'inconsistent_static_references' =>
      'The final positions differ between examples. Record the same grip or '
          'stall each time.',
    'invalid_trim_range' =>
      'That trim range is not valid. Keep the start before the end.',
    'invalid_reference_count' =>
      isStatic
          ? 'Record 1 clear example before reviewing.'
          : 'Record 2 examples of the same movement before reviewing.',
    _ => null,
  };
  return message == null ? null : '$prefix$message';
}

/// The backend reports observed-frame coverage. It is feedback for the next
/// recording, not a replacement for template inference (which also checks gaps).
class _ReferenceQuality {
  const _ReferenceQuality({
    required this.leftHandCoverage,
    required this.rightHandCoverage,
    required this.poseCoverage,
    this.propCoverage,
  });

  final double? leftHandCoverage;
  final double? rightHandCoverage;
  final double? poseCoverage;
  final double? propCoverage;

  // Matches template_engine.MIN_COVERAGE. Final template inference also checks
  // tracking gaps, so this only prompts a better next recording.
  static const minimumCoverageHint = 0.70;
  // Matches template_engine.REFERENCE_MIN_PROP_COVERAGE.
  static const minimumPropCoverageHint = 0.60;

  double? get bestHandCoverage {
    final values = [
      leftHandCoverage,
      rightHandCoverage,
    ].whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  bool get handsHardToSee {
    final best = bestHandCoverage;
    return best != null && best < minimumCoverageHint;
  }

  static _ReferenceQuality? fromJson(Map<String, dynamic>? value) {
    if (value == null) return null;
    double? coverage(String key) {
      final raw = value[key];
      if (raw is! num) return null;
      final result = raw.toDouble();
      return result.isFinite && result >= 0 && result <= 1 ? result : null;
    }

    return _ReferenceQuality(
      leftHandCoverage: coverage('left_hand_coverage'),
      rightHandCoverage: coverage('right_hand_coverage'),
      poseCoverage: coverage('pose_coverage'),
      propCoverage: coverage('prop_coverage'),
    );
  }
}

/// Shared trainee/teacher authoring page. Clips are session-local drafts;
/// only the resulting detector template is sent to Firestore.
class CustomMovementAuthoringScreen extends StatefulWidget {
  const CustomMovementAuthoringScreen({
    super.key,
    required this.ownerUid,
    required this.ownerRole,
    required this.repository,
    this.existing,
    this.existingRevision,
    this.webSocket,
  });

  final String ownerUid;
  final CustomMovementOwnerRole ownerRole;
  final CustomMovementRepository repository;
  final CustomMovement? existing;
  final CustomMovementRevision? existingRevision;
  final WebSocketService? webSocket;

  static Future<CustomMovement?> show(
    BuildContext context, {
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required CustomMovementRepository repository,
    CustomMovement? existing,
    CustomMovementRevision? existingRevision,
  }) => Navigator.of(context).push<CustomMovement>(
    FluentPageRoute<CustomMovement>(
      builder: (_) => CustomMovementAuthoringScreen(
        ownerUid: ownerUid,
        ownerRole: ownerRole,
        repository: repository,
        existing: existing,
        existingRevision: existingRevision,
      ),
    ),
  );

  @override
  State<CustomMovementAuthoringScreen> createState() =>
      _CustomMovementAuthoringScreenState();
}

class _CustomMovementAuthoringScreenState
    extends State<CustomMovementAuthoringScreen> {
  static const _referenceCaptureDuration = Duration(seconds: 15);
  static const _maxReferences = 5;
  static const _stepLabels = ['Set up', 'Record examples', 'Review & save'];

  /// Below this content height the wizard scrolls as one page instead of
  /// pinning the step actions to the bottom edge.
  static const _minPinnedLayoutHeight = 520.0;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final WebSocketService _socket;
  late final bool _ownsSocket;
  final ValueNotifier<Uint8List?> _frame = ValueNotifier(null);
  final ElixrPlaybackSession _playback = ElixrPlaybackSession();
  StreamSubscription<PreviewFrame>? _previewSubscription;
  StreamSubscription<PracticeFeedback>? _feedbackSubscription;
  Timer? _referenceCaptureTimer;
  Timer? _referenceCaptureDeadlineTimer;
  final ValueNotifier<int> _referenceRemainingSeconds = ValueNotifier(
    _referenceCaptureDuration.inSeconds,
  );
  final List<_ReferenceDraft> _references = [];

  late String _difficulty;
  late TrainingProp _prop;
  String _movementBehavior = 'dynamic';
  MovementTemplate? _template;
  bool _replacingReferences = false;
  bool _sessionStarted = false;
  bool _previewReady = false;
  bool _initializing = false;
  bool _cameraFailed = false;
  bool _active = false;
  bool _ready = false;
  bool _propVisible = false;
  bool _handsVisible = false;
  bool _upperBodyVisible = false;
  DateTime? _captureObservedAt;
  DateTime? _referenceCaptureDeadline;
  bool _recording = false;
  bool _finishingReference = false;
  Future<void>? _finishReferenceFuture;
  Uint8List? _referenceImageJpegBytes;
  bool _busy = false;
  bool _buildingTemplate = false;
  bool _cameraBusy = false;
  bool _resettingProp = false;
  bool _closed = false;
  CustomMovement? _savedMovement;
  int? _personCount;
  int? _countdown;
  int _step = 0;
  String? _sessionId;
  String? _error;
  String? _previewId;
  int _pendingStart = 0;
  int _pendingEnd = 0;

  bool get _hasUsableTemplate => _template?.isReady == true;
  int get _requiredReferences =>
      MovementTemplate.minimumReferencesFor(_movementBehavior);

  String? _issueMessage(CommandAck ack) => customReferenceIssueMessage(
    ack.errorCode,
    ack.referenceQuality,
    movementBehavior: _movementBehavior,
    propLabel: _prop.displayLabel,
  );
  bool get _canRecord =>
      _sessionStarted &&
      _previewReady &&
      !_initializing &&
      !_busy &&
      !_cameraBusy &&
      !_recording &&
      _references.length < _maxReferences &&
      _personCount == 1 &&
      _propVisible &&
      _handsVisible &&
      _upperBodyVisible &&
      _captureObservedAt != null &&
      DateTime.now().difference(_captureObservedAt!) <
          const Duration(seconds: 2) &&
      (_ready || _active);

  @override
  void initState() {
    super.initState();
    _ownsSocket = widget.webSocket == null;
    _socket = widget.webSocket ?? WebSocketService();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _difficulty = widget.existing?.difficulty ?? 'Easy';
    _prop = widget.existing?.propType ?? TrainingProp.bottle;
    _template = widget.existingRevision?.template;
    _movementBehavior = _template?.movementBehavior ?? 'dynamic';
    _replacingReferences = widget.existing == null;
  }

  @override
  void dispose() {
    _cancelReferenceCaptureTimers();
    unawaited(_teardown());
    _name.dispose();
    _description.dispose();
    _frame.dispose();
    _referenceRemainingSeconds.dispose();
    super.dispose();
  }

  Future<void> _teardown({bool reportFailure = false}) async {
    if (_closed) return;
    _closed = true;
    _cancelReferenceCaptureTimers();
    _recording = false;
    _finishingReference = false;
    Object? firstFailure;
    StackTrace? firstFailureStack;
    void recordFailure(Object error, StackTrace stackTrace) {
      firstFailure ??= error;
      firstFailureStack ??= stackTrace;
    }

    try {
      await _playback.release();
    } on Object catch (error, stackTrace) {
      // Continue backend teardown if native playback release fails.
      recordFailure(error, stackTrace);
    }
    try {
      await _previewSubscription?.cancel();
    } on Object catch (error, stackTrace) {
      recordFailure(error, stackTrace);
    }
    try {
      await _feedbackSubscription?.cancel();
    } on Object catch (error, stackTrace) {
      recordFailure(error, stackTrace);
    }
    final id = _sessionId;
    _sessionId = null;
    if (id != null) {
      try {
        await _socket.stopPracticeSession(sessionId: id);
      } on Object catch (error, stackTrace) {
        /* Disconnect closes the backend session. */
        recordFailure(error, stackTrace);
      }
    }
    try {
      await _socket.disconnect();
    } on Object catch (error, stackTrace) {
      // A lost connection already closes its backend session.
      recordFailure(error, stackTrace);
    }
    if (_ownsSocket) {
      try {
        _socket.dispose();
      } on Object catch (error, stackTrace) {
        recordFailure(error, stackTrace);
      }
    }
    if (reportFailure && firstFailure != null) {
      throw CustomMovementSaveException(
        stage: CustomMovementSaveStage.teardown,
        cause: firstFailure!,
        stackTrace: firstFailureStack ?? StackTrace.current,
      );
    }
  }

  Future<void> _resetSession() async {
    _cancelReferenceCaptureTimers();
    _recording = false;
    _finishingReference = false;
    await _playback.release();
    final id = _sessionId;
    _sessionId = null;
    if (id != null) {
      try {
        await _socket.stopPracticeSession(sessionId: id);
      } catch (_) {
        await _socket.disconnect();
      }
    }
    if (mounted) {
      setState(() {
        _sessionStarted = false;
        _previewReady = false;
        _active = false;
        _ready = false;
        _personCount = null;
        _propVisible = false;
        _handsVisible = false;
        _upperBodyVisible = false;
        _captureObservedAt = null;
        _frame.value = null;
      });
    }
  }

  void _requireAccepted(CommandAck ack) {
    if (!ack.accepted) {
      // Only the Review flow displays this text; every other caller replaces
      // it with its own guidance. Prefer the backend's human-readable message.
      throw StateError(ack.message ?? ack.errorCode ?? 'Command rejected');
    }
  }

  Future<void> _prepare() async {
    if (_sessionStarted || _initializing) return;
    setState(() {
      _initializing = true;
      _cameraFailed = false;
      _error = null;
    });
    try {
      _previewSubscription ??= _socket.previewStream.listen((preview) {
        if (!mounted) return;
        if (preview.hasJpeg) {
          _frame.value = preview.jpegBytes;
          if (!_previewReady) setState(() => _previewReady = true);
        }
      });
      _feedbackSubscription ??= _socket.feedbackStream.listen((feedback) {
        if (!mounted) return;
        final ready = feedback.readinessStable == true;
        if ((!_active && _ready != ready) ||
            _personCount != feedback.personCount ||
            _propVisible != (feedback.capturePropVisible == true) ||
            _handsVisible != (feedback.captureHandsVisible == true) ||
            _upperBodyVisible != (feedback.captureUpperBodyVisible == true)) {
          setState(() {
            if (!_active) _ready = ready;
            _personCount = feedback.personCount;
            _propVisible = feedback.capturePropVisible == true;
            _handsVisible = feedback.captureHandsVisible == true;
            _upperBodyVisible = feedback.captureUpperBodyVisible == true;
            _captureObservedAt = DateTime.now();
          });
        } else {
          _captureObservedAt = DateTime.now();
        }
      });
      final settings = context.read<SettingsService>();
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('Backend unavailable');
      final id = _socket.beginPracticeAttempt();
      _sessionId = id;
      // The saved device id is enough to prepare. Authoring deliberately does
      // not run GET /cameras discovery here: a hardware scan would serialize
      // on the same physical camera and delay this session's first frame.
      final cameraId = await settings.loadSelectedCameraDeviceId();
      _requireAccepted(
        await _socket.sendPrepare(
          movement: 'Custom Movement',
          difficulty: _difficulty,
          prop: _prop,
          sessionId: id,
          sessionMode: 'custom_capture',
          cameraDeviceId: cameraId,
          legacyCameraIndex: cameraId == null
              ? settings.pendingLegacyCameraIndex
              : null,
          readinessSpec: const TeacherActivityReadinessSpec(
            hands: ActivityHandRequirement.oneHand,
            body: ActivityBodyRequirement.upperBody,
          ),
        ),
      );
      _requireAccepted(await _socket.sendBeginReadiness(sessionId: id));
      if (!mounted) return;
      setState(() => _sessionStarted = true);
    } catch (_) {
      await _resetSession();
      if (mounted) {
        setState(() {
          _cameraFailed = true;
          _error =
              'Could not prepare the camera. Check the camera source and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _changeCamera(String? _) async {
    if (_initializing || _active || _references.isNotEmpty || _recording) {
      return;
    }
    await _resetSession();
    if (!mounted) return;
    await _prepare();
  }

  Future<void> _record() async {
    if (!_canRecord) return;
    _cancelReferenceCaptureTimers();
    setState(() {
      _busy = true;
      _error = null;
      _recording = false;
      _finishingReference = false;
    });
    try {
      if (!_active) {
        _requireAccepted(await _socket.sendConfirmReadiness());
      }
      for (var value = 3; value >= 1; value--) {
        if (!mounted) return;
        setState(() => _countdown = value);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
      if (!_active) {
        _requireAccepted(await _socket.sendActivate());
        _active = true;
      }
      // Anchor the client deadline immediately before the correlated start
      // command. Starting early by the command round-trip keeps the authoring
      // UI from claiming capture is active after the backend's own deadline.
      final deadline = DateTime.now().add(_referenceCaptureDuration);
      _requireAccepted(
        await _socket.sendStartCustomCapture(
          durationSeconds: _referenceCaptureDuration.inSeconds,
        ),
      );
      if (mounted) {
        setState(() {
          _recording = true;
          _referenceCaptureDeadline = deadline;
          _referenceRemainingSeconds.value =
              _referenceCaptureDuration.inSeconds;
        });
        _startReferenceCaptureTimers(deadline);
      }
    } catch (_) {
      _cancelReferenceCaptureTimers();
      if (mounted) {
        setState(
          () => _error =
              'Could not start recording. Keep one person and the prop in view, then retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _countdown = null;
        });
      }
    }
  }

  Future<void> _finishReference({bool automatic = false}) {
    final inProgress = _finishReferenceFuture;
    if (inProgress != null) return inProgress;
    if (!_recording) return Future<void>.value();
    _cancelReferenceCaptureTimers();
    setState(() {
      _recording = false;
      _finishingReference = true;
      _busy = true;
    });
    final completion = _stopAndStoreReference(automatic: automatic);
    _finishReferenceFuture = completion;
    return completion;
  }

  Future<void> _stopAndStoreReference({required bool automatic}) async {
    try {
      final ack = await _socket.sendStopCustomCapture();
      if (!ack.accepted) {
        final issue = _issueMessage(ack);
        if (issue != null) throw _ReferenceIssue(issue);
      }
      _requireAccepted(ack);
      final id = ack.referenceId;
      final path = ack.localFilePath;
      final duration = ack.videoDurationMs;
      if (id == null || path == null || duration == null || duration <= 0) {
        throw StateError('Incomplete reference clip metadata');
      }
      await _playback.release();
      if (!mounted) return;
      final referenceFrame = _frame.value;
      setState(() {
        _references.add(
          _ReferenceDraft(
            id: id,
            path: path,
            durationMs: duration,
            quality: _ReferenceQuality.fromJson(ack.referenceQuality),
          ),
        );
        _previewId = id;
        _pendingStart = 0;
        _pendingEnd = duration;
        _template = null;
        _referenceImageJpegBytes =
            referenceFrame != null &&
                referenceFrame.lengthInBytes >= 1024 &&
                referenceFrame.lengthInBytes <= 512 * 1024
            ? Uint8List.fromList(referenceFrame)
            : _referenceImageJpegBytes;
      });
    } on _ReferenceIssue catch (issue) {
      if (mounted) setState(() => _error = issue.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = automatic
              ? 'Recording time ended, but this example could not be finalized. Keep the full movement in view and retry.'
              : 'This example was not usable. Keep more of the full movement in view and retry.',
        );
      }
    } finally {
      _cancelReferenceCaptureTimers();
      _finishReferenceFuture = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _finishingReference = false;
        });
      }
    }
  }

  void _startReferenceCaptureTimers(DateTime deadline) {
    _referenceCaptureDeadline = deadline;
    _referenceCaptureTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateReferenceCaptureTime(),
    );
    final untilDeadline = deadline.difference(DateTime.now());
    _referenceCaptureDeadlineTimer = Timer(
      untilDeadline.isNegative ? Duration.zero : untilDeadline,
      _expireReferenceCapture,
    );
    _updateReferenceCaptureTime();
  }

  void _updateReferenceCaptureTime() {
    final deadline = _referenceCaptureDeadline;
    if (!mounted || !_recording || deadline == null) {
      _cancelReferenceCaptureTimers();
      return;
    }
    final remaining =
        (deadline.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, _referenceCaptureDuration.inSeconds);
    if (remaining == 0) {
      _expireReferenceCapture();
    } else if (remaining != _referenceRemainingSeconds.value) {
      _referenceRemainingSeconds.value = remaining;
    }
  }

  void _expireReferenceCapture() {
    if (!mounted || !_recording) return;
    _referenceCaptureTimer?.cancel();
    _referenceCaptureTimer = null;
    _referenceCaptureDeadlineTimer?.cancel();
    _referenceCaptureDeadlineTimer = null;
    _referenceRemainingSeconds.value = 0;
    unawaited(_finishReference(automatic: true));
  }

  void _cancelReferenceCaptureTimers() {
    _referenceCaptureTimer?.cancel();
    _referenceCaptureTimer = null;
    _referenceCaptureDeadlineTimer?.cancel();
    _referenceCaptureDeadlineTimer = null;
    _referenceCaptureDeadline = null;
    if (mounted) {
      _referenceRemainingSeconds.value = _referenceCaptureDuration.inSeconds;
    }
  }

  String _formatReferenceCaptureRemaining(int remainingSeconds) {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _delete(_ReferenceDraft reference) async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      if (_previewId == reference.id) {
        await _playback.release();
        if (mounted) setState(() => _previewId = null);
      }
      _requireAccepted(await _socket.sendDeleteCustomReference(reference.id));
      if (mounted) {
        setState(() {
          _references.removeWhere((item) => item.id == reference.id);
          _template = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not delete this example. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectPreview(_ReferenceDraft reference) async {
    if (_busy || _recording) return;
    if (_previewId == reference.id) {
      setState(() {
        _pendingStart = reference.startMs;
        _pendingEnd = reference.endMs;
      });
      return;
    }
    await _playback.release();
    if (!mounted) return;
    setState(() {
      _previewId = reference.id;
      _pendingStart = reference.startMs;
      _pendingEnd = reference.endMs;
    });
  }

  Future<void> _applyTrim(_ReferenceDraft reference, int start, int end) async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      await _commitTrim(reference, start, end);
    } on _ReferenceIssue catch (issue) {
      if (mounted) {
        setState(
          () => _error = '${issue.message} The previous trim is still saved.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Keep more of the movement in the clip. The previous trim is still saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commitTrim(
    _ReferenceDraft reference,
    int start,
    int end,
  ) async {
    final ack = await _socket.sendTrimCustomReference(
      reference.id,
      startMs: start,
      endMs: end,
    );
    if (!ack.accepted) {
      final issue = _issueMessage(ack);
      if (issue != null) throw _ReferenceIssue(issue);
    }
    _requireAccepted(ack);
    if (mounted) {
      setState(() {
        reference.startMs = start;
        reference.endMs = end;
        reference.semanticIssue = null;
        if (_previewId == reference.id) {
          _pendingStart = start;
          _pendingEnd = end;
        }
        _template = null;
        _error = null;
      });
    }
  }

  Future<void> _review() async {
    if (_replacingReferences && _references.length < _requiredReferences) {
      setState(
        () => _error = customReferenceIssueMessage(
          'invalid_reference_count',
          null,
          movementBehavior: _movementBehavior,
          propLabel: _prop.displayLabel,
        ),
      );
      return;
    }
    if (_replacingReferences) {
      setState(() {
        _busy = true;
        _buildingTemplate = true;
      });
      try {
        final selectedReference = _references
            .where((reference) => reference.id == _previewId)
            .firstOrNull;
        if (selectedReference != null &&
            (_pendingStart != selectedReference.startMs ||
                _pendingEnd != selectedReference.endMs)) {
          try {
            await _commitTrim(selectedReference, _pendingStart, _pendingEnd);
          } catch (_) {
            throw StateError(
              'Could not apply the trim. Keep more of the full movement in the clip, then try reviewing again. Your previous trim is still saved.',
            );
          }
        }
        final ack = await _socket.sendBuildCustomTemplate(
          movementBehavior: _movementBehavior,
        );
        if (!ack.accepted) {
          // Mark the example the backend identified so its card shows it.
          final index = ack.referenceQuality?['reference_index'];
          if (index is int && index >= 0 && index < _references.length) {
            final issue = ack.errorCode;
            if (mounted) {
              setState(() => _references[index].semanticIssue = issue);
            }
          }
          final issue = _issueMessage(ack);
          if (issue != null) throw StateError(issue);
        }
        if (!ack.accepted && ack.errorCode == 'insufficient_frames') {
          throw StateError(
            'The selected clip is too short or does not contain enough of the full movement. Adjust the trim to include the complete movement, then review again.',
          );
        }
        _requireAccepted(ack);
        final template = MovementTemplate.tryFrom(ack.movementTemplate);
        if (template == null || !template.isReady) {
          throw StateError(
            'ELIXR could not learn this movement from the current examples.',
          );
        }
        if (mounted) {
          setState(() {
            _template = template;
            _step = 2;
            _error = null;
            for (final reference in _references) {
              reference.semanticIssue = null;
            }
          });
        }
      } catch (error) {
        if (mounted) {
          setState(
            () => _error = error is StateError
                ? error.message
                : 'Could not learn this movement. Review your examples and try again.',
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _buildingTemplate = false;
          });
        }
      }
    } else {
      setState(() => _step = 2);
    }
  }

  Future<void> _save() async {
    final savedMovement = _savedMovement;
    if (savedMovement != null) {
      Navigator.of(context).pop(savedMovement);
      return;
    }
    final template = _template;
    final metadataError = CustomMovement.validateMetadata(
      name: _name.text,
      description: _description.text,
      difficulty: _difficulty,
    );
    if (metadataError != null || template == null || !_hasUsableTemplate) {
      setState(
        () => _error =
            metadataError ??
            customReferenceIssueMessage(
              'invalid_reference_count',
              null,
              movementBehavior: _movementBehavior,
              propLabel: _prop.displayLabel,
            ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.existing == null
          ? await widget.repository.createMovement(
              ownerUid: widget.ownerUid,
              ownerRole: widget.ownerRole,
              name: _name.text,
              description: _description.text,
              difficulty: _difficulty,
              propType: _prop,
              template: template,
              referenceImageJpegBytes: _referenceImageJpegBytes,
            )
          : await widget.repository.publishRevision(
              current: widget.existing!,
              name: _name.text,
              description: _description.text,
              difficulty: _difficulty,
              propType: _prop,
              template: template,
              referenceImageJpegBytes: _referenceImageJpegBytes,
            );
      _savedMovement = result;
      await _teardown(reportFailure: true);
      if (mounted) Navigator.of(context).pop(result);
    } on CustomMovementSaveException catch (error) {
      emitCustomMovementSaveDiagnostic(
        stage: error.stage,
        error: error.cause,
        stackTrace: error.stackTrace,
      );
      if (mounted) {
        setState(
          () => _error = customMovementSaveFailureMessage(
            stage: error.stage,
            cause: error.cause,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      emitCustomMovementSaveDiagnostic(
        stage: CustomMovementSaveStage.unknown,
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = CustomMovementSaveStage.unknown.userMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_busy) return;
    final savedMovement = _savedMovement;
    if (savedMovement != null) {
      Navigator.of(context).pop(savedMovement);
      return;
    }
    setState(() => _busy = true);
    await _teardown();
    if (mounted) Navigator.of(context).pop();
  }

  void _nextDetails() {
    if (_resettingProp) return;
    final error = CustomMovement.validateMetadata(
      name: _name.text,
      description: _description.text,
      difficulty: _difficulty,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _step = 1;
      _error = null;
    });
    if (widget.existing == null || _replacingReferences || _template == null) {
      unawaited(_prepare());
    }
  }

  void _previousStep() => setState(() {
    _step--;
    _error = null;
  });

  void _retryCamera() {
    if (_initializing) return;
    unawaited(_prepare());
  }

  void _setMovementBehavior(String value) {
    if (value == _movementBehavior) return;
    setState(() {
      _movementBehavior = value;
      _template = null;
      _replacingReferences = true;
    });
  }

  void _changeProp(TrainingProp value) {
    if (value == _prop) return;
    if (_sessionStarted) {
      _resettingProp = true;
      unawaited(() async {
        try {
          await _resetSession();
        } finally {
          if (mounted) {
            setState(() => _resettingProp = false);
          }
        }
      }());
    }
    setState(() {
      _prop = value;
      _template = null;
      _replacingReferences = true;
    });
  }

  bool get _setupLocked => _references.isNotEmpty || _recording || _busy;

  // ---------------------------------------------------------------------------
  // Shared presentation helpers
  // ---------------------------------------------------------------------------

  Widget _surface(
    Widget child, {
    bool tinted = false,
    EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.md),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: tinted
          ? context.elixColors.surfaceTinted
          : context.elixColors.surfaceRaised,
      borderRadius: BorderRadius.circular(ElixRadius.panel),
      border: Border.all(color: context.elixColors.borderSubtle),
    ),
    child: child,
  );

  Widget _cardHeading(String title, [String? subtitle]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: ElixTypography.sectionTitle(
          context,
          color: context.elixTextPrimary,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
      ],
    ],
  );

  Widget _field(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: ElixTypography.label(color: context.elixTextPrimary)),
      const SizedBox(height: AppSpacing.sm),
      control,
    ],
  );

  // ---------------------------------------------------------------------------
  // Step 1: Set up
  // ---------------------------------------------------------------------------

  Widget _details() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final basics = _basicsCard();
          final setup = _setupCard();
          if (constraints.maxWidth < 880) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                basics,
                const SizedBox(height: AppSpacing.md),
                setup,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: basics),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 9, child: setup),
            ],
          );
        },
      ),
    ),
  );

  Widget _basicsCard() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeading(
          'Movement basics',
          'Give it a clear name and explain how to perform it.',
        ),
        const SizedBox(height: AppSpacing.md),
        _field(
          'Movement name',
          TextBox(
            key: const ValueKey('custom-movement-name'),
            controller: _name,
            maxLength: CustomMovement.nameMaxLength,
            placeholder: 'For example, Bottle Loop',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(
          'How to perform it',
          TextBox(
            key: const ValueKey('custom-movement-description'),
            controller: _description,
            minLines: 4,
            maxLines: 7,
            maxLength: CustomMovement.descriptionMaxLength,
            placeholder:
                'Describe each step from start to finish, including the important body, hand, and prop actions',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Describe it step by step. ELIXR shows these instructions during practice.',
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
      ],
    ),
  );

  Widget _setupCard() {
    final locked = _setupLocked;
    return _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeading('Movement setup'),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Movement behavior',
            style: ElixTypography.label(color: context.elixTextPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            label: 'Movement behavior',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthoringChoiceCard(
                  key: const ValueKey('custom-movement-behavior-dynamic'),
                  title: 'Dynamic sequence',
                  description:
                      'Use this for any visible change: a grip transition, wrist or arm movement, prop path, or toss. Small movements are okay.',
                  icon: FluentIcons.play,
                  selected: _movementBehavior == 'dynamic',
                  onPressed: locked
                      ? null
                      : () => _setMovementBehavior('dynamic'),
                ),
                const SizedBox(height: AppSpacing.sm),
                AuthoringChoiceCard(
                  key: const ValueKey('custom-movement-behavior-static'),
                  title: 'Static hold',
                  description:
                      'Use this for a grip, stall, or final position that should be held steady.',
                  icon: FluentIcons.pause,
                  selected: _movementBehavior == 'static',
                  onPressed: locked
                      ? null
                      : () => _setMovementBehavior('static'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final difficulty = _field(
                'Difficulty',
                ComboBox<String>(
                  key: const ValueKey('custom-movement-difficulty'),
                  value: _difficulty,
                  isExpanded: true,
                  items: CustomMovement.allowedDifficulties
                      .map(
                        (item) => ComboBoxItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _difficulty = value);
                  },
                ),
              );
              final prop = _field(
                'Prop',
                ComboBox<TrainingProp>(
                  key: const ValueKey('custom-movement-prop'),
                  value: _prop,
                  isExpanded: true,
                  items: CustomMovement.supportedProps
                      .map(
                        (item) => ComboBoxItem(
                          value: item,
                          child: Text(item.displayLabel),
                        ),
                      )
                      .toList(),
                  onChanged: locked
                      ? null
                      : (value) {
                          if (value != null) _changeProp(value);
                        },
                ),
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    difficulty,
                    const SizedBox(height: AppSpacing.md),
                    prop,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: difficulty),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: prop),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _references.isEmpty
                ? 'Use the same prop in every example.'
                : 'Delete recorded examples to change the behavior or prop.',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
          if (_prop == TrainingProp.bottle) ...[
            const SizedBox(height: AppSpacing.md),
            _rotationCallout(),
          ],
        ],
      ),
    );
  }

  Widget _rotationCallout() => Container(
    key: const ValueKey('custom-movement-rotation-info'),
    padding: const EdgeInsets.all(AppSpacing.smPlus),
    decoration: BoxDecoration(
      color: context.elixColors.surfaceTinted,
      borderRadius: BorderRadius.circular(ElixRadius.card),
      border: Border.all(color: context.elixColors.borderSubtle),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            FluentIcons.info,
            size: 14,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bottle rotation',
                style: ElixTypography.label(
                  color: context.elixTextPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'ELIXR can also learn visible bottle turns when the colored top and bottom markers are clear. Rotation is optional and will not block assessment.',
                style: ElixTypography.caption(color: context.elixTextSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // Step 2: Record examples
  // ---------------------------------------------------------------------------

  Widget _studioStep({required bool pinned}) {
    if (widget.existing != null && !_replacingReferences) {
      final card = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _savedVersionCard(),
        ),
      );
      return pinned ? SingleChildScrollView(child: card) : card;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            pinned &&
            constraints.maxWidth >= 1000 &&
            constraints.maxHeight >= 420;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 62, child: _capturePanel(fill: true)),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 38, child: _examplesPanel(fill: true)),
            ],
          );
        }
        final stacked = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _capturePanel(fill: false),
            const SizedBox(height: AppSpacing.md),
            _examplesPanel(fill: false),
          ],
        );
        return pinned ? SingleChildScrollView(child: stacked) : stacked;
      },
    );
  }

  Widget _savedVersionCard() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your saved movement is ready',
          style: ElixTypography.cardTitle(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Earlier recordings were not saved. You can keep this version or record new examples.',
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: ElixPrimaryButton(
            label: 'Record new examples',
            expanded: false,
            variant: ElixButtonVariant.outline,
            onPressed: () {
              setState(() {
                _replacingReferences = true;
                _template = null;
              });
              unawaited(_prepare());
            },
          ),
        ),
      ],
    ),
  );

  Widget _capturePanel({required bool fill}) {
    final header = LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Live camera',
              style: ElixTypography.sectionTitle(
                context,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _movementBehavior == 'static'
                  ? 'Show the grip or stall, then hold the final position steady.'
                  : 'Show the full movement from start to finish.',
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
          ],
        );
        final selector = CameraSourcePreference(
          settings: context.watch<SettingsService>(),
          cameras: context.watch<CameraDeviceService>(),
          compact: true,
          // Session preparation owns the camera here. Discovery runs only
          // from the selector's explicit Refresh action.
          refreshOnMount: false,
          enabled:
              !_initializing &&
              !_active &&
              !_recording &&
              !_busy &&
              _references.isEmpty,
          onSelectionBusyChanged: (busy) {
            if (mounted) setState(() => _cameraBusy = busy);
          },
          onSelectionSaved: _changeCamera,
        );
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: AppSpacing.smPlus),
              selector,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: 340, child: selector),
          ],
        );
      },
    );
    final camera = AspectRatio(aspectRatio: 16 / 9, child: _cameraView());
    return _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: AppSpacing.smPlus),
          if (fill) Expanded(child: Center(child: camera)) else camera,
          const SizedBox(height: AppSpacing.smPlus),
          _captureControls(singleLineGuidance: fill),
        ],
      ),
    );
  }

  Widget _cameraView() {
    final colors = context.elixColors;
    final countingDown = _countdown != null;
    final borderColor = _recording
        ? colors.error
        : countingDown
        ? colors.brandPrimary
        : colors.borderSubtle;
    final mirrored = context.read<SettingsService>().cameraMirrored;
    return Semantics(
      container: true,
      label: _recording
          ? 'Live camera, recording'
          : _previewReady
          ? 'Live camera preview'
          : 'Camera preview',
      child: AnimatedContainer(
        key: const ValueKey('custom-camera-frame'),
        duration: ElixMotion.duration(context, ElixMotion.micro),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: _recording ? 3 : (countingDown ? 2 : 1),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Preview frames arrive at camera rate. Only this subtree
              // repaints for them; the wizard rebuilds on state changes only.
              RepaintBoundary(
                child: ValueListenableBuilder<Uint8List?>(
                  valueListenable: _frame,
                  builder: (context, bytes, placeholder) => bytes == null
                      ? placeholder!
                      : Transform.flip(
                          flipX: mirrored,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                  child: _cameraPlaceholder(),
                ),
              ),
              if (_countdown case final value?) _countdownOverlay(value),
              Positioned(
                left: AppSpacing.smPlus,
                top: AppSpacing.smPlus,
                child: _cameraBadge(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraPlaceholder() {
    final colors = context.elixColors;
    final List<Widget> content;
    if (_cameraFailed) {
      content = [
        Icon(FluentIcons.warning, size: 28, color: colors.warning),
        const SizedBox(height: AppSpacing.smPlus),
        Text(
          'Camera could not start',
          style: ElixTypography.body(
            color: colors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Check that the camera is connected and not in use by another app, then try again.',
          textAlign: TextAlign.center,
          style: ElixTypography.supporting(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        ElixPrimaryButton(
          key: const ValueKey('custom-camera-retry'),
          label: 'Retry camera',
          icon: FluentIcons.refresh,
          expanded: false,
          onPressed: _initializing ? null : _retryCamera,
        ),
      ];
    } else if (_initializing || _sessionStarted) {
      final cameraName =
          context.read<SettingsService>().selectedCameraDisplayName ??
          'Auto-select camera';
      content = [
        SizedBox(
          width: 32,
          height: 32,
          child: ProgressRing(strokeWidth: 3, activeColor: colors.brandPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Starting camera…',
          style: ElixTypography.body(
            color: colors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          cameraName,
          style: ElixTypography.label(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This may take a moment while ELIXR checks the camera.',
          textAlign: TextAlign.center,
          style: ElixTypography.supporting(color: colors.textSecondary),
        ),
      ];
    } else {
      content = [
        Icon(FluentIcons.camera, size: 28, color: colors.textSecondary),
        const SizedBox(height: AppSpacing.smPlus),
        Text(
          'Camera is off',
          style: ElixTypography.body(
            color: colors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        ElixPrimaryButton(
          key: const ValueKey('custom-camera-start'),
          label: 'Start camera',
          expanded: false,
          onPressed: _retryCamera,
        ),
      ];
    }
    return ColoredBox(
      key: const ValueKey('custom-camera-placeholder'),
      color: colors.canvasDeep,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, children: content),
            ),
          ),
        ),
      ),
    );
  }

  Widget _countdownOverlay(int value) => Semantics(
    liveRegion: true,
    label: 'Recording starts in $value',
    child: ExcludeSemantics(
      child: ColoredBox(
        key: const ValueKey('custom-recording-countdown'),
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Recording starts in',
                  style: ElixTypography.cardTitle(color: Colors.white),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _cameraBadge() {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    Widget pill({
      required List<Widget> children,
      required Color background,
      Color? border,
    }) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smPlus,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ElixRadius.pill),
        border: border == null ? null : Border.all(color: border, width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
    Widget dot(Color color) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    const onDark = Colors.white;
    if (_recording) {
      return Semantics(
        key: const ValueKey('custom-recording-badge'),
        liveRegion: true,
        label: 'Recording',
        child: pill(
          background: highContrast ? Colors.black : colors.error,
          border: highContrast ? colors.error : null,
          children: [
            dot(highContrast ? colors.error : onDark),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'REC',
              style: ElixTypography.label(
                color: onDark,
              ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            const SizedBox(width: AppSpacing.smPlus),
            ValueListenableBuilder<int>(
              valueListenable: _referenceRemainingSeconds,
              builder: (context, remaining, _) => Text(
                '${_formatReferenceCaptureRemaining(remaining)} remaining',
                style: ElixTypography.label(color: onDark),
              ),
            ),
          ],
        ),
      );
    }
    if (_finishingReference) {
      return pill(
        background: Colors.black.withValues(alpha: 0.7),
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Saving example…', style: ElixTypography.label(color: onDark)),
        ],
      );
    }
    if (_previewReady) {
      return pill(
        background: Colors.black.withValues(alpha: 0.55),
        children: [
          dot(colors.success),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'LIVE',
            style: ElixTypography.caption(
              color: onDark,
            ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// Pre-recording guidance using the backend-mirrored minimums.
  String get _recordingGuidance {
    String seconds(Duration value) =>
        (value.inMilliseconds / 1000).toStringAsFixed(1);
    final minimum = seconds(MovementTemplate.minimumReferenceDuration);
    return _movementBehavior == 'static'
        ? 'Record 1 clear example. Hold the final position steady for at least ${seconds(MovementTemplate.staticHoldDuration)} seconds. Each clip must be at least $minimum second long.'
        : 'Record 2 examples of the same movement. Small movements are okay. Each clip must be at least $minimum second long.';
  }

  String get _recordLabel {
    if (_recording) return 'Stop & save example';
    if (_finishingReference) return 'Saving example…';
    if (_countdown != null) return 'Get ready…';
    if (_references.length >= _maxReferences) return 'Example limit reached';
    if (_references.length < _requiredReferences) {
      return 'Record example ${_references.length + 1}';
    }
    return 'Record another example';
  }

  Widget _captureControls({required bool singleLineGuidance}) {
    final required = _requiredReferences;
    final count = _references.length;
    final action = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ElixPrimaryButton(
          key: const ValueKey('custom-reference-record'),
          label: _recordLabel,
          icon: _recording ? FluentIcons.stop_solid : FluentIcons.circle_fill,
          variant: _recording
              ? ElixButtonVariant.destructive
              : ElixButtonVariant.primary,
          expanded: false,
          onPressed: _recording
              ? (_busy ? null : () => _finishReference())
              : (_canRecord ? _record : null),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          count < required
              ? '$count of $required required · Up to $_maxReferences examples'
              : '$count of $_maxReferences examples recorded',
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
      ],
    );
    final checks = _cameraChecks(singleLineGuidance: singleLineGuidance);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              checks,
              const SizedBox(height: AppSpacing.smPlus),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: checks),
            const SizedBox(width: AppSpacing.md),
            action,
          ],
        );
      },
    );
  }

  Widget _cameraChecks({required bool singleLineGuidance}) {
    final live = _sessionStarted && _previewReady;
    AuthoringCheckState state(bool ok) => !live
        ? AuthoringCheckState.pending
        : ok
        ? AuthoringCheckState.ok
        : AuthoringCheckState.missing;
    final (message, tone) = _cameraGuidance();
    final colors = context.elixColors;
    return Semantics(
      container: true,
      label: 'Camera check',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AuthoringStatusPill(
                key: const ValueKey('camera-check-person'),
                label: '1 person',
                state: state(_personCount == 1),
              ),
              AuthoringStatusPill(
                key: const ValueKey('camera-check-prop'),
                label: _prop.displayLabel,
                state: state(_propVisible),
              ),
              AuthoringStatusPill(
                key: const ValueKey('camera-check-hands'),
                label: 'Hands',
                state: state(_handsVisible),
              ),
              AuthoringStatusPill(
                key: const ValueKey('camera-check-body'),
                label: 'Upper body',
                state: state(_upperBodyVisible),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const ValueKey('camera-check-guidance'),
              maxLines: singleLineGuidance ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: ElixTypography.label(
                color: switch (tone) {
                  AuthoringCheckState.ok => colors.success,
                  AuthoringCheckState.missing => colors.warning,
                  AuthoringCheckState.pending => colors.textSecondary,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One concise next action for the camera check, in priority order.
  (String, AuthoringCheckState) _cameraGuidance() {
    const pending = AuthoringCheckState.pending;
    const missing = AuthoringCheckState.missing;
    if (_recording) {
      return (
        _movementBehavior == 'static'
            ? 'Recording. Hold the final position steady, then stop to save.'
            : 'Recording. Perform the full movement, then stop to save.',
        pending,
      );
    }
    if (_finishingReference) return ('Saving this example…', pending);
    if (_countdown != null) {
      return ('Get into your starting position.', pending);
    }
    if (!_sessionStarted || !_previewReady) {
      return (
        'The camera check starts when the live preview appears.',
        pending,
      );
    }
    if (_references.length >= _maxReferences) {
      return ('Maximum of $_maxReferences examples recorded.', pending);
    }
    final people = _personCount ?? 0;
    if (people == 0) return ('Step into view so ELIXR can see you.', missing);
    if (people > 1) {
      return ('Only one person should be in view to record.', missing);
    }
    if (!_propVisible) {
      return (
        'Hold your ${_prop.displayLabel.toLowerCase()} where the camera can see it.',
        missing,
      );
    }
    if (!_handsVisible) {
      return ('Move your hands fully into view to start recording.', missing);
    }
    if (!_upperBodyVisible) {
      return (
        'Keep your shoulders and one arm in view to start recording.',
        missing,
      );
    }
    if (!_canRecord) {
      return ('Hold steady while ELIXR confirms the view…', pending);
    }
    return (
      'Everything is in view. You can record now.',
      AuthoringCheckState.ok,
    );
  }

  Widget _examplesPanel({required bool fill}) {
    final count = _references.length;
    final required = _requiredReferences;
    final selectedIndex = _references.indexWhere(
      (item) => item.id == _previewId,
    );
    final ready = count >= required;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Examples',
                style: ElixTypography.sectionTitle(
                  context,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            AuthoringStatusPill(
              key: const ValueKey('examples-progress'),
              label: ready ? '$count recorded' : '$count of $required required',
              state: ready
                  ? AuthoringCheckState.ok
                  : AuthoringCheckState.pending,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (ready) ...[
          Row(
            children: [
              Icon(
                FluentIcons.completed_solid,
                size: 14,
                color: context.elixColors.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Ready to review',
                style: ElixTypography.label(
                  color: context.elixColors.success,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
        Text(
          count >= _maxReferences
              ? 'You have reached the 5 example limit.'
              : count < required
              ? _recordingGuidance
              : count == required && _movementBehavior != 'static'
              ? 'A third example can help ELIXR learn the movement more consistently.'
              : 'You can review whenever you are ready.',
          key: const ValueKey('examples-guidance'),
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_references.isEmpty) _emptyExamples() else _exampleSlots(),
        if (selectedIndex >= 0) ...[
          const SizedBox(height: AppSpacing.md),
          _exampleEditor(_references[selectedIndex], selectedIndex),
        ] else if (_references.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Select an example to preview or trim it.',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
        ],
      ],
    );
    return _surface(fill ? SingleChildScrollView(child: content) : content);
  }

  Widget _emptyExamples() => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.lg,
    ),
    decoration: BoxDecoration(
      color: context.elixColors.surfaceInteractive.withValues(
        alpha: context.isHighContrast ? 0 : 0.45,
      ),
      borderRadius: BorderRadius.circular(ElixRadius.card),
      border: Border.all(color: context.elixColors.borderSubtle),
    ),
    child: Column(
      children: [
        Icon(FluentIcons.video, size: 22, color: context.elixTextSecondary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your recordings will appear here. Select one to preview or trim it.',
          textAlign: TextAlign.center,
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
      ],
    ),
  );

  Widget _exampleSlots() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 420
          ? 3
          : constraints.maxWidth >= 260
          ? 2
          : 1;
      final width =
          (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (var index = 0; index < _references.length; index++)
            SizedBox(
              width: width,
              child: _exampleTile(_references[index], index),
            ),
        ],
      );
    },
  );

  Widget _exampleTile(_ReferenceDraft reference, int index) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final selected = _previewId == reference.id;
    final weakHands = reference.quality?.handsHardToSee == true;
    final kept = formatClipTime(reference.endMs - reference.startMs);
    return Semantics(
      selected: selected,
      child: HoverButton(
        key: ValueKey('example-select-${reference.id}'),
        onPressed: _busy || _recording ? null : () => _selectPreview(reference),
        semanticLabel:
            'Example ${index + 1}, accepted, $kept'
            '${reference.isTrimmed ? ', trimmed' : ''}'
            '${weakHands ? ', hands were hard to see' : ''}',
        builder: (context, states) {
          final focused = states.isFocused;
          final hovered = states.isHovered && !selected;
          return AnimatedContainer(
            key: ValueKey('example-card-${reference.id}'),
            duration: ElixMotion.duration(context, ElixMotion.micro),
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: selected && !highContrast
                  ? colors.surfaceSelected
                  : hovered
                  ? colors.interactiveHover
                  : colors.surfaceInteractive,
              borderRadius: BorderRadius.circular(ElixRadius.card),
              border: Border.all(
                color: focused
                    ? colors.focusRing
                    : selected
                    ? colors.borderInteractive
                    : colors.borderSubtle,
                width: focused || selected ? (highContrast ? 3 : 2) : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Example ${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ElixTypography.label(
                          color: colors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Tooltip(
                      message: 'Accepted',
                      child: Icon(
                        FluentIcons.completed_solid,
                        size: 13,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$kept${reference.isTrimmed ? ' · Trimmed' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.caption(color: colors.textSecondary),
                ),
                if (weakHands) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        FluentIcons.warning,
                        size: 10,
                        color: colors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Hands hard to see',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ElixTypography.caption(color: colors.warning),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _coverage(double? value) =>
      value == null ? 'not reported' : '${(value * 100).round()}%';

  /// Compact per-example quality: what ELIXR saw and what review will check.
  Widget _qualityChips(_ReferenceDraft reference) {
    final quality = reference.quality;
    AuthoringCheckState coverageState(double? value, double minimum) =>
        value == null
        ? AuthoringCheckState.pending
        : value >= minimum
        ? AuthoringCheckState.ok
        : AuthoringCheckState.missing;
    final keptMs = reference.endMs - reference.startMs;
    final isStatic = _movementBehavior == 'static';
    final issue = reference.semanticIssue;
    final motionIssue = const {
      'no_meaningful_motion',
      'inconsistent_dynamic_references',
      'unstable_static_reference',
      'inconsistent_static_references',
    }.contains(issue);
    return Wrap(
      key: const ValueKey('reference-quality'),
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        AuthoringStatusPill(
          key: const ValueKey('reference-quality-hands'),
          label: 'Hands',
          detail: _coverage(quality?.bestHandCoverage),
          state: coverageState(
            quality?.bestHandCoverage,
            _ReferenceQuality.minimumCoverageHint,
          ),
        ),
        AuthoringStatusPill(
          key: const ValueKey('reference-quality-body'),
          label: 'Body',
          detail: _coverage(quality?.poseCoverage),
          state: coverageState(
            quality?.poseCoverage,
            _ReferenceQuality.minimumCoverageHint,
          ),
        ),
        AuthoringStatusPill(
          key: const ValueKey('reference-quality-prop'),
          label: 'Prop',
          detail: _coverage(quality?.propCoverage),
          state: coverageState(
            quality?.propCoverage,
            _ReferenceQuality.minimumPropCoverageHint,
          ),
        ),
        AuthoringStatusPill(
          key: const ValueKey('reference-quality-motion'),
          label: isStatic ? 'Hold' : 'Movement',
          detail: motionIssue
              ? 'needs attention'
              : _template != null
              ? 'learned'
              : 'checked at review',
          state: motionIssue
              ? AuthoringCheckState.missing
              : _template != null
              ? AuthoringCheckState.ok
              : AuthoringCheckState.pending,
        ),
        AuthoringStatusPill(
          key: const ValueKey('reference-quality-duration'),
          label: 'Duration',
          detail: '${(keptMs / 1000).toStringAsFixed(1)} s',
          state:
              keptMs >= MovementTemplate.minimumReferenceDuration.inMilliseconds
              ? AuthoringCheckState.ok
              : AuthoringCheckState.missing,
        ),
      ],
    );
  }

  Widget _exampleEditor(_ReferenceDraft reference, int index) {
    final colors = context.elixColors;
    final editable = !_busy && !_recording;
    final dirty =
        _pendingStart != reference.startMs || _pendingEnd != reference.endMs;
    final fullRange = _pendingStart == 0 && _pendingEnd == reference.durationMs;
    final quality = reference.quality;
    return Container(
      key: const ValueKey('custom-reference-editor'),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: colors.surfaceTinted,
        borderRadius: BorderRadius.circular(ElixRadius.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(FluentIcons.trim, size: 14, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Preview & trim',
                  style: ElixTypography.label(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Tooltip(
                message: 'Delete example ${index + 1}',
                child: IconButton(
                  key: ValueKey('example-delete-${reference.id}'),
                  onPressed: editable ? () => _delete(reference) : null,
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.delete, size: 12, color: colors.error),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Delete',
                        style: ElixTypography.caption(color: colors.error),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              // Video surface plus the player's own playback controls.
              height: math.min(constraints.maxWidth * 9 / 16, 220) + 76,
              child: ElixrVideoPlayer(
                key: ValueKey('reference-player-${reference.id}'),
                source: Uri.file(reference.path),
                session: _playback,
                clipStart: Duration(milliseconds: _pendingStart),
                clipEnd: Duration(milliseconds: _pendingEnd),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _qualityChips(reference),
          if (quality != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tracking: left hand ${_coverage(quality.leftHandCoverage)} · right hand ${_coverage(quality.rightHandCoverage)} · upper body ${_coverage(quality.poseCoverage)}',
              style: ElixTypography.caption(color: colors.textSecondary),
            ),
            if (quality.handsHardToSee)
              Text(
                'Try keeping your hands fully in frame on your next example.',
                style: ElixTypography.caption(color: colors.warning),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Drag the handles to keep only the movement. Your original recording stays intact.',
            style: ElixTypography.caption(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ReferenceTrimTimeline(
            durationMs: reference.durationMs,
            startMs: _pendingStart,
            endMs: _pendingEnd,
            enabled: editable,
            onChanged: (start, end) => setState(() {
              _pendingStart = start;
              _pendingEnd = end;
            }),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                'Start ${formatClipTime(_pendingStart)}',
                key: const ValueKey('trim-start-time'),
                style: ElixTypography.caption(color: colors.textSecondary),
              ),
              Expanded(
                child: Text(
                  'Keeps ${formatClipTime(_pendingEnd - _pendingStart)}',
                  key: const ValueKey('trim-kept-time'),
                  textAlign: TextAlign.center,
                  style: ElixTypography.label(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'End ${formatClipTime(_pendingEnd)}',
                key: const ValueKey('trim-end-time'),
                style: ElixTypography.caption(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  dirty ? 'Trim not applied yet' : '',
                  style: ElixTypography.caption(color: colors.textSecondary),
                ),
              ),
              Button(
                key: const ValueKey('trim-reset'),
                onPressed: editable && !fullRange
                    ? () => setState(() {
                        _pendingStart = 0;
                        _pendingEnd = reference.durationMs;
                      })
                    : null,
                child: const Text('Reset'),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElixPrimaryButton(
                key: const ValueKey('trim-apply'),
                label: 'Apply trim',
                expanded: false,
                onPressed: editable && dirty
                    ? () => _applyTrim(reference, _pendingStart, _pendingEnd)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3: Review & save
  // ---------------------------------------------------------------------------

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 2),
        Text(value, style: ElixTypography.body(color: context.elixTextPrimary)),
      ],
    ),
  );

  Widget _learnedRow(
    String label,
    bool learned, {
    required String keyName,
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ElixTypography.supporting(color: context.elixTextPrimary),
          ),
        ),
        AuthoringStatusPill(
          key: ValueKey('learned-$keyName'),
          label: learned
              ? 'Learned'
              : optional
              ? 'Not learned · optional'
              : 'Not learned',
          state: learned
              ? AuthoringCheckState.ok
              : optional
              ? AuthoringCheckState.pending
              : AuthoringCheckState.missing,
        ),
      ],
    ),
  );

  Widget _missingCapabilityCallout({
    required bool handsLearned,
    required bool poseLearned,
  }) {
    final colors = context.elixColors;
    final (title, message) = !handsLearned && !poseLearned
        ? (
            'Only prop movement was learned',
            'Hands and upper body were not tracked consistently. You can still save; recording with both in view gives a better assessment.',
          )
        : !handsLearned
        ? (
            'Hands were not learned',
            'Hands were not tracked consistently. You can still save; recording with your hands fully in view gives a better assessment.',
          )
        : (
            'Upper body was not learned',
            'Upper body movement was not tracked consistently. You can still save; recording with your upper body in view gives a better assessment.',
          );
    return Container(
      key: const ValueKey('custom-movement-learning-warning'),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? Colors.transparent
            : colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ElixRadius.card),
        border: Border.all(
          color: colors.warning.withValues(
            alpha: context.isHighContrast ? 1 : 0.45,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.warning, size: 14, color: colors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: ElixTypography.label(
                    color: colors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: ElixTypography.caption(color: colors.textSecondary),
          ),
          if (_replacingReferences) ...[
            const SizedBox(height: AppSpacing.smPlus),
            ElixPrimaryButton(
              key: const ValueKey('custom-movement-rerecord'),
              label: 'Record better examples',
              icon: FluentIcons.record2,
              variant: ElixButtonVariant.outline,
              expanded: false,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _step = 1;
                      _error = null;
                    }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final capabilities =
        _template?.featureCapabilities ?? const <String, bool>{};
    final handsLearned = capabilities['hands'] == true;
    final poseLearned = capabilities['pose'] == true;
    final rotationLearned = capabilities['prop_rotation'] == true;
    final details = _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeading('Movement details'),
          const SizedBox(height: AppSpacing.md),
          _reviewRow('Name', _name.text.trim()),
          _reviewRow('How to perform it', _description.text.trim()),
          _reviewRow(
            'Behavior',
            _movementBehavior == 'static' ? 'Static hold' : 'Dynamic sequence',
          ),
          _reviewRow('Difficulty', _difficulty),
          _reviewRow('Prop', _prop.displayLabel),
          _reviewRow(
            'Examples',
            _replacingReferences
                ? '${_references.length} recorded'
                : 'Saved version',
          ),
          if (_replacingReferences &&
              _movementBehavior != 'static' &&
              _references.length == _requiredReferences)
            Text(
              'You can save now. A third example may improve consistency.',
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
          if (!_replacingReferences)
            Text(
              'Earlier recordings are not available, but this version remains active.',
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
        ],
      ),
    );
    final learned = _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeading(
            'What ELIXR learned',
            'These signals are used to assess this movement during practice.',
          ),
          const SizedBox(height: AppSpacing.md),
          _learnedRow(
            '${_prop.displayLabel} movement',
            capabilities['prop_translation'] == true,
            keyName: 'prop',
          ),
          _learnedRow('Hands', handsLearned, keyName: 'hands'),
          _learnedRow('Upper body', poseLearned, keyName: 'pose'),
          if (_prop == TrainingProp.bottle) ...[
            _learnedRow(
              'Visible bottle rotation',
              rotationLearned,
              keyName: 'rotation',
              optional: true,
            ),
            if (!rotationLearned)
              Text(
                'Rotation is optional. This movement can still be saved and scored.',
                style: ElixTypography.caption(color: context.elixTextSecondary),
              ),
          ],
          if (!handsLearned || !poseLearned) ...[
            const SizedBox(height: AppSpacing.md),
            _missingCapabilityCallout(
              handsLearned: handsLearned,
              poseLearned: poseLearned,
            ),
          ],
        ],
      ),
      tinted: true,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: AppSpacing.md),
                  learned,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: learned),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Wizard shell
  // ---------------------------------------------------------------------------

  Widget _stepBody({required bool pinned}) {
    Widget scroll(Widget child) => pinned
        ? SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: child,
          )
        : child;
    return switch (_step) {
      0 => scroll(_details()),
      1 => _studioStep(pinned: pinned),
      _ => scroll(_reviewStep()),
    };
  }

  String _footerHint() {
    switch (_step) {
      case 0:
        return _movementBehavior == 'static'
            ? 'Next, you will record 1 clear example of the held position.'
            : 'Next, you will record the movement 2 to 5 times.';
      case 1:
        final missing = _requiredReferences - _references.length;
        if (_recording || _finishingReference) {
          return 'Finish the current example to continue.';
        }
        if (_replacingReferences && missing > 0) {
          return 'Record $missing more example${missing == 1 ? '' : 's'} to continue.';
        }
        return '';
      default:
        return _savedMovement == null
            ? 'You can edit this movement later.'
            : '';
    }
  }

  Widget _primaryAction() => switch (_step) {
    0 => ElixPrimaryButton(
      key: const ValueKey('custom-movement-next'),
      onPressed: _resettingProp ? null : _nextDetails,
      label: 'Continue to recording',
      icon: FluentIcons.chevron_right,
      expanded: false,
    ),
    1 => ElixPrimaryButton(
      key: const ValueKey('custom-movement-review'),
      onPressed:
          _busy ||
              _recording ||
              (_replacingReferences && _references.length < _requiredReferences)
          ? null
          : _review,
      isLoading: _buildingTemplate,
      label: _buildingTemplate ? 'Learning movement…' : 'Continue to review',
      icon: _buildingTemplate ? null : FluentIcons.chevron_right,
      expanded: false,
    ),
    _ => ElixPrimaryButton(
      key: const ValueKey('custom-movement-save'),
      onPressed: _busy || !_hasUsableTemplate ? null : _save,
      label: _busy
          ? 'Saving…'
          : _savedMovement == null
          ? 'Save movement'
          : 'Close',
      expanded: false,
    ),
  };

  Widget _footer() {
    final colors = context.elixColors;
    final hint = _footerHint();
    return Container(
      key: const ValueKey('custom-movement-wizard-footer'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.smPlus,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.canvas.withValues(
          alpha: context.isHighContrast ? 1 : 0.86,
        ),
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InfoBar(
              title: Text(
                _savedMovement == null
                    ? 'Please check this step'
                    : 'Movement saved',
              ),
              content: Text(_error!),
              severity: _savedMovement == null
                  ? InfoBarSeverity.error
                  : InfoBarSeverity.warning,
            ),
            const SizedBox(height: AppSpacing.smPlus),
          ],
          Row(
            children: [
              if (_step > 0)
                ElixPrimaryButton(
                  key: const ValueKey('custom-movement-back'),
                  label: 'Back',
                  expanded: false,
                  variant: ElixButtonVariant.outline,
                  onPressed: _busy || _recording ? null : _previousStep,
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  hint,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.caption(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _primaryAction(),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ElixScaffoldPage(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    header: ElixEditorialPageHeader(
      leading: ElixBackButton(onPressed: _busy ? null : _exit),
      eyebrow: 'CUSTOM MOVEMENT',
      heading: widget.existing == null ? 'Create movement' : 'Edit movement',
      // The recording studio needs the vertical space for the live camera.
      subtitle: _step == 1
          ? null
          : 'Teach ELIXR a movement using your own demonstrations.',
      variant: ElixEditorialHeaderVariant.compact,
    ),
    content: LayoutBuilder(
      builder: (context, constraints) {
        final pinned = constraints.maxHeight >= _minPinnedLayoutHeight;
        final stepper = Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.smPlus,
          ),
          child: AuthoringStepper(
            step: _step,
            labels: _stepLabels,
            dense: constraints.maxHeight < 820,
          ),
        );
        final body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TweenAnimationBuilder<double>(
            key: ValueKey('custom-movement-step-$_step'),
            tween: Tween(begin: 0, end: 1),
            duration: ElixMotion.duration(context, ElixMotion.standard),
            curve: ElixMotion.standardCurve,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 6),
                child: child,
              ),
            ),
            child: _stepBody(pinned: pinned),
          ),
        );
        final wizard = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            stepper,
            if (pinned) Expanded(child: body) else body,
            if (!pinned) const SizedBox(height: AppSpacing.md),
            _footer(),
          ],
        );
        final framed = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1480),
            child: wizard,
          ),
        );
        return pinned ? framed : SingleChildScrollView(child: framed);
      },
    ),
  );
}
