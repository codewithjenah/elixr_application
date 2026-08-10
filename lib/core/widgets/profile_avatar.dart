import 'dart:io';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import 'profile_border_frame.dart';

/// Shared circular avatar used by the sidebar, profile menu, and profile
/// settings screen.
///
/// Resolves the image to show using this priority:
/// 1. [memoryPreviewBytes] — an in-memory cropped preview not yet uploaded
///    (profile settings crop flow).
/// 2. [localPreviewPath] — a just-picked file not yet uploaded, when it
///    still exists on disk (legacy / compatibility).
/// 3. [networkImageUrl] — the saved Firebase Cloud Storage avatar, which
///    works across Windows machines.
/// 4. [legacyLocalPath] — a pre-Cloud-Storage local file path, only usable
///    on the PC where it was picked.
/// 5. [initials] rendered over a tinted circle.
///
/// Performs no Firebase or repository calls; all resolution here is either
/// a synchronous local file-existence check or delegated to [Image.memory] /
/// [Image.network] loading and error callbacks.
class ProfileAvatarWidget extends StatelessWidget {
  const ProfileAvatarWidget({
    super.key,
    this.memoryPreviewBytes,
    this.localPreviewPath,
    this.networkImageUrl,
    this.legacyLocalPath,
    required this.initials,
    this.radius = 20,
    this.equippedBorderId,
    this.showBorder = true,
    this.animateBorder = false,
  });

  /// In-memory cropped (or otherwise staged) avatar bytes. Takes priority
  /// over path and network sources so Settings can preview a crop before
  /// Save changes uploads it.
  final Uint8List? memoryPreviewBytes;
  final String? localPreviewPath;
  final String? networkImageUrl;
  final String? legacyLocalPath;
  final String initials;
  final double radius;

  /// Public equipped cosmetic border id (from leaderboard). Null/unknown
  /// falls back to the neutral presentation.
  final String? equippedBorderId;
  final bool showBorder;

  /// When true, animates the equipped cosmetic frame (Settings preview,
  /// large profile headers). Defaults to false for dense lists.
  final bool animateBorder;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    return ProfileBorderFrame(
      size: size,
      equippedBorderId: equippedBorderId,
      showBorder: showBorder,
      animate: animateBorder,
      child: ClipOval(child: _resolveContent()),
    );
  }

  Widget _resolveContent() {
    final memory = memoryPreviewBytes;
    if (memory != null && memory.isNotEmpty) {
      return Image.memory(
        memory,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _pathOrNetwork(),
      );
    }

    return _pathOrNetwork();
  }

  Widget _pathOrNetwork() {
    final previewFile = _existingFileOrNull(localPreviewPath);
    if (previewFile != null) {
      return _fileImage(previewFile);
    }

    if (networkImageUrl != null && networkImageUrl!.isNotEmpty) {
      return Image.network(
        networkImageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Stack(
            alignment: Alignment.center,
            children: [
              _initialsFallback(),
              const ProgressRing(strokeWidth: 2),
            ],
          );
        },
        errorBuilder: (context, error, stackTrace) => _legacyOrFallback(),
      );
    }

    return _legacyOrFallback();
  }

  Widget _legacyOrFallback() {
    final legacyFile = _existingFileOrNull(legacyLocalPath);
    if (legacyFile != null) {
      return _fileImage(legacyFile);
    }
    return _initialsFallback();
  }

  Widget _fileImage(File file) {
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _initialsFallback(),
    );
  }

  Widget _initialsFallback() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: radius * 0.65,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static File? _existingFileOrNull(String? path) {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }
}
