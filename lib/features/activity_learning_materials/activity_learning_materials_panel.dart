import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elixr_video_player.dart';
import '../../data/models/activity_learning_material.dart';
import '../../data/repositories/activity_learning_material_repository.dart';

/// Mirrors the server's current limits for early, friendly feedback only.
/// Functions still validates bytes and content before publishing a material.
abstract final class ActivityLearningMaterialLimits {
  static const pdfBytes = 20 * 1024 * 1024;
  static const imageBytes = 10 * 1024 * 1024;
  static const videoBytes = 100 * 1024 * 1024;
}

String activityLearningMaterialSizeLabel(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData activityLearningMaterialIcon(ActivityLearningMaterialType type) =>
    switch (type) {
      ActivityLearningMaterialType.pdf => FluentIcons.pdf,
      ActivityLearningMaterialType.image => FluentIcons.photo2,
      ActivityLearningMaterialType.video => FluentIcons.video,
      ActivityLearningMaterialType.link => FluentIcons.link,
    };

String activityLearningMaterialTypeLabel(ActivityLearningMaterialType type) =>
    switch (type) {
      ActivityLearningMaterialType.pdf => 'PDF',
      ActivityLearningMaterialType.image => 'Image',
      ActivityLearningMaterialType.video => 'Video',
      ActivityLearningMaterialType.link => 'Link',
    };

/// A compact, assignment-scoped Teacher manager. It deliberately does not
/// update assignment documents: Functions remain the sole material authority.
class ActivityLearningMaterialsPanel extends StatefulWidget {
  const ActivityLearningMaterialsPanel({
    super.key,
    required this.assignmentId,
    required this.repository,
  });

  final String assignmentId;
  final ActivityLearningMaterialRepository repository;

  @override
  State<ActivityLearningMaterialsPanel> createState() =>
      _ActivityLearningMaterialsPanelState();
}

class _ActivityLearningMaterialsPanelState
    extends State<ActivityLearningMaterialsPanel> {
  final List<_PendingUpload> _pending = [];
  List<ActivityLearningMaterial> _materials = const [];
  final Set<String> _removing = {};
  bool _loading = true;
  String? _loadError;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
    for (final item in _pending) {
      item.cancelled = true;
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final materials = await widget.repository.list(
        assignmentId: widget.assignmentId,
      );
      if (!_disposed) {
        setState(() {
          _materials = materials;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _loading = false;
          _loadError = 'Learning materials could not be loaded.';
        });
      }
    }
  }

  Future<void> _showAddMenu() async {
    final type = await showDialog<ActivityLearningMaterialType>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Add material'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choose a supporting file or a safe web link.'),
              const SizedBox(height: AppSpacing.sm),
              for (final type in ActivityLearningMaterialType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Button(
                    onPressed: () => Navigator.pop(context, type),
                    child: Row(
                      children: [
                        Icon(activityLearningMaterialIcon(type), size: 16),
                        const SizedBox(width: AppSpacing.sm),
                        Text(activityLearningMaterialTypeLabel(type)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;
    if (type == ActivityLearningMaterialType.link) {
      await _showAddLink();
    } else {
      await _pickFile(type);
    }
  }

  Future<void> _pickFile(ActivityLearningMaterialType type) async {
    final config = _fileConfig(type);
    final selected = await openFile(acceptedTypeGroups: [config.group]);
    if (selected == null || !mounted) return;
    final file = File(selected.path);
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size < 1) {
        throw const FormatException('Choose a non-empty file.');
      }
      if (!config.extensions.any(
        (extension) => selected.name.toLowerCase().endsWith('.$extension'),
      )) {
        throw const FormatException('Choose a supported file type.');
      }
      if (stat.size > config.maximumBytes) {
        throw FormatException(
          '${activityLearningMaterialTypeLabel(type)} files must be ${activityLearningMaterialSizeLabel(config.maximumBytes)} or smaller.',
        );
      }
      final item = _PendingUpload.file(
        type,
        file,
        selected.name,
        stat.size,
        type == ActivityLearningMaterialType.image &&
                selected.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : config.contentType,
      );
      setState(() => _pending.add(item));
      unawaited(_upload(item));
    } on FormatException catch (error) {
      _showError(error.message);
    } on FileSystemException {
      _showError('The selected file could not be read.');
    }
  }

  Future<void> _showAddLink() async {
    final name = TextEditingController();
    final url = TextEditingController();
    String? error;
    var adding = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => ContentDialog(
          title: const Text('Add link'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoLabel(
                  label: 'Display name',
                  child: TextBox(controller: name, maxLength: 120),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'URL',
                  child: TextBox(
                    controller: url,
                    placeholder: 'https://example.com',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      error!,
                      style: AppTheme.caption.copyWith(color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: adding
                  ? null
                  : () async {
                      final parsed = Uri.tryParse(url.text.trim());
                      if (name.text.trim().isEmpty ||
                          parsed == null ||
                          !parsed.hasAuthority ||
                          (parsed.scheme != 'http' &&
                              parsed.scheme != 'https') ||
                          parsed.userInfo.isNotEmpty) {
                        setDialogState(
                          () =>
                              error = 'Enter a name and an HTTP or HTTPS URL.',
                        );
                        return;
                      }
                      try {
                        setDialogState(() => adding = true);
                        final material = await widget.repository.addLink(
                          assignmentId: widget.assignmentId,
                          displayName: name.text.trim(),
                          url: parsed,
                        );
                        if (!dialogContext.mounted) return;
                        if (mounted) {
                          setState(
                            () => _materials = [..._materials, material],
                          );
                        }
                        Navigator.pop(dialogContext);
                      } catch (_) {
                        setDialogState(
                          () => error = 'The link could not be added.',
                        );
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => adding = false);
                        }
                      }
                    },
              child: Text(adding ? 'Adding...' : 'Add link'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    url.dispose();
  }

  Future<void> _upload(_PendingUpload item) async {
    try {
      final upload = await widget.repository.beginUpload(
        assignmentId: widget.assignmentId,
        type: item.type,
        displayName: item.displayName,
        declaredContentType: item.contentType!,
        sizeBytes: item.sizeBytes!,
      );
      item.uploadId = upload.uploadId;
      item.materialId = upload.materialId;
      if (item.cancelled || _disposed) {
        await _removeReservedMaterial(item);
        return;
      }
      await widget.repository.uploadStagedFile(
        upload: upload,
        file: item.file!,
      );
      if (item.cancelled || _disposed) return;
      item.status = _PendingStatus.processing;
      if (mounted) setState(() {});
      for (
        var attempt = 0;
        attempt < 20 && !item.cancelled && !_disposed;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (item.cancelled || _disposed) return;
        final status = await widget.repository.getUploadStatus(
          uploadId: upload.uploadId,
        );
        if (status.state == ActivityMaterialUploadState.ready &&
            status.material != null) {
          if (mounted) {
            setState(() {
              _pending.remove(item);
              _materials = [..._materials, status.material!];
            });
          }
          return;
        }
        if (status.state == ActivityMaterialUploadState.rejected) {
          item.status = _PendingStatus.failed;
          item.message = _rejectionMessage(status.rejectionReason);
          if (mounted) setState(() {});
          return;
        }
      }
      item.status = _PendingStatus.processing;
      item.message = 'Still processing. Check again shortly.';
      if (mounted) setState(() {});
    } catch (_) {
      item.status = _PendingStatus.failed;
      item.message = 'The upload could not be completed.';
      if (mounted && !item.cancelled) setState(() {});
    }
  }

  Future<void> _checkPending(_PendingUpload item) async {
    final uploadId = item.uploadId;
    if (uploadId == null || item.checking || item.cancelled) return;
    item.checking = true;
    if (mounted) setState(() {});
    try {
      final status = await widget.repository.getUploadStatus(
        uploadId: uploadId,
      );
      if (status.state == ActivityMaterialUploadState.ready &&
          status.material != null) {
        if (mounted) {
          setState(() {
            _pending.remove(item);
            _materials = [..._materials, status.material!];
          });
        }
      } else if (status.state == ActivityMaterialUploadState.rejected) {
        item.status = _PendingStatus.failed;
        item.message = _rejectionMessage(status.rejectionReason);
      }
    } catch (_) {
      item.message = 'Still processing. Check again shortly.';
    } finally {
      item.checking = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _cancel(_PendingUpload item) async {
    item.cancelled = true;
    if (mounted) setState(() => _pending.remove(item));
    await _removeReservedMaterial(item);
  }

  Future<void> _removeReservedMaterial(_PendingUpload item) async {
    final materialId = item.materialId;
    if (materialId == null) return;
    try {
      await widget.repository.remove(
        assignmentId: widget.assignmentId,
        materialId: materialId,
      );
    } catch (_) {
      // The stage expires server-side if it cannot be removed immediately.
    }
  }

  Future<void> _remove(ActivityLearningMaterial material) async {
    if (_removing.contains(material.id)) return;
    setState(() => _removing.add(material.id));
    try {
      await widget.repository.remove(
        assignmentId: widget.assignmentId,
        materialId: material.id,
      );
      if (mounted) {
        setState(
          () => _materials = _materials
              .where((item) => item.id != material.id)
              .toList(),
        );
      }
    } catch (_) {
      _showError('The material could not be removed. Please try again.');
    } finally {
      if (mounted) setState(() => _removing.remove(material.id));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    displayInfoBar(
      context,
      builder: (_, _) => InfoBar(
        title: const Text('Learning materials'),
        content: Text(message),
        severity: InfoBarSeverity.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ElixPanelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.education),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Learning materials', style: AppTheme.headingMedium),
                  Text(
                    'Optional supporting files or links for Trainees.',
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _loading ? null : _showAddMenu,
              child: const Text('Add material'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading) const ProgressRing(),
        if (_loadError != null) _ErrorRow(message: _loadError!, action: _load),
        for (final material in _materials)
          _TeacherMaterialRow(
            material: material,
            removing: _removing.contains(material.id),
            onRemove: () => _remove(material),
          ),
        for (final pending in _pending)
          _PendingMaterialRow(
            item: pending,
            onCancel: () => _cancel(pending),
            onCheck: () => _checkPending(pending),
          ),
        if (!_loading &&
            _loadError == null &&
            _materials.isEmpty &&
            _pending.isEmpty)
          Text(
            'No materials attached yet.',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
      ],
    ),
  );
}

class ActivityLearningMaterialsTraineeSection extends StatefulWidget {
  const ActivityLearningMaterialsTraineeSection({
    super.key,
    required this.assignmentId,
    required this.repository,
  });
  final String assignmentId;
  final ActivityLearningMaterialRepository repository;
  @override
  State<ActivityLearningMaterialsTraineeSection> createState() =>
      _ActivityLearningMaterialsTraineeSectionState();
}

class _ActivityLearningMaterialsTraineeSectionState
    extends State<ActivityLearningMaterialsTraineeSection> {
  List<ActivityLearningMaterial>? _materials;
  String? _error;
  String? _opening;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await widget.repository.list(
        assignmentId: widget.assignmentId,
      );
      if (mounted) {
        setState(() {
          _materials = values;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Learning materials could not be loaded.');
      }
    }
  }

  Future<void> _open(ActivityLearningMaterial material) async {
    if (_opening != null) return;
    setState(() => _opening = material.id);
    try {
      if (material.type == ActivityLearningMaterialType.link) {
        final url = material.externalUrl;
        if (url == null ||
            !url.hasAuthority ||
            url.userInfo.isNotEmpty ||
            (url.scheme != 'http' && url.scheme != 'https')) {
          throw const FormatException();
        }
        await Process.start('explorer.exe', [url.toString()]);
      } else {
        final file = await widget.repository.openFile(material);
        if (!mounted) return;
        if (material.type == ActivityLearningMaterialType.image) {
          await showDialog<void>(
            context: context,
            builder: (_) => ContentDialog(
              title: Text(material.displayName),
              content: SizedBox(
                width: 760,
                child: Image.file(file, fit: BoxFit.contain),
              ),
              actions: [
                Button(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        } else if (material.type == ActivityLearningMaterialType.video) {
          await showDialog<void>(
            context: context,
            builder: (_) =>
                _MaterialVideoDialog(title: material.displayName, file: file),
          );
        } else {
          await Process.start('explorer.exe', [file.path]);
        }
      }
    } catch (_) {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (_, _) => const InfoBar(
            title: Text('Learning materials'),
            content: Text(
              'This material is no longer available or could not be opened.',
            ),
            severity: InfoBarSeverity.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = _materials;
    if (_error != null) return _ErrorRow(message: _error!, action: _load);
    if (materials == null) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: ProgressRing(),
      );
    }
    if (materials.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Learning materials', style: AppTheme.headingMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final material in materials)
            _TraineeMaterialRow(
              material: material,
              opening: _opening == material.id,
              onOpen: () => _open(material),
            ),
        ],
      ),
    );
  }
}

class _MaterialVideoDialog extends StatefulWidget {
  const _MaterialVideoDialog({required this.title, required this.file});
  final String title;
  final File file;
  @override
  State<_MaterialVideoDialog> createState() => _MaterialVideoDialogState();
}

class _MaterialVideoDialogState extends State<_MaterialVideoDialog> {
  final _session = ElixrPlaybackSession();
  @override
  void dispose() {
    unawaited(_session.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 760,
      height: 430,
      child: ElixrVideoPlayer(
        source: Uri.file(widget.file.path),
        mirrored: false,
        session: _session,
      ),
    ),
    actions: [
      Button(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _TraineeMaterialRow extends StatelessWidget {
  const _TraineeMaterialRow({
    required this.material,
    required this.opening,
    required this.onOpen,
  });
  final ActivityLearningMaterial material;
  final bool opening;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: ElixPanelCard(
      child: Row(
        children: [
          Icon(activityLearningMaterialIcon(material.type)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${activityLearningMaterialTypeLabel(material.type)}${material.sizeBytes == null ? '' : ' · ${activityLearningMaterialSizeLabel(material.sizeBytes)}'}',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Button(
            onPressed: opening ? null : onOpen,
            child: opening
                ? const ProgressRing()
                : Text(
                    material.type == ActivityLearningMaterialType.image
                        ? 'View'
                        : material.type == ActivityLearningMaterialType.video
                        ? 'Watch'
                        : material.type == ActivityLearningMaterialType.link
                        ? 'Open link'
                        : 'Open',
                  ),
          ),
        ],
      ),
    ),
  );
}

class _TeacherMaterialRow extends StatelessWidget {
  const _TeacherMaterialRow({
    required this.material,
    required this.removing,
    required this.onRemove,
  });
  final ActivityLearningMaterial material;
  final bool removing;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      children: [
        Icon(activityLearningMaterialIcon(material.type)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Tooltip(
            message: material.displayName,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${activityLearningMaterialTypeLabel(material.type)}${material.sizeBytes == null ? '' : ' · ${activityLearningMaterialSizeLabel(material.sizeBytes)}'}',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Tooltip(
          message: 'Remove material',
          child: IconButton(
            icon: removing
                ? const ProgressRing()
                : const Icon(FluentIcons.delete),
            onPressed: removing ? null : onRemove,
          ),
        ),
      ],
    ),
  );
}

class _PendingMaterialRow extends StatelessWidget {
  const _PendingMaterialRow({
    required this.item,
    required this.onCancel,
    required this.onCheck,
  });
  final _PendingUpload item;
  final VoidCallback onCancel;
  final VoidCallback onCheck;
  @override
  Widget build(BuildContext context) {
    final label = switch (item.status) {
      _PendingStatus.uploading => 'Uploading',
      _PendingStatus.processing => 'Processing',
      _PendingStatus.failed => 'Failed',
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(activityLearningMaterialIcon(item.type)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.message ?? label,
                  style: AppTheme.caption.copyWith(
                    color: item.status == _PendingStatus.failed
                        ? AppColors.error
                        : context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (item.status == _PendingStatus.processing && item.message != null)
            Button(
              onPressed: item.checking ? null : onCheck,
              child: const Text('Check status'),
            ),
          Tooltip(
            message: item.status == _PendingStatus.failed
                ? 'Remove failed upload'
                : 'Cancel upload',
            child: IconButton(
              icon: const Icon(FluentIcons.cancel),
              onPressed: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.action});
  final String message;
  final Future<void> Function() action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          message,
          style: AppTheme.bodySecondary.copyWith(color: AppColors.error),
        ),
      ),
      Button(onPressed: action, child: const Text('Retry')),
    ],
  );
}

enum _PendingStatus { uploading, processing, failed }

class _PendingUpload {
  _PendingUpload.file(
    this.type,
    this.file,
    this.displayName,
    this.sizeBytes,
    this.contentType,
  );
  final ActivityLearningMaterialType type;
  final File? file;
  final String displayName;
  final int? sizeBytes;
  final String? contentType;
  _PendingStatus status = _PendingStatus.uploading;
  String? message;
  String? uploadId;
  String? materialId;
  bool cancelled = false;
  bool checking = false;
}

class _FileConfig {
  const _FileConfig(
    this.group,
    this.extensions,
    this.contentType,
    this.maximumBytes,
  );
  final XTypeGroup group;
  final List<String> extensions;
  final String contentType;
  final int maximumBytes;
}

_FileConfig _fileConfig(ActivityLearningMaterialType type) => switch (type) {
  ActivityLearningMaterialType.pdf => const _FileConfig(
    XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ['pdf'],
    'application/pdf',
    ActivityLearningMaterialLimits.pdfBytes,
  ),
  ActivityLearningMaterialType.image => const _FileConfig(
    XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png']),
    ['jpg', 'jpeg', 'png'],
    'image/jpeg',
    ActivityLearningMaterialLimits.imageBytes,
  ),
  ActivityLearningMaterialType.video => const _FileConfig(
    XTypeGroup(label: 'MP4 video', extensions: ['mp4']),
    ['mp4'],
    'video/mp4',
    ActivityLearningMaterialLimits.videoBytes,
  ),
  ActivityLearningMaterialType.link => throw ArgumentError.value(type),
};
String _rejectionMessage(ActivityMaterialUploadRejectionReason? reason) =>
    switch (reason) {
      ActivityMaterialUploadRejectionReason.invalidSize =>
        'File size does not match the upload.',
      ActivityMaterialUploadRejectionReason.invalidContent =>
        'The selected file is not a valid supported file.',
      ActivityMaterialUploadRejectionReason.expired =>
        'Upload expired. Please try again.',
      ActivityMaterialUploadRejectionReason.materialUnavailable =>
        'The material could not be published.',
      _ => 'The upload could not be completed.',
    };
