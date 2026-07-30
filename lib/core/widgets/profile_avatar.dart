import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';

/// Shared circular avatar used by the sidebar, profile menu, and profile
/// settings screen.
///
/// Resolves the image to show using this priority:
/// 1. [localPreviewPath] — a just-picked file not yet uploaded, when it
///    still exists on disk (profile settings screen only).
/// 2. [networkImageUrl] — the saved Firebase Cloud Storage avatar, which
///    works across Windows machines.
/// 3. [legacyLocalPath] — a pre-Cloud-Storage local file path, only usable
///    on the PC where it was picked.
/// 4. `assets/default_profile.png`.
/// 5. [initials] rendered over a tinted circle, if the asset itself fails
///    to load.
///
/// Performs no Firebase or repository calls; all resolution here is either
/// a synchronous local file-existence check or delegated to [Image.network]
/// / [Image.asset] loading and error callbacks.
class ProfileAvatarWidget extends StatelessWidget {
  const ProfileAvatarWidget({
    super.key,
    this.localPreviewPath,
    this.networkImageUrl,
    this.legacyLocalPath,
    required this.initials,
    this.radius = 20,
  });

  final String? localPreviewPath;
  final String? networkImageUrl;
  final String? legacyLocalPath;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: _resolveContent()),
    );
  }

  Widget _resolveContent() {
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
          return const Center(child: ProgressRing(strokeWidth: 2));
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
    return _defaultAssetOrInitials();
  }

  Widget _fileImage(File file) {
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _defaultAssetOrInitials(),
    );
  }

  Widget _defaultAssetOrInitials() {
    return Image.asset(
      'assets/default_profile.png',
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
