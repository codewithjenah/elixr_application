import 'package:fluent_ui/fluent_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/camera_device_service.dart';
import '../../../services/settings_service.dart';
import 'settings_components.dart';

/// Shared camera-source preference used by trainee settings and Teacher Preview.
///
/// Physical identity always comes from camera discovery. A missing saved device
/// remains visible and selected until the user explicitly chooses another
/// camera or Auto-select.
class CameraSourcePreference extends StatefulWidget {
  const CameraSourcePreference({
    super.key,
    required this.settings,
    required this.cameras,
    this.enabled = true,
    this.compact = false,
  });

  final SettingsService settings;
  final CameraDeviceService cameras;
  final bool enabled;
  final bool compact;

  @override
  State<CameraSourcePreference> createState() => _CameraSourcePreferenceState();
}

class _CameraSourcePreferenceState extends State<CameraSourcePreference> {
  static const autoValue = '__auto_select__';

  bool _writing = false;
  String? _writeError;
  bool _refreshRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _refreshRequested) return;
      _refreshRequested = true;
      widget.cameras.refresh(forceRefresh: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeMigrateLegacySelection();
  }

  Future<void> _maybeMigrateLegacySelection() async {
    final settings = widget.settings;
    final cameras = widget.cameras;
    if (!settings.hasPendingLegacyCameraMigration) return;
    if (cameras.state != CameraDiscoveryState.success) return;
    if (cameras.cameras.isEmpty) return;

    final migrated = await settings.migrateLegacyCameraIndex(cameras.cameras);
    if (migrated && mounted) setState(() {});
  }

  Future<void> _onSelectionChanged(String? value) async {
    if (value == null || _writing || !widget.enabled) return;
    setState(() {
      _writing = true;
      _writeError = null;
    });

    final settings = widget.settings;
    final cameras = widget.cameras;
    late final SettingsWriteOutcome outcome;
    if (value == autoValue) {
      outcome = await settings.clearCameraSelectionForAutoSelect();
    } else {
      final match = cameras.findByDeviceId(value);
      if (match != null && !match.identityStable) {
        if (!mounted) return;
        setState(() {
          _writing = false;
          _writeError =
              'This camera does not expose a stable physical identity. '
              'Choose Auto-select.';
        });
        return;
      }
      outcome = await settings.setSelectedCameraDevice(
        value,
        displayName: match?.displayName ?? settings.selectedCameraDisplayName,
      );
    }

    if (!mounted) return;
    setState(() {
      _writing = false;
      if (outcome == SettingsWriteOutcome.writeFailed) {
        _writeError = 'Could not save camera selection. Try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final cameras = widget.cameras;
    final selectedId = settings.selectedCameraDeviceId;
    final labels = cameras.distinguishableLabels;
    final options = <(String, String)>[
      (autoValue, 'Auto-select (Recommended)'),
      for (var i = 0; i < cameras.cameras.length; i++)
        (
          cameras.cameras[i].deviceId,
          cameras.cameras[i].identityStable
              ? labels[i]
              : '${labels[i]} — Auto-select only',
        ),
    ];

    final discoveryComplete =
        cameras.state == CameraDiscoveryState.success ||
        cameras.state == CameraDiscoveryState.empty;
    final selectedMissing =
        selectedId != null &&
        discoveryComplete &&
        cameras.findByDeviceId(selectedId) == null;
    final selectedDevice = cameras.findByDeviceId(selectedId);
    final selectedUnstable =
        selectedDevice != null && !selectedDevice.identityStable;
    if (selectedId != null && cameras.findByDeviceId(selectedId) == null) {
      final cachedName =
          settings.selectedCameraDisplayName ?? 'Selected camera';
      options.add((
        selectedId,
        selectedMissing ? '$cachedName — unavailable' : cachedName,
      ));
    }

    final comboValue = selectedId ?? autoValue;
    final warning =
        selectedId != null &&
        cameras.state == CameraDiscoveryState.success &&
        (selectedMissing || selectedUnstable);
    final autoActive = cameras.activeDeviceId != null
        ? cameras.findByDeviceId(cameras.activeDeviceId!)
        : null;
    final selectionLocked = !widget.enabled || cameras.isLoading || _writing;

    return Column(
      key: const ValueKey('camera-source-preference'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camera source',
          style: AppTheme.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.elixTextPrimary,
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: 4),
          Text(
            'Choose the camera ELIXR will use during sessions.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child:
                  context.isHighContrast ||
                      shad.ShadTheme.maybeOf(context) == null
                  ? ComboBox<String>(
                      key: const ValueKey('camera-source-selector'),
                      value: comboValue,
                      items: [
                        for (final option in options)
                          ComboBoxItem<String>(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      isExpanded: true,
                      onChanged: selectionLocked ? null : _onSelectionChanged,
                    )
                  : shad.ShadSelect<String>(
                      key: ValueKey('camera-source-selector-$comboValue'),
                      initialValue: comboValue,
                      enabled: !selectionLocked,
                      minWidth: widget.compact ? 220 : 260,
                      selectedOptionBuilder: (_, value) => Text(
                        options.firstWhere((option) => option.$1 == value).$2,
                      ),
                      onChanged: _onSelectionChanged,
                      options: [
                        for (final option in options)
                          shad.ShadOption<String>(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const ValueKey('camera-source-refresh'),
              icon: cameras.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.refresh, size: 16),
              onPressed: selectionLocked
                  ? null
                  : () async {
                      await cameras.refresh(forceRefresh: true);
                      if (!mounted) return;
                      await _maybeMigrateLegacySelection();
                    },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _statusText(),
          style: AppTheme.caption.copyWith(
            color: warning || cameras.state == CameraDiscoveryState.error
                ? context.elixColors.warning
                : context.elixTextSecondary,
          ),
        ),
        if (selectedId == null &&
            cameras.state == CameraDiscoveryState.success &&
            autoActive != null) ...[
          const SizedBox(height: 4),
          Text(
            'Auto-select is currently using ${autoActive.displayName}',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        if (warning) ...[
          const SizedBox(height: 4),
          Text(
            selectedUnstable
                ? '${settings.selectedCameraDisplayName ?? 'Selected camera'} has no stable physical identity; choose Auto-select'
                : '${settings.selectedCameraDisplayName ?? 'Selected camera'} is no longer available',
            style: AppTheme.caption.copyWith(color: context.elixColors.warning),
          ),
        ],
        if (!widget.compact) ...[
          const SizedBox(height: 4),
          Text(
            'Selection applies to your next session',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        if (_writeError != null) SettingsStatusBanner(message: _writeError!),
      ],
    );
  }

  String _statusText() {
    final cameras = widget.cameras;
    switch (cameras.state) {
      case CameraDiscoveryState.idle:
      case CameraDiscoveryState.loading:
        return 'Checking cameras…';
      case CameraDiscoveryState.empty:
        return 'No usable cameras detected';
      case CameraDiscoveryState.error:
        return cameras.errorMessage ??
            'Backend unavailable — start the Python server';
      case CameraDiscoveryState.success:
        final count = cameras.cameras.length;
        return '$count camera${count == 1 ? '' : 's'} available';
    }
  }
}
