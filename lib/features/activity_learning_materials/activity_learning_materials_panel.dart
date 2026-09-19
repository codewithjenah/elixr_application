import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_form_field.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/elix_toast.dart';
import '../../core/widgets/elixr_video_player.dart';
import '../../data/models/activity_learning_material.dart';
import '../../data/repositories/activity_learning_material_repository.dart';

typedef ActivityLearningMaterialFilePicker =
    Future<XFile?> Function({required List<XTypeGroup> acceptedTypeGroups});

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
    this.filePicker = openFile,
    this.pollingInterval = const Duration(milliseconds: 1500),
    this.maximumPollCount = 20,
  });

  final String assignmentId;
  final ActivityLearningMaterialRepository repository;

  /// Kept injectable so lifecycle tests do not depend on the native picker.
  final ActivityLearningMaterialFilePicker filePicker;

  /// Server status remains authoritative; these only control bounded UI polls.
  final Duration pollingInterval;
  final int maximumPollCount;

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
    final type = await ElixDialog.show<ActivityLearningMaterialType>(
      context,
      title: 'Add material',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a supporting file or a safe web link.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final type in ActivityLearningMaterialType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ElixPrimaryButton(
                label: activityLearningMaterialTypeLabel(type),
                icon: activityLearningMaterialIcon(type),
                expanded: true,
                variant: ElixButtonVariant.outline,
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(type),
              ),
            ),
        ],
      ),
      actions: [
        ElixPrimaryButton(
          label: 'Cancel',
          expanded: false,
          variant: ElixButtonVariant.secondary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
    if (type == null || !mounted) return;
    if (type == ActivityLearningMaterialType.link) {
      await _showAddLink();
    } else {
      await _pickFile(type);
    }
  }

  Future<void> _pickFile(ActivityLearningMaterialType type) async {
    final config = activityLearningMaterialFileConfig(type);
    final selected = await widget.filePicker(
      acceptedTypeGroups: [config.group],
    );
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
    final requestId = newActivityLearningMaterialRequestId();
    String? error;
    var adding = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => ElixDialog(
          title: 'Add link',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElixTextField(
                label: 'Display name',
                controller: name,
                maxLength: 120,
              ),
              const SizedBox(height: AppSpacing.sm),
              ElixTextField(
                label: 'URL',
                controller: url,
                placeholder: 'https://example.com',
                errorText: error,
              ),
            ],
          ),
          actions: [
            ElixPrimaryButton(
              label: 'Cancel',
              expanded: false,
              variant: ElixButtonVariant.secondary,
              onPressed: () => Navigator.pop(dialogContext),
            ),
            ElixPrimaryButton(
              label: adding ? 'Adding...' : 'Add link',
              expanded: false,
              isLoading: adding,
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
                          requestId: requestId,
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
        requestId: item.requestId,
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
        attempt < widget.maximumPollCount && !item.cancelled && !_disposed;
        attempt++
      ) {
        await Future<void>.delayed(widget.pollingInterval);
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
    ElixToast.showError(context, message: message);
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
            ElixPrimaryButton(
              label: 'Add material',
              expanded: false,
              onPressed: _loading ? null : _showAddMenu,
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
  int _loadGeneration = 0;

  @override
  void didUpdateWidget(
    covariant ActivityLearningMaterialsTraineeSection oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignmentId != widget.assignmentId ||
        !identical(oldWidget.repository, widget.repository)) {
      _materials = null;
      _error = null;
      _opening = null;
      unawaited(_load());
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final repository = widget.repository;
    final assignmentId = widget.assignmentId;
    try {
      final values = await repository.list(assignmentId: assignmentId);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _materials = values;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = 'Learning materials could not be loaded.');
      }
    }
  }

  Future<void> _open(ActivityLearningMaterial material) async {
    if (_opening != null) return;
    final generation = _loadGeneration;
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
        if (!mounted || generation != _loadGeneration) return;
        await _showTraineeMaterialViewer(
          context: context,
          material: material,
          file: file,
        );
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        ElixToast.showError(
          context,
          message:
              'This material is no longer available or could not be opened.',
        );
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _opening = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final materials = _materials;
    if (_error != null) return _ErrorRow(message: _error!, action: _load);
    if (materials == null) {
      return const ElixStatusPanel(
        isLoading: true,
        icon: FluentIcons.education,
        title: 'Loading learning materials',
        message: 'Opening the files your teacher shared.',
      );
    }
    if (materials.isEmpty) return const SizedBox.shrink();
    return ElixPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ElixSectionHeader(
            heading: 'Learning materials',
            subtitle: 'Guides and examples from your teacher.',
          ),
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

class _MaterialVideoPlayer extends StatefulWidget {
  const _MaterialVideoPlayer({required this.file});
  final File file;
  @override
  State<_MaterialVideoPlayer> createState() => _MaterialVideoPlayerState();
}

class _MaterialVideoPlayerState extends State<_MaterialVideoPlayer> {
  final _session = ElixrPlaybackSession();
  @override
  void dispose() {
    unawaited(_session.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ElixrVideoPlayer(
    source: Uri.file(widget.file.path),
    mirrored: false,
    session: _session,
  );
}

Future<void> _showTraineeMaterialViewer({
  required BuildContext context,
  required ActivityLearningMaterial material,
  required File file,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final maxWidth = math.min(1040.0, math.max(320.0, viewport.width - 48));
  final maxHeight = math.min(840.0, math.max(360.0, viewport.height - 48));
  // ElixDialog owns the fixed header, body padding, and footer. Reserving this
  // space keeps every viewer action inside the desktop viewport at 720px high.
  final contentHeight = math.max(180.0, maxHeight - 216);
  final content = switch (material.type) {
    ActivityLearningMaterialType.video => _MaterialVideoPlayer(file: file),
    ActivityLearningMaterialType.image => _MaterialImageViewer(file: file),
    ActivityLearningMaterialType.pdf => _MaterialPdfViewer(file: file),
    ActivityLearningMaterialType.link => const SizedBox.shrink(),
  };
  return ElixDialog.show<void>(
    context,
    title: material.displayName,
    subtitle: switch (material.type) {
      ActivityLearningMaterialType.video => 'Video',
      ActivityLearningMaterialType.image => 'Image',
      ActivityLearningMaterialType.pdf => 'PDF document',
      ActivityLearningMaterialType.link => 'Link',
    },
    icon: activityLearningMaterialIcon(material.type),
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    scrollableContent: false,
    expandSingleAction: false,
    content: SizedBox(height: contentHeight, child: content),
    actions: [
      ElixPrimaryButton(
        label: 'Close',
        expanded: false,
        variant: ElixButtonVariant.secondary,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}

class _MaterialImageViewer extends StatelessWidget {
  const _MaterialImageViewer({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) => _MaterialViewerCanvas(
    child: Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const _MaterialViewerFailure(
        title: 'Image unavailable',
        message: 'This image could not be displayed.',
      ),
    ),
  );
}

class _MaterialPdfViewer extends StatefulWidget {
  const _MaterialPdfViewer({required this.file});

  final File file;

  @override
  State<_MaterialPdfViewer> createState() => _MaterialPdfViewerState();
}

class _MaterialPdfViewerState extends State<_MaterialPdfViewer> {
  final _controller = PdfViewerController();
  var _ready = false;

  Future<void> _resetZoom() async {
    if (!_controller.isReady) return;
    final fitScale = _controller.alternativeFitScale;
    if (fitScale != null) {
      await _controller.setZoom(Offset.zero, fitScale);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Zoom out',
              child: IconButton(
                icon: const Icon(FluentIcons.remove),
                onPressed: _ready
                    ? () => unawaited(_controller.zoomDown())
                    : null,
              ),
            ),
            Tooltip(
              message: 'Reset zoom',
              child: IconButton(
                icon: const Icon(FluentIcons.refresh),
                onPressed: _ready ? () => unawaited(_resetZoom()) : null,
              ),
            ),
            Tooltip(
              message: 'Zoom in',
              child: IconButton(
                icon: const Icon(FluentIcons.add),
                onPressed: _ready
                    ? () => unawaited(_controller.zoomUp())
                    : null,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Expanded(
        child: _MaterialViewerCanvas(
          child: PdfViewer.file(
            widget.file.path,
            controller: _controller,
            params: PdfViewerParams(
              backgroundColor: context.isHighContrast
                  ? context.elixCardSurface
                  : context.elixBackground,
              loadingBannerBuilder: (_, _, _) =>
                  const _MaterialViewerLoading(message: 'Opening PDF…'),
              errorBannerBuilder: (_, _, _, _) => const _MaterialViewerFailure(
                title: 'PDF unavailable',
                message: 'This document could not be displayed.',
              ),
              onViewerReady: (_, _) {
                if (mounted) setState(() => _ready = true);
              },
            ),
          ),
        ),
      ),
    ],
  );
}

class _MaterialViewerCanvas extends StatelessWidget {
  const _MaterialViewerCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.isHighContrast
          ? context.elixCardSurface
          : context.elixPanelSurface,
      borderRadius: BorderRadius.circular(ElixRadius.card),
      border: Border.all(color: context.elixBorder),
    ),
    child: Center(child: child),
  );
}

class _MaterialViewerLoading extends StatelessWidget {
  const _MaterialViewerLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Center(child: ElixStatusPanel(isLoading: true, message: message));
}

class _MaterialViewerFailure extends StatelessWidget {
  const _MaterialViewerFailure({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: ElixStatusPanel(
      isError: true,
      icon: FluentIcons.warning,
      title: title,
      message: message,
    ),
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
  Widget build(BuildContext context) {
    final actionLabel = material.type == ActivityLearningMaterialType.image
        ? 'View'
        : material.type == ActivityLearningMaterialType.video
        ? 'Watch'
        : material.type == ActivityLearningMaterialType.link
        ? 'Open link'
        : 'Open';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
          if (opening)
            const SizedBox(width: 22, height: 22, child: ProgressRing())
          else
            ElixPrimaryButton(
              label: actionLabel,
              expanded: false,
              dense: true,
              variant: ElixButtonVariant.outline,
              onPressed: onOpen,
            ),
        ],
      ),
    );
  }
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
            ElixPrimaryButton(
              label: 'Check status',
              variant: ElixButtonVariant.outline,
              expanded: false,
              dense: true,
              onPressed: item.checking ? null : onCheck,
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
      ElixPrimaryButton(
        label: 'Retry',
        expanded: false,
        dense: true,
        variant: ElixButtonVariant.outline,
        onPressed: () {
          unawaited(action());
        },
      ),
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
  final String requestId = newActivityLearningMaterialRequestId();
  _PendingStatus status = _PendingStatus.uploading;
  String? message;
  String? uploadId;
  String? materialId;
  bool cancelled = false;
  bool checking = false;
}

/// Shared picker configuration for the material types accepted by ELIXR.
/// This remains friendly client-side feedback; the Functions lifecycle is the
/// authoritative validation step.
class ActivityLearningMaterialFileConfig {
  const ActivityLearningMaterialFileConfig(
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

ActivityLearningMaterialFileConfig activityLearningMaterialFileConfig(
  ActivityLearningMaterialType type,
) => switch (type) {
  ActivityLearningMaterialType.pdf => const ActivityLearningMaterialFileConfig(
    XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ['pdf'],
    'application/pdf',
    ActivityLearningMaterialLimits.pdfBytes,
  ),
  ActivityLearningMaterialType.image =>
    const ActivityLearningMaterialFileConfig(
      XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png']),
      ['jpg', 'jpeg', 'png'],
      'image/jpeg',
      ActivityLearningMaterialLimits.imageBytes,
    ),
  ActivityLearningMaterialType.video =>
    const ActivityLearningMaterialFileConfig(
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
