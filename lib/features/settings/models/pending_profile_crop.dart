import 'dart:typed_data';

/// In-memory cropped profile image ready for immediate upload.
///
/// Always produced as a 512×512 PNG so [AccountProfileSection] can pass
/// [bytes] and [contentType] straight to [AuthService.updateProfilePicture]
/// without further conversion.
class PendingProfileCrop {
  const PendingProfileCrop({
    required this.bytes,
    this.contentType = 'image/png',
  });

  final Uint8List bytes;
  final String contentType;
}
