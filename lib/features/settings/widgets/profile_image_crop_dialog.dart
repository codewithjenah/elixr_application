import 'dart:ui' as ui;

import 'package:crop/crop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../models/pending_profile_crop.dart';

/// Fixed output size for staged profile crops (square PNG).
const int kProfileCropOutputSize = 512;

const double _kMinScale = 1.0;
const double _kMaxScale = 5.0;

/// Optional override used by widget tests to simulate slow or failing crops.
@visibleForTesting
typedef ProfileCropApplyHook =
    Future<PendingProfileCrop?> Function(CropController controller);

/// Interactive 1:1 profile-image crop dialog (Elixr-styled).
///
/// The circular guide is UI-only ([Crop.helper]); the returned image remains
/// a square 512×512 PNG suitable for circular avatar display.
class ProfileImageCropDialog extends StatefulWidget {
  const ProfileImageCropDialog({
    super.key,
    required this.sourceBytes,
    this.applyHook,
  });

  final Uint8List sourceBytes;

  /// When non-null, replaces the real crop+encode path (tests only).
  final ProfileCropApplyHook? applyHook;

  static Future<PendingProfileCrop?> show(
    BuildContext context, {
    required Uint8List sourceBytes,
    ProfileCropApplyHook? applyHook,
  }) {
    return showDialog<PendingProfileCrop>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => ProfileImageCropDialog(
        sourceBytes: sourceBytes,
        applyHook: applyHook,
      ),
    );
  }

  @override
  State<ProfileImageCropDialog> createState() => _ProfileImageCropDialogState();
}

class _ProfileImageCropDialogState extends State<ProfileImageCropDialog> {
  late final CropController _controller;
  bool _applying = false;
  double _scale = _kMinScale;

  @override
  void initState() {
    super.initState();
    _controller = CropController(aspectRatio: 1);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final next = _controller.scale.clamp(_kMinScale, _kMaxScale);
    if ((next - _scale).abs() < 0.001) return;
    if (!mounted) return;
    setState(() => _scale = next);
  }

  void _setScale(double value) {
    final clamped = value.clamp(_kMinScale, _kMaxScale);
    _controller.scale = clamped;
    setState(() => _scale = clamped);
  }

  void _reset() {
    _controller.rotation = 0;
    _controller.offset = Offset.zero;
    _controller.scale = _kMinScale;
    setState(() => _scale = _kMinScale);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_applying) return;
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    // Scroll up (negative dy) zooms in.
    final step = delta < 0 ? 0.12 : -0.12;
    _setScale(_scale + step);
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final PendingProfileCrop? result;
      final hook = widget.applyHook;
      if (hook != null) {
        result = await hook(_controller);
      } else {
        result = await _cropAndNormalize(_controller);
      }
      if (!mounted) return;
      if (result == null) {
        setState(() => _applying = false);
        await ElixDialog.error(
          context,
          'Could not crop the image. Try again with a different photo.',
        );
        return;
      }
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void _cancel() {
    if (_applying) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewSize = MediaQuery.sizeOf(context);
    final maxDialogHeight = viewSize.height * 0.85;

    return PopScope(
      canPop: !_applying,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _cancel();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Center(
              child: ElixDialog(
                title: 'Adjust profile photo',
                subtitle:
                    'Drag to reposition. Scroll or use the slider to zoom.',
                icon: FluentIcons.crop,
                maxWidth: 540,
                maxHeight: maxDialogHeight,
                scrollableContent: true,
                content: _buildContent(context),
                actions: [
                  // Single child so ElixDialog stretches full width; Wrap
                  // prevents narrow-window Row overflow.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Button(
                        onPressed: _applying ? null : _reset,
                        child: const Text('Reset'),
                      ),
                      Button(
                        onPressed: _applying ? null : _cancel,
                        child: const Text('Cancel'),
                      ),
                      ElixPrimaryButton(
                        label: 'Apply crop',
                        expanded: false,
                        isLoading: _applying,
                        onPressed: _applying ? null : _apply,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final viewWidth = MediaQuery.sizeOf(context).width;
    // Leave room for dialog margin + padding on compact windows.
    final side = (viewWidth - 96).clamp(180.0, 300.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: Crop(
                controller: _controller,
                shape: BoxShape.rectangle,
                backgroundColor: Colors.black,
                dimColor: const Color.fromRGBO(0, 0, 0, 0.55),
                padding: EdgeInsets.zero,
                helper: const IgnorePointer(
                  child: CustomPaint(painter: _CircularGuidePainter()),
                ),
                child: Image.memory(
                  widget.sourceBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Zoom',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            IconButton(
              icon: const Icon(FluentIcons.remove, size: 14),
              onPressed: _applying ? null : () => _setScale(_scale - 0.15),
            ),
            Expanded(
              child: Slider(
                value: _scale,
                min: _kMinScale,
                max: _kMaxScale,
                onChanged: _applying ? null : _setScale,
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.add, size: 14),
              onPressed: _applying ? null : () => _setScale(_scale + 0.15),
            ),
          ],
        ),
      ],
    );
  }
}

class _CircularGuidePainter extends CustomPainter {
  const _CircularGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.shortestSide / 2;
    final center = rect.center;

    final overlay = Path()
      ..addRect(rect)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlay,
      Paint()..color = const Color.fromRGBO(0, 0, 0, 0.35),
    );
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.textPrimary.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Crops via [CropController.crop], then resizes to [kProfileCropOutputSize]
/// square PNG bytes. Safe well under the 5 MB repository limit.
Future<PendingProfileCrop?> _cropAndNormalize(CropController controller) async {
  final viewport = 320.0;
  final pixelRatio = kProfileCropOutputSize / viewport;
  final raw = await controller.crop(pixelRatio: pixelRatio);
  if (raw == null) return null;

  try {
    final bytes = await _resizeToSquarePng(raw, kProfileCropOutputSize);
    if (bytes == null || bytes.isEmpty) return null;
    return PendingProfileCrop(bytes: bytes);
  } finally {
    raw.dispose();
  }
}

Future<Uint8List?> _resizeToSquarePng(ui.Image source, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dest = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  final src = Rect.fromLTWH(
    0,
    0,
    source.width.toDouble(),
    source.height.toDouble(),
  );
  canvas.drawImageRect(
    source,
    src,
    dest,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final resized = await picture.toImage(size, size);
  try {
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } finally {
    resized.dispose();
  }
}
