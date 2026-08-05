import 'dart:typed_data';

/// In-memory cropped profile image staged for Save changes.
///
/// Always produced as a 512×512 PNG so the upload pipeline can pass
/// [bytes] and [contentType] straight to [AuthService.updateProfileDetails]
/// without further conversion.
class PendingProfileCrop {
  const PendingProfileCrop({
    required this.bytes,
    this.contentType = 'image/png',
  });

  final Uint8List bytes;
  final String contentType;
}
