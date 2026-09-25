import 'dart:async';
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
    required this.quality,
  });

  final String id;
  final String path;
  final int durationMs;
  final _ReferenceQuality? quality;
  int startMs = 0;
  late int endMs = durationMs;
}

/// The backend reports observed-frame coverage. It is feedback for the next
/// recording, not a replacement for template inference (which also checks gaps).
class _ReferenceQuality {
  const _ReferenceQuality({
    required this.leftHandCoverage,
    required this.rightHandCoverage,
    required this.poseCoverage,
  });

  final double? leftHandCoverage;
  final double? rightHandCoverage;
  final double? poseCoverage;

  // Matches template_engine.MIN_COVERAGE. Final template inference also checks
  // tracking gaps, so this only prompts a better next recording.
  static const minimumCoverageHint = 0.70;

  double? get bestHandCoverage {
    final values = [
      leftHandCoverage,
      rightHandCoverage,
    ].whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
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
  bool _propVisible = false;
  bool _handsVisible = false;
  bool _upperBodyVisible = false;
  DateTime? _captureObservedAt;
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

  bool get _hasUsableTemplate => _template?.isReady == true;
  bool get _canRecord =>
      _sessionStarted &&
      _previewReady &&
      !_initializing &&
      !_busy &&
      !_cameraBusy &&
      !_recording &&
      _references.length < 5 &&
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
      await _playback.release();
      if (!mounted) return;
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
        _recording = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
          _error =
              'This example was not usable. Keep more of the full movement in view and retry.';
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
        setState(() => _error = 'Could not delete this example. Try again.');
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
        () => _error = 'Record the movement at least twice before reviewing.',
      );
      return;
    }
    if (_replacingReferences) {
      setState(() => _busy = true);
      try {
        final ack = await _socket.sendBuildCustomTemplate();
        if (!ack.accepted && ack.errorCode == 'insufficient_hand_coverage') {
          throw StateError(
            'Hands were visible but tracking was too intermittent to learn the hand movement. Re-record examples with at least one hand clearly visible throughout.',
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
            metadataError ??
            'Record at least two usable examples before saving.',
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

  Widget _surface(Widget child, {bool tinted = false}) => Container(
    padding: const EdgeInsets.all(AppSpacing.mdPlus),
    decoration: BoxDecoration(
      color: tinted
          ? context.elixColors.surfaceTinted
          : context.elixColors.surfaceRaised,
      borderRadius: BorderRadius.circular(ElixRadius.panel),
      border: Border.all(color: context.elixColors.borderSubtle),
    ),
    child: child,
  );

  Widget _field(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: ElixTypography.label(color: context.elixTextPrimary)),
      const SizedBox(height: AppSpacing.sm),
      control,
    ],
  );

  Widget _details() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 900),
    child: _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set up your movement',
            style: ElixTypography.sectionTitle(
              context,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Give it a name, choose your prop, and tell ELIXR what kind of movement you are teaching.',
            style: ElixTypography.supporting(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
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
            'Short description',
            TextBox(
              key: const ValueKey('custom-movement-description'),
              controller: _description,
              minLines: 2,
              maxLines: 3,
              maxLength: CustomMovement.descriptionMaxLength,
              placeholder: 'Describe the movement from start to finish',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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
                            if (value != TrainingProp.bottle) {
                              _trackRotation = false;
                            }
                          });
                        },
                ),
              );
              if (constraints.maxWidth < 560) {
                return Column(
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            _references.isEmpty
                ? 'Use the same prop for every example.'
                : 'Delete recorded examples before changing the prop.',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
          if (_prop == TrainingProp.bottle) ...[
            const SizedBox(height: AppSpacing.lg),
            _surface(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Does the bottle visibly rotate?',
                          style: ElixTypography.label(
                            color: context.elixTextPrimary,
                          ),
                        ),
                      ),
                      ToggleSwitch(
                        key: const ValueKey('custom-movement-require-rotation'),
                        checked: _trackRotation,
                        onChanged: (value) => setState(() {
                          _trackRotation = value;
                          if (_references.isEmpty &&
                              widget.existingRevision != null &&
                              _prop == widget.existing?.propType) {
                            _template = widget.existingRevision!.template;
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _trackRotation
                        ? 'Optional quality bonus: orange tape near the top and yellow tape near the base can help ELIXR observe the turn. The movement can still be saved and scored without it.'
                        : 'Rotation is optional. Body, hands, timing, and prop path determine the movement score.',
                    style: ElixTypography.supporting(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
              tinted: true,
            ),
          ],
        ],
      ),
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

  Widget _checkRow(String label, bool present, String missing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Icon(
          present ? FluentIcons.check_mark : FluentIcons.info,
          size: 14,
          color: present
              ? context.elixColors.success
              : context.elixColors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: ElixTypography.label(color: context.elixTextPrimary),
          ),
        ),
        Flexible(
          child: Text(
            present ? 'In view' : missing,
            textAlign: TextAlign.end,
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
        ),
      ],
    ),
  );

  Widget _cameraCheck() => ValueListenableBuilder<PreviewFrame?>(
    valueListenable: _presentation,
    builder: (context, preview, _) {
      final prop = _propVisible;
      final hands = _handsVisible;
      final body = _upperBodyVisible;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Camera check',
            style: ElixTypography.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _checkRow(
            'One person',
            _personCount == 1,
            'Keep one person in frame',
          ),
          _checkRow(
            'Selected prop',
            prop,
            'Show your ${_prop.displayLabel.toLowerCase()}',
          ),
          _checkRow('Hands', hands, 'Keep at least one hand visible to record'),
          _checkRow(
            'Upper body',
            body,
            'Keep shoulders and one arm visible to record',
          ),
          if (!hands) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Keep your hands fully visible so ELIXR can learn more movement detail.',
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
          ],
        ],
      );
    },
  );

  Widget _captureWorkspace() => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Live camera',
                style: ElixTypography.sectionTitle(
                  context,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            if (_recording)
              Text(
                '● Recording',
                style: ElixTypography.label(color: context.elixColors.error),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Show the full movement from start to finish.',
          style: ElixTypography.supporting(color: context.elixTextSecondary),
        ),
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
        _camera(),
        const SizedBox(height: AppSpacing.md),
        _cameraCheck(),
        const SizedBox(height: AppSpacing.md),
        ElixPrimaryButton(
          key: const ValueKey('custom-reference-record'),
          label: _recording
              ? 'Finish example'
              : _references.isEmpty
              ? 'Record example'
              : 'Record another example',
          onPressed: _recording
              ? (_busy ? null : _finishReference)
              : (_canRecord ? _record : null),
        ),
        if (_initializing) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Preparing camera…',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
        ],
      ],
    ),
  );

  String _coverageLabel(double? value) =>
      value == null ? 'Not reported' : '${(value * 100).round()}% of frames';

  Widget _exampleCard(_ReferenceDraft reference, int index) {
    final selected = _previewId == reference.id;
    final quality = reference.quality;
    final handCoverage = quality?.bestHandCoverage;
    return Container(
      key: ValueKey('example-card-${reference.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: selected
            ? context.elixColors.surfaceSelected
            : context.elixColors.surfaceInteractive,
        borderRadius: BorderRadius.circular(ElixRadius.card),
        border: Border.all(
          color: selected
              ? context.elixColors.borderInteractive
              : context.elixColors.borderSubtle,
          width: selected && context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Example ${index + 1}',
                  style: ElixTypography.cardTitle(
                    color: context.elixTextPrimary,
                  ),
                ),
              ),
              Text(
                '✓ Accepted',
                style: ElixTypography.caption(
                  color: context.elixColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_time(reference.endMs - reference.startMs)}${reference.startMs > 0 || reference.endMs < reference.durationMs ? ' · Trimmed' : ''}',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
          if (handCoverage != null &&
              handCoverage < _ReferenceQuality.minimumCoverageHint) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Hands were difficult to see',
              style: ElixTypography.caption(color: context.elixColors.warning),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Button(
                key: ValueKey('example-select-${reference.id}'),
                onPressed: _busy ? null : () => _selectPreview(reference),
                child: Text(selected ? 'Selected' : 'Preview / edit'),
              ),
              Button(
                onPressed: _busy ? null : () => _delete(reference),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualityDetails(_ReferenceDraft reference) {
    final quality = reference.quality;
    if (quality == null) return const SizedBox.shrink();
    final bestHand = quality.bestHandCoverage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          'What the camera saw',
          style: ElixTypography.label(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Left hand: ${_coverageLabel(quality.leftHandCoverage)} · Right hand: ${_coverageLabel(quality.rightHandCoverage)}',
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
        Text(
          'Upper body: ${_coverageLabel(quality.poseCoverage)}',
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
        if (bestHand != null &&
            bestHand < _ReferenceQuality.minimumCoverageHint) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Try keeping your hands fully in frame on your next example.',
            style: ElixTypography.caption(color: context.elixColors.warning),
          ),
        ],
      ],
    );
  }

  Widget _exampleEditor(_ReferenceDraft reference, int index) => _surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Example ${index + 1}',
                style: ElixTypography.sectionTitle(
                  context,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            Text(
              '✓ Accepted',
              style: ElixTypography.caption(color: context.elixColors.success),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: constraints.maxWidth < 430
                ? 240
                : constraints.maxWidth * 9 / 16,
            child: ElixrVideoPlayer(
              key: ValueKey('reference-player-${reference.id}'),
              source: Uri.file(reference.path),
              session: _playback,
              clipStart: Duration(milliseconds: _pendingStart),
              clipEnd: Duration(milliseconds: _pendingEnd),
            ),
          ),
        ),
        _qualityDetails(reference),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Trim example',
          style: ElixTypography.cardTitle(color: context.elixTextPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Choose the part that shows the full movement. Your original recording stays intact.',
          style: ElixTypography.caption(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.smPlus),
          decoration: BoxDecoration(
            color: context.elixColors.surfaceTinted,
            borderRadius: BorderRadius.circular(ElixRadius.card),
            border: Border.all(color: context.elixColors.borderSubtle),
          ),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Text('Start  ${_time(_pendingStart)}'),
                  Text('End  ${_time(_pendingEnd)}'),
                ],
              ),
              Slider(
                value: _pendingStart.toDouble(),
                min: 0,
                max: reference.durationMs.toDouble(),
                onChanged: (value) => setState(
                  () => _pendingStart = value.round().clamp(0, _pendingEnd - 1),
                ),
              ),
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
              Text(
                'Selected  ${_time(_pendingEnd - _pendingStart)}',
                style: ElixTypography.label(color: context.elixTextPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Button(
              onPressed: _busy
                  ? null
                  : () => _applyTrim(reference, 0, reference.durationMs),
              child: const Text('Reset trim'),
            ),
            ElixPrimaryButton(
              label: 'Apply changes',
              expanded: false,
              onPressed: _busy
                  ? null
                  : () => _applyTrim(reference, _pendingStart, _pendingEnd),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _examplesWorkspace() {
    final selectedIndex = _references.indexWhere(
      (item) => item.id == _previewId,
    );
    return _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your examples',
                  style: ElixTypography.sectionTitle(
                    context,
                    color: context.elixTextPrimary,
                  ),
                ),
              ),
              Text(
                '${_references.length} of 5',
                style: ElixTypography.label(color: context.elixTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _references.length < 2
                ? 'Record the movement at least twice.'
                : _references.length == 2
                ? "You're ready to continue. A third example helps ELIXR learn the pattern more consistently."
                : 'Recommended amount reached. You can review whenever you are ready.',
            style: ElixTypography.supporting(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 480) {
                return Column(
                  children: [
                    for (var index = 0; index < _references.length; index++)
                      _exampleCard(_references[index], index),
                  ],
                );
              }
              final cardWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (var index = 0; index < _references.length; index++)
                    SizedBox(
                      width: cardWidth,
                      child: _exampleCard(_references[index], index),
                    ),
                ],
              );
            },
          ),
          if (_references.isEmpty)
            Text(
              'Your recordings will appear here. Select one to preview or trim it.',
              style: ElixTypography.supporting(
                color: context.elixTextSecondary,
              ),
            ),
          if (selectedIndex >= 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _exampleEditor(_references[selectedIndex], selectedIndex),
          ],
          if (_references.length >= 5)
            Text(
              'You have reached the 5 example limit.',
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
        ],
      ),
    );
  }

  Widget _studioStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Show ELIXR the movement',
        style: ElixTypography.pageTitle(
          context,
          color: context.elixTextPrimary,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Perform the full movement from start to finish. Record it at least twice so ELIXR can learn the pattern.',
        style: ElixTypography.supporting(color: context.elixTextSecondary),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (widget.existing != null && !_replacingReferences)
        _surface(
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
                style: ElixTypography.supporting(
                  color: context.elixTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ElixPrimaryButton(
                label: 'Record new examples',
                expanded: false,
                onPressed: () {
                  setState(() {
                    _replacingReferences = true;
                    _template = null;
                  });
                  unawaited(_prepare());
                },
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  _captureWorkspace(),
                  const SizedBox(height: AppSpacing.md),
                  _examplesWorkspace(),
                ],
              );
            }
            final mainWidth = (constraints.maxWidth - AppSpacing.md) * 0.58;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: mainWidth, child: _captureWorkspace()),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _examplesWorkspace()),
              ],
            );
          },
        ),
    ],
  );

  Widget _capability(String label) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      children: [
        Icon(
          FluentIcons.check_mark,
          size: 14,
          color: context.elixColors.success,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: ElixTypography.supporting(color: context.elixTextPrimary),
        ),
      ],
    ),
  );

  Widget _reviewStep() {
    final capabilities =
        _template?.featureCapabilities ?? const <String, bool>{};
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: _surface(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review and save',
              style: ElixTypography.pageTitle(
                context,
                color: context.elixTextPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Check what ELIXR learned before saving.',
              style: ElixTypography.supporting(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Movement',
              style: ElixTypography.label(color: context.elixTextSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _name.text.trim(),
              style: ElixTypography.sectionTitle(
                context,
                color: context.elixTextPrimary,
              ),
            ),
            Text(
              '$_difficulty · ${_prop.displayLabel}',
              style: ElixTypography.supporting(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Examples',
              style: ElixTypography.label(color: context.elixTextSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _replacingReferences
                  ? '${_references.length} recorded'
                  : 'Saved version',
              style: ElixTypography.cardTitle(color: context.elixTextPrimary),
            ),
            if (_replacingReferences && _references.length == 2)
              Text(
                'You can save now. A third example may improve consistency.',
                style: ElixTypography.supporting(
                  color: context.elixTextSecondary,
                ),
              ),
            if (!_replacingReferences)
              Text(
                'Earlier recordings are not available, but this version remains active.',
                style: ElixTypography.supporting(
                  color: context.elixTextSecondary,
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            _surface(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What ELIXR learned',
                    style: ElixTypography.cardTitle(
                      color: context.elixTextPrimary,
                    ),
                  ),
                  if (capabilities['prop_translation'] == true)
                    _capability('${_prop.displayLabel} movement'),
                  if (capabilities['hands'] == true) _capability('Hands'),
                  if (capabilities['pose'] == true) _capability('Upper body'),
                  if (capabilities['prop_rotation'] == true)
                    _capability('Visible bottle rotation bonus'),
                ],
              ),
              tinted: true,
            ),
            if (_trackRotation && capabilities['prop_rotation'] != true) ...[
              const SizedBox(height: AppSpacing.md),
              const InfoBar(
                title: Text('Rotation could not be learned'),
                content: Text(
                  'You can save this movement. Rotation will not affect its score; record clearer marked examples later if you want the optional bonus.',
                ),
                severity: InfoBarSeverity.info,
              ),
            ],
            if (capabilities['hands'] != true ||
                capabilities['pose'] != true) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBar(
                title: Text(
                  capabilities['hands'] != true && capabilities['pose'] != true
                      ? 'Only prop movement was learned'
                      : capabilities['hands'] != true
                      ? 'Hands were not learned'
                      : 'Upper body was not learned',
                ),
                content: Text(
                  capabilities['hands'] != true && capabilities['pose'] != true
                      ? 'Hands and upper body were not tracked consistently enough to be part of this assessment. You can save now, or record better examples with your hands and upper body in frame.'
                      : capabilities['hands'] != true
                      ? 'Hands were not tracked consistently enough to be part of this assessment. You can save now, or record better examples with your hands fully in frame.'
                      : 'Upper body movement was not tracked consistently enough to be part of this assessment. You can save now, or record better examples with your upper body in frame.',
                ),
                severity: InfoBarSeverity.warning,
              ),
              if (_replacingReferences) ...[
                const SizedBox(height: AppSpacing.sm),
                Button(
                  onPressed: _busy ? null : () => setState(() => _step = 1),
                  child: const Text('Go back and record better examples'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _progress() => LayoutBuilder(
    builder: (context, constraints) {
      Widget step(int index) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: index == _step
              ? context.elixColors.surfaceSelected
              : Colors.transparent,
          borderRadius: BorderRadius.circular(ElixRadius.pill),
          border: Border.all(
            color: index == _step
                ? context.elixColors.borderInteractive
                : context.elixColors.borderSubtle,
          ),
        ),
        child: Text(
          '${index < _step ? '✓' : '${index + 1}'}  ${const ['Set up', 'Show movement', 'Review'][index]}',
          style: ElixTypography.label(
            color: index > _step
                ? context.elixTextSecondary
                : context.elixTextPrimary,
          ),
        ),
      );
      if (constraints.maxWidth < 480) {
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (var index = 0; index < 3; index++) step(index)],
        );
      }
      return Row(
        children: [
          for (var index = 0; index < 3; index++) ...[
            if (index > 0)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  color: context.elixColors.borderSubtle,
                ),
              ),
            step(index),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => ElixScaffoldPage(
    header: ElixEditorialPageHeader(
      leading: ElixBackButton(onPressed: _busy ? null : _exit),
      eyebrow: 'CUSTOM MOVEMENT',
      heading: widget.existing == null ? 'Create movement' : 'Edit movement',
      subtitle: 'Teach ELIXR a movement using your own demonstrations.',
      variant: ElixEditorialHeaderVariant.compact,
    ),
    content: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _progress(),
              const SizedBox(height: AppSpacing.lg),
              if (_step == 0) _details(),
              if (_step == 1) _studioStep(),
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
                    ElixPrimaryButton(
                      label: 'Previous',
                      expanded: false,
                      variant: ElixButtonVariant.outline,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _step--;
                              _error = null;
                            }),
                    ),
                  const Spacer(),
                  if (_step == 0)
                    ElixPrimaryButton(
                      key: const ValueKey('custom-movement-next'),
                      onPressed: _resettingProp ? null : _nextDetails,
                      label: 'Next: Show movement',
                      expanded: false,
                    ),
                  if (_step == 1)
                    ElixPrimaryButton(
                      key: const ValueKey('custom-movement-review'),
                      onPressed:
                          _busy ||
                              _recording ||
                              (_replacingReferences && _references.length < 2)
                          ? null
                          : _review,
                      label: 'Review movement',
                      expanded: false,
                    ),
                  if (_step == 2)
                    ElixPrimaryButton(
                      key: const ValueKey('custom-movement-save'),
                      onPressed: _busy || !_hasUsableTemplate ? null : _save,
                      label: _busy ? 'Saving…' : 'Save movement',
                      expanded: false,
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
