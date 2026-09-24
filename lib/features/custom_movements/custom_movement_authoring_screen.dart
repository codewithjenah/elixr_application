import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../core/widgets/elixr_video_player.dart';
import '../../data/models/custom_movement.dart';
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

class _ReferenceDraft {
  _ReferenceDraft({
    required this.id,
    required this.path,
    required this.durationMs,
  });

  final String id;
  final String path;
  final int durationMs;
  int startMs = 0;
  late int endMs = durationMs;
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
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final WebSocketService _socket;
  late final bool _ownsSocket;
  final ValueNotifier<Uint8List?> _frame = ValueNotifier(null);
  final ValueNotifier<PreviewFrame?> _presentation = ValueNotifier(null);
  final ElixrPlaybackSession _playback = ElixrPlaybackSession();
  StreamSubscription<PreviewFrame>? _previewSubscription;
  StreamSubscription<PracticeFeedback>? _feedbackSubscription;
  final List<_ReferenceDraft> _references = [];

  late String _difficulty;
  late TrainingProp _prop;
  MovementTemplate? _template;
  bool _trackRotation = false;
  bool _replacingReferences = false;
  bool _sessionStarted = false;
  bool _previewReady = false;
  bool _initializing = false;
  bool _active = false;
  bool _ready = false;
  bool _recording = false;
  bool _busy = false;
  bool _cameraBusy = false;
  bool _resettingProp = false;
  bool _closed = false;
  int? _personCount;
  int? _countdown;
  int _step = 0;
  String? _sessionId;
  String? _error;
  String? _previewId;
  int _pendingStart = 0;
  int _pendingEnd = 0;

