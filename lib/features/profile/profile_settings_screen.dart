import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/elix_dialog.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/camera_device_service.dart';
import '../../services/settings_service.dart';

enum ProfileSettingsSection { account, profile, security, preferences }

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    super.key,
    this.initialSection = ProfileSettingsSection.account,
  });

  final ProfileSettingsSection initialSection;

  static Future<void> show(
    BuildContext context, {
    ProfileSettingsSection initialSection = ProfileSettingsSection.account,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x99000000),
      builder: (_) => ProfileSettingsScreen(initialSection: initialSection),
    );
  }

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late ProfileSettingsSection _section;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _pickedImagePath;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _editingEmail = false;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    final user = context.read<AuthService>().currentUser;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _pickedImagePath = user?.profilePicturePath;
    if (_section == ProfileSettingsSection.preferences) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CameraDeviceService>().refresh(forceRefresh: true);
        }
      });
    }
  }

  void _openSection(ProfileSettingsSection section) {
    setState(() => _section = section);
    if (section == ProfileSettingsSection.preferences) {
      context.read<CameraDeviceService>().refresh(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImagePath = picked.path);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      _showError('Name and email cannot be empty.');
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await context.read<AuthService>().updateProfile(
        fullName: name,
        email: email,
        profilePicturePath: _pickedImagePath,
      );
      if (mounted) {
        setState(() => _editingEmail = false);
        _showSuccess('Profile updated successfully.');
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showError('All password fields are required.');
      return;
    }
    if (newPass != confirm) {
      _showError('New passwords do not match.');
      return;
    }
    if (newPass.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await context.read<AuthService>().updatePassword(
        currentPassword: current,
        newPassword: newPass,
      );
      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _showSuccess('Password updated successfully.');
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _showError(String msg) {
    ElixDialog.error(context, msg);
  }

  void _showSuccess(String msg) {
    ElixDialog.success(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width * 0.85).clamp(640.0, 900.0);
    final height = (screen.height * 0.85).clamp(480.0, 720.0);

    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: AppTheme.cardDecoration(context).copyWith(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: context.isDarkTheme ? 0.5 : 0.12,
              ),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    const sidebarWidth = 230.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: context.elixBackground,
        border: Border(
          right: BorderSide(color: context.elixBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 20,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your account',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SidebarNavItem(
            icon: FluentIcons.contact,
            label: 'Account',
            isSelected: _section == ProfileSettingsSection.account,
            onTap: () => _openSection(ProfileSettingsSection.account),
          ),
          _SidebarNavItem(
            icon: FluentIcons.photo2,
            label: 'Profile',
            isSelected: _section == ProfileSettingsSection.profile,
            onTap: () => _openSection(ProfileSettingsSection.profile),
          ),
          _SidebarNavItem(
            icon: FluentIcons.lock,
            label: 'Security',
            isSelected: _section == ProfileSettingsSection.security,
            onTap: () => _openSection(ProfileSettingsSection.security),
          ),
          _SidebarNavItem(
            icon: FluentIcons.settings,
            label: 'Preferences',
            isSelected: _section == ProfileSettingsSection.preferences,
            onTap: () => _openSection(ProfileSettingsSection.preferences),
          ),
        ],
      ),
    );
  }

  String get _sectionTitle => switch (_section) {
    ProfileSettingsSection.account => 'Account',
    ProfileSettingsSection.profile => 'Profile',
    ProfileSettingsSection.security => 'Security',
    ProfileSettingsSection.preferences => 'Preferences',
  };

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.elixBorder.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _sectionTitle,
                  style: AppTheme.headingMedium.copyWith(
                    fontSize: 22,
                    color: context.elixTextPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.cancel, size: 16),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: switch (_section) {
              ProfileSettingsSection.account => _buildAccountSection(),
              ProfileSettingsSection.profile => _buildProfileSection(),
              ProfileSettingsSection.security => _buildSecuritySection(),
              ProfileSettingsSection.preferences => _buildPreferencesSection(),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    final user = context.watch<AuthService>().currentUser;

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account details',
            style: AppTheme.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _AccountRow(
            label: 'Name',
            child: Text(
              user?.fullName ?? '',
              style: AppTheme.body.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _AccountRow(
            label: 'Email',
            child: _editingEmail
                ? SizedBox(
                    width: 280,
                    child: TextBox(
                      controller: _emailController,
                      style: AppTheme.body,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user?.email ?? '',
                        style: AppTheme.body.copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(
                        FluentIcons.chevron_right,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
            onTap: () => setState(() => _editingEmail = !_editingEmail),
          ),
          if (_editingEmail) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: _savingProfile ? null : _saveProfile,
                child: _savingProfile
                    ? const ProgressRing(strokeWidth: 2)
                    : const Text('Save email'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _AccountRow(
            label: 'Role',
            child: Text(
              user?.role ?? 'Trainee',
              style: AppTheme.body.copyWith(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Update your profile photo and display name.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Stack(
                    children: [
                      _ProfileAvatar(
                        imagePath: _pickedImagePath,
                        radius: 48,
                        initials: _initials(_nameController.text),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF1A1A1F),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            FluentIcons.camera,
                            size: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      label: 'Full Name',
                      controller: _nameController,
                      icon: FluentIcons.contact,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildField(
                      label: 'Email',
                      controller: _emailController,
                      icon: FluentIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _savingProfile ? null : _saveProfile,
                      child: _savingProfile
                          ? const ProgressRing(strokeWidth: 2)
                          : const Text('Save changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    final settings = context.watch<SettingsService>();
    final cameras = context.watch<CameraDeviceService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customize your practice experience.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SettingsCard(
          child: Column(
            children: [
              _PreferenceRow(
                label: 'Dark mode',
                description: 'Use a dark color scheme across the app.',
                child: ToggleSwitch(
                  checked: settings.darkMode,
                  onChanged: (value) => settings.setDarkMode(value),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PreferenceRow(
                label: 'Mirror camera feed',
                description:
                    'Flip the camera preview horizontally, like a mirror.',
                child: ToggleSwitch(
                  checked: settings.cameraMirrored,
                  onChanged: (value) => settings.setCameraMirrored(value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsCard(
          child: _CameraSourcePreference(settings: settings, cameras: cameras),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Change your password to keep your account secure.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SettingsCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                _buildField(
                  label: 'Current password',
                  controller: _currentPasswordController,
                  icon: FluentIcons.lock,
                  obscure: true,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildField(
                  label: 'New password',
                  controller: _newPasswordController,
                  icon: FluentIcons.lock_solid,
                  obscure: true,
                ),
                const SizedBox(height: AppSpacing.md),
                _buildField(
                  label: 'Confirm new password',
                  controller: _confirmPasswordController,
                  icon: FluentIcons.lock_solid,
                  obscure: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _savingPassword ? null : _savePassword,
                  child: _savingPassword
                      ? const ProgressRing(strokeWidth: 2)
                      : const Text('Update password'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.elixBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.elixBorder),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(icon, size: 18, color: context.elixTextSecondary),
              ),
              Expanded(
                child: TextBox(
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscure,
                  style: AppTheme.body,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm + 2,
                    horizontal: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraSourcePreference extends StatefulWidget {
  const _CameraSourcePreference({
    required this.settings,
    required this.cameras,
  });

  final SettingsService settings;
  final CameraDeviceService cameras;

  @override
  State<_CameraSourcePreference> createState() =>
      _CameraSourcePreferenceState();
}

class _CameraSourcePreferenceState extends State<_CameraSourcePreference> {
  static const _autoValue = '__auto_select__';

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
    if (migrated && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final cameras = widget.cameras;
    final selectedId = settings.selectedCameraDeviceId;
    final labels = cameras.distinguishableLabels;
    final items = <ComboBoxItem<String>>[
      const ComboBoxItem<String>(
        value: _autoValue,
        child: Text('Auto-select (Recommended)'),
      ),
      for (var i = 0; i < cameras.cameras.length; i++)
        ComboBoxItem<String>(
          value: cameras.cameras[i].deviceId,
          child: Text(labels[i]),
        ),
    ];

    // Keep a previously saved explicit camera visible even if discovery no
    // longer lists it, so the preference is not silently reset.
    final discoveryComplete =
        cameras.state == CameraDiscoveryState.success ||
        cameras.state == CameraDiscoveryState.empty;
    final selectedMissing =
        selectedId != null &&
        discoveryComplete &&
        cameras.findByDeviceId(selectedId) == null;
    if (selectedId != null && cameras.findByDeviceId(selectedId) == null) {
      final cachedName =
          settings.selectedCameraDisplayName ?? 'Selected camera';
      final label = selectedMissing ? '$cachedName — unavailable' : cachedName;
      items.add(ComboBoxItem<String>(value: selectedId, child: Text(label)));
    }

    final comboValue = selectedId ?? _autoValue;
    final statusText = _statusText(selectedId);
    final warning =
        selectedId != null &&
        cameras.state == CameraDiscoveryState.success &&
        selectedMissing;

    final autoActive = cameras.activeDeviceId != null
        ? cameras.findByDeviceId(cameras.activeDeviceId!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Camera source',
          style: AppTheme.body.copyWith(
            fontSize: 14,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the camera ELIXR will use during practice.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: ComboBox<String>(
                value: comboValue,
                items: items,
                isExpanded: true,
                onChanged: cameras.isLoading
                    ? null
                    : (value) {
                        if (value == null) return;
                        if (value == _autoValue) {
                          settings.clearCameraSelectionForAutoSelect();
                          return;
                        }
                        final match = cameras.findByDeviceId(value);
                        settings.setSelectedCameraDevice(
                          value,
                          displayName:
                              match?.displayName ??
                              settings.selectedCameraDisplayName,
                        );
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: cameras.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.refresh, size: 16),
              onPressed: cameras.isLoading
                  ? null
                  : () async {
                      await cameras.refresh(forceRefresh: true);
                      if (!mounted) return;
                      await _maybeMigrateLegacySelection();
                    },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          statusText,
          style: AppTheme.caption.copyWith(
            color: warning || cameras.state == CameraDiscoveryState.error
                ? AppColors.warning
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
            '${settings.selectedCameraDisplayName ?? 'Selected camera'} is no longer available',
            style: AppTheme.caption.copyWith(color: AppColors.warning),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Selection applies to your next practice session',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }

  String _statusText(String? selected) {
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

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.label,
    required this.description,
    required this.child,
  });

  final String label;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.body.copyWith(
                  fontSize: 14,
                  color: context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        child,
      ],
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || _hovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : _hovered
                  ? context.elixBorder.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: widget.isSelected
                  ? Border.all(color: AppColors.primary.withValues(alpha: 0.2))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? AppColors.primary.withValues(alpha: 0.18)
                        : context.elixBorder.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 15,
                    color: active
                        ? AppColors.primary
                        : context.elixTextSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Text(
                  widget.label,
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    color: active
                        ? (widget.isSelected
                              ? AppColors.primary
                              : context.elixTextPrimary)
                        : context.elixTextSecondary,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({required this.label, required this.child, this.onTap});

  final String label;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (interactive) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (interactive) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  widget.label,
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (widget.child != null) Expanded(child: widget.child!),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.elixBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.elixBorder.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imagePath,
    required this.radius,
    required this.initials,
  });

  final String? imagePath;
  final double radius;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    ImageProvider? imageProvider;

    if (imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        imageProvider = FileImage(file);
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: imageProvider != null
            ? Image(image: imageProvider, fit: BoxFit.cover)
            : _DefaultAvatar(radius: radius, initials: initials),
      ),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar({required this.radius, required this.initials});
  final double radius;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/default_profile.png',
      fit: BoxFit.cover,
      errorBuilder: (context, e, stack) => Container(
        width: radius * 2,
        height: radius * 2,
        color: AppColors.primary.withValues(alpha: 0.2),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: radius * 0.6,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileAvatarWidget extends StatelessWidget {
  const ProfileAvatarWidget({
    super.key,
    required this.imagePath,
    required this.initials,
    this.radius = 20,
  });

  final String? imagePath;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    ImageProvider? imageProvider;

    if (imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        imageProvider = FileImage(file);
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: imageProvider != null
            ? Image(image: imageProvider, fit: BoxFit.cover)
            : Image.asset(
                'assets/default_profile.png',
                fit: BoxFit.cover,
                errorBuilder: (context, e, stack) => Container(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: radius * 0.7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
