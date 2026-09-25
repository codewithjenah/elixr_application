import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../data/models/training_prop.dart';
import 'movement_image.dart';

/// Loads an owner-private reference still saved with a custom movement.
class CustomMovementReferenceImage extends StatefulWidget {
  const CustomMovementReferenceImage({
    super.key,
    required this.movementName,
    required this.prop,
    required this.size,
    this.storagePath,
  });

  final String movementName;
  final TrainingProp prop;
  final double size;
  final String? storagePath;

  @override
  State<CustomMovementReferenceImage> createState() =>
      _CustomMovementReferenceImageState();
}

class _CustomMovementReferenceImageState
    extends State<CustomMovementReferenceImage> {
  Future<Uint8List?>? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomMovementReferenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) _load();
  }

  void _load() {
    final path = widget.storagePath;
    _image = path == null
        ? null
        : FirebaseStorage.instance
              .ref(path)
              .getData(512 * 1024)
              .then<Uint8List?>((bytes) => bytes)
              .catchError((Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return MovementImage(
        movementName: widget.movementName,
        prop: widget.prop,
        size: widget.size,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: image,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return MovementImage(
            movementName: widget.movementName,
            prop: widget.prop,
            size: widget.size,
          );
        }
        final pixels =
            (widget.size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1))
                .round();
        return Semantics(
          image: true,
          label: 'Reference image: ${widget.movementName}',
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size * 0.16),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: pixels > 0 ? pixels : null,
                cacheHeight: pixels > 0 ? pixels : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