  bool get _hasUsableTemplate =>
      _template?.isReady == true &&
      (!_trackRotation || _template?.requiresRotation == true);
  bool get _canRecord =>
      _sessionStarted &&
      _previewReady &&
      !_initializing &&
      !_busy &&
      !_cameraBusy &&
      !_recording &&
      _references.length < 5 &&
      _personCount == 1 &&
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
    _replacingReferences = widget.existing == null;
    _trackRotation =
        _prop == TrainingProp.bottle && _template?.requiresRotation == true;
  }

  @override
  void dispose() {
    unawaited(_teardown());
    _name.dispose();
    _description.dispose();
    _frame.dispose();
    _presentation.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    if (_closed) return;
    _closed = true;
    try {
      await _playback.release();
    } catch (_) {
      // Continue backend teardown if native playback release fails.
    }
    await _previewSubscription?.cancel();
    await _feedbackSubscription?.cancel();
    final id = _sessionId;
    _sessionId = null;
    if (id != null) {
      try {
        await _socket.stopPracticeSession(sessionId: id);
      } catch (_) {
        /* Disconnect closes the backend session. */
      }
    }
    try {
      await _socket.disconnect();
    } catch (_) {
      // A lost connection already closes its backend session.
    }
    if (_ownsSocket) _socket.dispose();
  }

  Future<void> _resetSession() async {
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
        _frame.value = null;
      });
    }
  }

  void _requireAccepted(CommandAck ack) {
    if (!ack.accepted) {
      throw StateError(ack.errorCode ?? ack.message ?? 'Command rejected');
    }
  }

  Future<void> _prepare() async {
    if (_sessionStarted || _initializing) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      _previewSubscription ??= _socket.previewStream.listen((preview) {
        if (!mounted) return;
        _presentation.value = preview;
        if (preview.hasJpeg) {
          _frame.value = preview.jpegBytes;
          if (!_previewReady) setState(() => _previewReady = true);
        }
      });
      _feedbackSubscription ??= _socket.feedbackStream.listen((feedback) {
        if (!mounted) return;
        setState(() {
          _ready = feedback.readinessStable == true;
          _personCount = feedback.personCount;
        });
      });
      final settings = context.read<SettingsService>();
      await _socket.connect();
      if (!_socket.isConnected) throw StateError('Backend unavailable');
      final id = _socket.beginPracticeAttempt();
      _sessionId = id;
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
          readinessSpec: const TeacherActivityReadinessSpec(),
        ),
      );
      _requireAccepted(await _socket.sendBeginReadiness(sessionId: id));
      if (!mounted) return;
      setState(() => _sessionStarted = true);
    } catch (_) {
      await _resetSession();
      if (mounted) {
        setState(
          () => _error =
              'Could not prepare the camera. Check the camera source and retry.',
        );
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
    setState(() {
      _busy = true;
      _error = null;
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
      _requireAccepted(
        await _socket.sendStartCustomCapture(durationSeconds: 15),
      );
      if (mounted) setState(() => _recording = true);
    } catch (_) {
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

  Future<void> _finishReference() async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    try {
      final ack = await _socket.sendStopCustomCapture();
      _requireAccepted(ack);
      final id = ack.referenceId;
      final path = ack.localFilePath;
      final duration = ack.videoDurationMs;
      if (id == null || path == null || duration == null || duration <= 0) {
        throw StateError('Incomplete reference clip metadata');
      }
      if (!mounted) return;
      setState(() {
        _references.add(
          _ReferenceDraft(id: id, path: path, durationMs: duration),
        );
        _template = null;
        _recording = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error =
              'This reference was not usable. Keep more of the full movement in view and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(_ReferenceDraft reference) async {
    if (_busy) return;
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
        setState(() => _error = 'Could not delete this reference. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectPreview(_ReferenceDraft reference) async {
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ack = await _socket.sendTrimCustomReference(
        reference.id,
        startMs: start,
        endMs: end,
      );
      _requireAccepted(ack);
      if (mounted) {
        setState(() {
          reference.startMs = start;
          reference.endMs = end;
          if (_previewId == reference.id) {
            _pendingStart = start;
            _pendingEnd = end;
          }
          _template = null;
          _error = null;
        });
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

  Future<void> _review() async {
    if (_replacingReferences &&
        _references.length < MovementTemplate.minimumReferences) {
      setState(
        () => _error = 'Record at least 2 valid references before reviewing.',
      );
      return;
    }
    if (_replacingReferences) {
      setState(() => _busy = true);
      try {
        final ack = await _socket.sendBuildCustomTemplate();
        _requireAccepted(ack);
        final template = MovementTemplate.tryFrom(ack.movementTemplate);
        if (template == null || !template.isReady) {
          throw StateError('Invalid template');
        }
        if (_trackRotation && !template.requiresRotation) {
          throw StateError(
            'Visible bottle rotation was not learned. Keep the orange top and yellow base markers in view.',
          );
        }
        if (mounted) {
          setState(() {
            _template = template;
            _step = 2;
            _error = null;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(
            () => _error = error is StateError
                ? error.message
                : 'Could not build the assessment. Review your references and retry.',
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      setState(() => _step = 2);
    }
  }

  Future<void> _save() async {
    final template = _template;
    final metadataError = CustomMovement.validateMetadata(
      name: _name.text,
      description: _description.text,
      difficulty: _difficulty,
    );
    if (metadataError != null || template == null || !_hasUsableTemplate) {
      setState(
        () => _error =
            metadataError ?? 'Record 2 valid references before saving.',
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
            )
          : await widget.repository.publishRevision(
              current: widget.existing!,
              name: _name.text,
              description: _description.text,
              difficulty: _difficulty,
              propType: _prop,
              template: template,
            );
      await _teardown();
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the movement. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_busy) return;
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

  Widget _surface(Widget child) => Container(
    padding: const EdgeInsets.all(AppSpacing.mdPlus),
    decoration: BoxDecoration(
      color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: FluentTheme.of(context).resources.cardStrokeColorDefault,
      ),
    ),
    child: child,
  );

  Widget _details() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Movement details',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: 6),
        const Text('Give your movement a name and choose what you will hold.'),
        const SizedBox(height: AppSpacing.md),
        const Text('Movement name'),
        TextBox(
          key: const ValueKey('custom-movement-name'),
          controller: _name,
          maxLength: CustomMovement.nameMaxLength,
          placeholder: 'For example, Bottle Flip',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Short description'),
        TextBox(
          key: const ValueKey('custom-movement-description'),
          controller: _description,
          minLines: 2,
          maxLines: 3,
          maxLength: CustomMovement.descriptionMaxLength,
          placeholder: 'Describe the movement from start to finish',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Difficulty'),
        ComboBox<String>(
          key: const ValueKey('custom-movement-difficulty'),
          value: _difficulty,
          isExpanded: true,
          items: CustomMovement.allowedDifficulties
              .map((item) => ComboBoxItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _difficulty = value);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Prop'),
        ComboBox<TrainingProp>(
          key: const ValueKey('custom-movement-prop'),
          value: _prop,
          isExpanded: true,
          items: CustomMovement.supportedProps
              .map(
                (item) =>
                    ComboBoxItem(value: item, child: Text(item.displayLabel)),
              )
              .toList(),
          onChanged: _references.isNotEmpty
              ? null
              : (value) {
                  if (value == null || value == _prop) return;
                  if (_sessionStarted) {
                    _resettingProp = true;
                    unawaited(() async {
                      try {
                        await _resetSession();
                      } finally {
                        if (mounted) setState(() => _resettingProp = false);
                      }
                    }());
                  }
                  setState(() {
                    _prop = value;
                    _template = null;
                    _replacingReferences = true;
                    if (value != TrainingProp.bottle) _trackRotation = false;
                  });
                },
        ),
        const SizedBox(height: 6),
        Text(
          _references.isEmpty
              ? 'Use a bottle or cocktail shaker for every demonstration.'
              : 'Delete recorded references before changing the prop.',
        ),
        if (_prop == TrainingProp.bottle) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ToggleSwitch(
                key: const ValueKey('custom-movement-require-rotation'),
                checked: _trackRotation,
                onChanged: (value) => setState(() {
                  _trackRotation = value;
                  if (_references.isEmpty &&
                      widget.existingRevision != null &&
                      _prop == widget.existing?.propType) {
                    _replacingReferences =
                        value &&
                        widget.existingRevision!.template.requiresRotation !=
                            true;
                    _template = widget.existingRevision!.template;
                  }
                }),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Track visible bottle rotation')),
            ],
          ),
          const Text(
            'For turns, place orange tape on the top and yellow tape on the base. Keep both visible while you move.',
          ),
        ],
      ],
    ),
  );

  Widget _camera() => AspectRatio(
    aspectRatio: 16 / 9,
    child: RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<Uint8List?>(
                valueListenable: _frame,
                builder: (context, bytes, _) => bytes == null
                    ? const Center(child: ProgressRing())
                    : Transform.flip(
                        flipX: context.read<SettingsService>().cameraMirrored,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
              ),
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
              Positioned(
                left: 12,
                top: 12,
                child: Text(
                  _recording ? '● Recording' : 'Live camera',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _time(int ms) {
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final hundredths = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$hundredths';
  }

  Widget _referenceCard(_ReferenceDraft reference, int index) => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reference ${index + 1}  ·  ${_time(reference.endMs - reference.startMs)}  ·  Good reference',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Button(
              onPressed: _busy ? null : () => _selectPreview(reference),
              child: const Text('Preview / Trim'),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: _busy ? null : () => _delete(reference),
              child: const Text('Delete'),
            ),
          ],
        ),
        if (_previewId == reference.id) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 260,
            child: ElixrVideoPlayer(
              key: ValueKey('reference-player-${reference.id}'),
              source: Uri.file(reference.path),
              session: _playback,
              clipStart: Duration(milliseconds: _pendingStart),
              clipEnd: Duration(milliseconds: _pendingEnd),
            ),
          ),
          const SizedBox(height: 8),
          Text('Start: ${_time(_pendingStart)}'),
          Slider(
            value: _pendingStart.toDouble(),
            min: 0,
            max: reference.durationMs.toDouble(),
            onChanged: (value) => setState(
              () => _pendingStart = value.round().clamp(0, _pendingEnd - 1),
            ),
          ),
          Text('End: ${_time(_pendingEnd)}'),
          Slider(
            value: _pendingEnd.toDouble(),
            min: 0,
            max: reference.durationMs.toDouble(),
            onChanged: (value) => setState(
              () => _pendingEnd = value.round().clamp(
                _pendingStart + 1,
                reference.durationMs,
              ),
            ),
          ),
          Text('Selected duration: ${_time(_pendingEnd - _pendingStart)}'),
          Row(
            children: [
              Button(
                onPressed: _busy
                    ? null
                    : () => _applyTrim(reference, 0, reference.durationMs),
                child: const Text('Reset trim'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _applyTrim(reference, _pendingStart, _pendingEnd),
                child: const Text('Apply trim'),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _referencesStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Record references',
        style: FluentTheme.of(context).typography.subtitle,
      ),
      const SizedBox(height: 6),
      const Text('2 required  ·  3 recommended  ·  Up to 5'),
      if (widget.existing != null && !_replacingReferences) ...[
        const SizedBox(height: AppSpacing.md),
        _surface(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your saved assessment is active. Earlier raw videos were not saved.',
              ),
              const SizedBox(height: 8),
              Button(
                onPressed: () {
                  setState(() {
                    _replacingReferences = true;
                    _template = null;
                  });
                  unawaited(_prepare());
                },
                child: const Text('Record new references'),
              ),
            ],
          ),
        ),
      ] else ...[
        const SizedBox(height: AppSpacing.md),
        CameraSourcePreference(
          settings: context.watch<SettingsService>(),
          cameras: context.watch<CameraDeviceService>(),
          compact: true,
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
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final camera = _camera();
            final guidance = _surface(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _initializing
                        ? 'Preparing camera…'
                        : _personCount == 1
                        ? 'One person ready'
                        : 'Keep one person in the camera.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keep your ${_prop.displayLabel.toLowerCase()} and upper body visible.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Perform the complete movement from start to finish.',
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<PreviewFrame?>(
                    valueListenable: _presentation,
                    builder: (context, preview, _) => Text(
                      'Prop: ${preview?.propPresentationState ?? 'missing'}  ·  Hands: ${preview?.handsPresentationState ?? 'missing'}  ·  Body: ${preview?.posePresentationState ?? 'missing'}',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const ValueKey('custom-reference-record'),
                    onPressed: _recording
                        ? (_busy ? null : _finishReference)
                        : (_canRecord ? _record : null),
                    child: Text(
                      _recording ? 'Finish Reference' : 'Record Reference',
                    ),
                  ),
                ],
              ),
            );
            if (constraints.maxWidth < 800) {
              return Column(
                children: [camera, const SizedBox(height: 12), guidance],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: camera),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: guidance),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < _references.length; index++) ...[
          _referenceCard(_references[index], index),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_references.length == 2)
          const InfoBar(
            title: Text('Ready to build'),
            content: Text(
              'A third reference is recommended for better consistency.',
            ),
            severity: InfoBarSeverity.info,
          ),
        if (_references.length >= 5)
          const Text('You have reached the 5 reference limit.'),
      ],
    ],
  );

  Widget _reviewStep() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review and save',
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_name.text.trim()),
        Text('$_difficulty  ·  ${_prop.displayLabel}'),
        const SizedBox(height: AppSpacing.md),
        Text(
          _replacingReferences
              ? '${_references.length} recorded references will form this assessment.'
              : 'The existing assessment template remains active. No historical reference videos are available.',
        ),
        if (_references.length == 2)
          const InfoBar(
            title: Text('Optional improvement'),
            content: Text(
              'You can save now. A third reference is recommended.',
            ),
            severity: InfoBarSeverity.info,
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _template?.requiresRotation == true
              ? 'Assessment can track prop path, visible body and hands, and visible bottle rotation.'
              : 'Assessment can track prop path and the body and hands visible in your references.',
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ElixScaffoldPage(
    header: PageHeader(
      leading: Button(
        onPressed: _busy ? null : _exit,
        child: const Text('Back'),
      ),
      title: Text(
        widget.existing == null ? 'Create Movement' : 'Edit Movement',
      ),
    ),
    content: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < 3; index++)
                    Text(
                      '${index + 1}. ${const ['Movement details', 'Record references', 'Review and save'][index]}',
                      style: TextStyle(
                        fontWeight: index == _step
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_step == 0) _details(),
              if (_step == 1) _referencesStep(),
              if (_step == 2) _reviewStep(),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                InfoBar(
                  title: const Text('Please check this step'),
                  content: Text(_error!),
                  severity: InfoBarSeverity.error,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (_step > 0)
                    Button(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _step--;
                              _error = null;
                            }),
                      child: const Text('Previous'),
                    ),
                  const Spacer(),
                  if (_step == 0)
                    FilledButton(
                      key: const ValueKey('custom-movement-next'),
                      onPressed: _resettingProp ? null : _nextDetails,
                      child: const Text('Next: References'),
                    ),
                  if (_step == 1)
                    FilledButton(
                      key: const ValueKey('custom-movement-review'),
                      onPressed:
                          _busy ||
                              _recording ||
                              (_replacingReferences && _references.length < 2)
                          ? null
                          : _review,
                      child: const Text('Review movement'),
                    ),
                  if (_step == 2)
                    FilledButton(
                      key: const ValueKey('custom-movement-save'),
                      onPressed: _busy || !_hasUsableTemplate ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save Movement'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
