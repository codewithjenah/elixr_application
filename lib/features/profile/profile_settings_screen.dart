import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
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

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen>
    with WidgetsBindingObserver {
  late ProfileSettingsSection _section;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _pickedImagePath;
  late final AuthService _authService;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _refreshingEmail = false;
  bool _editingEmail = false;
  int _passwordFormRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _section = widget.initialSection;
    _authService = context.read<AuthService>();
    final user = _authService.currentUser;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _pickedImagePath = user?.profilePicturePath;
    _currentPasswordController.addListener(_onPasswordFieldsChanged);
    _newPasswordController.addListener(_onPasswordFieldsChanged);
    _confirmPasswordController.addListener(_onPasswordFieldsChanged);
    _authService.addListener(_onAuthServiceChanged);
    if (_section == ProfileSettingsSection.preferences) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CameraDeviceService>().refresh(forceRefresh: true);
        }
      });
    }
  }

  void _onAuthServiceChanged() {
    if (!mounted) return;

    final authService = _authService;
    final successMessage = authService.takePendingEmailChangeSuccessMessage();
    if (successMessage != null) {
      final confirmedEmail = authService.currentUser?.email.trim() ?? '';
      if (confirmedEmail.isNotEmpty) {
        _emailController.text = confirmedEmail;
      }
      setState(() => _editingEmail = false);
      _showSuccess(successMessage);
    }
  }

  void _onPasswordFieldsChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSubmitPassword {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    return current.isNotEmpty &&
        newPass.isNotEmpty &&
        confirm.isNotEmpty &&
        newPass.length >= 6 &&
        newPass == confirm;
  }

  void _openSection(ProfileSettingsSection section) {
    setState(() => _section = section);
    if (section == ProfileSettingsSection.preferences) {
      context.read<CameraDeviceService>().refresh(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthServiceChanged);
    _currentPasswordController.removeListener(_onPasswordFieldsChanged);
    _newPasswordController.removeListener(_onPasswordFieldsChanged);
    _confirmPasswordController.removeListener(_onPasswordFieldsChanged);
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authService = context.read<AuthService>();
    if (state == AppLifecycleState.resumed &&
        authService.hasPendingEmailChange &&
        !_refreshingEmail) {
      _refreshVerifiedEmail(showFeedback: false);
    }
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
    if (_savingProfile) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      _showError('Name and email cannot be empty.');
      return;
    }

    final authService = context.read<AuthService>();
    final verifiedEmail = authService.currentUser?.email.trim() ?? '';
    final emailChanged = email.toLowerCase() != verifiedEmail.toLowerCase();

    String? currentPassword;
    if (emailChanged) {
      currentPassword = await ElixDialog.promptCurrentPassword(
        context,
        title: 'Confirm email change',
        message:
            'Enter your current password to confirm changing your email address.',
      );
      if (!mounted) return;
      if (currentPassword == null) return;
    }

    setState(() => _savingProfile = true);
    try {
      var verificationSent = false;
      var currentEmailVerificationSent = false;

      if (emailChanged) {
        verificationSent = await authService.requestEmailChange(
          newEmail: email,
          currentPassword: currentPassword!,
        );
      }

      await authService.updateProfileDetails(
        fullName: name,
        profilePicturePath: _pickedImagePath,
      );

      if (!emailChanged) {
        final verified = await authService.isCurrentEmailVerified();
        if (!verified) {
          await authService.requestCurrentEmailVerification();
          currentEmailVerificationSent = true;
        }
      }

      if (!mounted) return;
      setState(() => _editingEmail = false);
      if (verificationSent) {
        await ElixDialog.emailVerificationSent(context, email);
      } else if (currentEmailVerificationSent) {
        await ElixDialog.currentEmailVerificationSent(context, email);
      } else {
        _showSuccess('Profile updated successfully.');
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _refreshVerifiedEmail({bool showFeedback = true}) async {
    if (_refreshingEmail) return;

    final authService = context.read<AuthService>();
    if (!authService.hasPendingEmailChange) return;

    setState(() => _refreshingEmail = true);
    try {
      final status = await authService.checkPendingEmailChange(
        manual: showFeedback,
      );
      if (!mounted) return;

      if (status == PendingEmailChangeRecoveryStatus.completed) {
        final confirmedEmail = authService.currentUser?.email.trim() ?? '';
        if (confirmedEmail.isNotEmpty) {
          _emailController.text = confirmedEmail;
        }
        setState(() => _editingEmail = false);
        if (showFeedback) {
          _showSuccess('Your verified email has been updated.');
        }
      } else if (showFeedback &&
          status == PendingEmailChangeRecoveryStatus.pending) {
        final confirmedEmail = authService.currentUser?.email.trim() ?? '';
        await ElixDialog.alert(
          context,
          title: 'Verification still pending',
          message:
              'Firebase still reports your current sign-in email as '
              '$confirmedEmail. Open the verification link, then try again.',
          icon: FluentIcons.mail,
        );
      } else if (showFeedback &&
          status == PendingEmailChangeRecoveryStatus.failed) {
        final message =
            authService.pendingEmailRecoveryError ??
            'Could not restore your session automatically. '
                'Sign in with your verified email.';
        _showError(message);
      }
    } catch (e) {
      if (mounted && showFeedback) {
        _showError(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _refreshingEmail = false);
    }
  }

  Future<void> _resendPendingEmailChange() async {
    final authService = context.read<AuthService>();
    final pendingEmail = authService.pendingEmail;
    if (pendingEmail == null || _savingProfile) return;

    final password = await ElixDialog.promptCurrentPassword(
      context,
      title: 'Resend verification link',
      message:
          'Enter your current password to resend the verification link to '
          '$pendingEmail.',
    );
    if (!mounted || password == null) return;

    setState(() => _savingProfile = true);
    try {
      final sent = await context.read<AuthService>().requestEmailChange(
        newEmail: pendingEmail,
        currentPassword: password,
      );
      if (!mounted) return;
      if (sent) {
        await ElixDialog.emailVerificationSent(context, pendingEmail);
      } else {
        _showSuccess('No email change is pending.');
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Widget _buildPendingEmailNotice() {
    final pendingEmail = context.watch<AuthService>().pendingEmail;
    if (pendingEmail == null) return const SizedBox.shrink();

    return InfoBar(
      title: const Text('Email verification pending'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firebase sent a verification link to $pendingEmail. '
            'Check Spam or Promotions, open the link, then tap Check status. '
            'Your current sign-in email stays active until verification completes.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              Button(
                onPressed: _savingProfile ? null : _resendPendingEmailChange,
                child: const Text('Resend link'),
              ),
              Button(
                onPressed: _refreshingEmail ? null : _refreshVerifiedEmail,
                child: _refreshingEmail
                    ? const ProgressRing(strokeWidth: 2)
                    : const Text('Check status'),
              ),
            ],
          ),
        ],
      ),
      severity: InfoBarSeverity.info,
    );
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
    final authService = context.read<AuthService>();
    try {
      await authService.updatePassword(
        currentPassword: current,
        newPassword: newPass,
      );
      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() => _passwordFormRevision++);
        ElixDialog.passwordUpdated(context);
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    FluentIcons.settings,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
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
                      const SizedBox(height: 2),
                      Text(
                        'Manage your Elixr experience',
                        style: AppTheme.caption.copyWith(
                          color: context.elixTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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
          if (context.watch<AuthService>().hasPendingEmailChange) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildPendingEmailNotice(),
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
                    if (context.watch<AuthService>().hasPendingEmailChange) ...[
                      const SizedBox(height: AppSpacing.md),
                      _buildPendingEmailNotice(),
                    ],
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
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    String? confirmStatus;
    bool? confirmSuccess;
    if (confirm.isNotEmpty) {
      if (newPass == confirm) {
        confirmStatus = 'Passwords match';
        confirmSuccess = true;
      } else {
        confirmStatus = 'Passwords do not match';
        confirmSuccess = false;
      }
    }

    return Column(
      key: ValueKey(_passwordFormRevision),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Update your password and protect access to your Elixr account.',
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SecurityIntroBanner(),
        const SizedBox(height: AppSpacing.lg),
        _SecurityFormCard(
          currentPasswordController: _currentPasswordController,
          newPasswordController: _newPasswordController,
          confirmPasswordController: _confirmPasswordController,
          newPassword: newPass,
          confirmPassword: confirm,
          confirmStatus: confirmStatus,
          confirmSuccess: confirmSuccess,
          savingPassword: _savingPassword,
          canSubmit: _canSubmitPassword,
          onSave: _savePassword,
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final selected = widget.isSelected;
    final highlighted = selected || _hovered || _focused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs / 2,
        AppSpacing.md,
        AppSpacing.xs / 2,
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.label,
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : _hovered
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 3,
                      height: 28,
                      margin: const EdgeInsets.only(right: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.16)
                            : context.elixBorder.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 15,
                        color: selected
                            ? AppColors.primary
                            : highlighted
                            ? context.elixTextPrimary
                            : context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                          fontSize: 14,
                          color: selected
                              ? context.elixTextPrimary
                              : highlighted
                              ? context.elixTextPrimary
                              : context.elixTextSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityIntroBanner extends StatelessWidget {
  const _SecurityIntroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              FluentIcons.shield_solid,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Password protection',
                  style: AppTheme.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Use a strong, unique password that you do not use on other accounts.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityFormCard extends StatelessWidget {
  const _SecurityFormCard({
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.newPassword,
    required this.confirmPassword,
    required this.confirmStatus,
    required this.confirmSuccess,
    required this.savingPassword,
    required this.canSubmit,
    required this.onSave,
  });

  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final String newPassword;
  final String confirmPassword;
  final String? confirmStatus;
  final bool? confirmSuccess;
  final bool savingPassword;
  final bool canSubmit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final hasMinLength = newPassword.length >= 6;
    final passwordsMatch =
        confirmPassword.isNotEmpty && newPassword == confirmPassword;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      FluentIcons.lock_solid,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Change password',
                          style: AppTheme.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.elixTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Enter your current password, then choose a new password.',
                          style: AppTheme.caption.copyWith(
                            color: context.elixTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _PasswordField(
                label: 'Current password',
                controller: currentPasswordController,
                icon: FluentIcons.lock,
                onSubmitted: (_) {
                  if (canSubmit && !savingPassword) onSave();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _PasswordField(
                label: 'New password',
                controller: newPasswordController,
                icon: FluentIcons.lock_solid,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _PasswordRequirement(
                    label: 'At least 6 characters',
                    met: hasMinLength,
                  ),
                  _PasswordRequirement(
                    label: 'Passwords must match',
                    met: passwordsMatch,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _PasswordField(
                label: 'Confirm new password',
                controller: confirmPasswordController,
                icon: FluentIcons.lock_solid,
                statusText: confirmStatus,
                statusIsSuccess: confirmSuccess,
                onSubmitted: (_) {
                  if (canSubmit && !savingPassword) onSave();
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: savingPassword || !canSubmit ? null : onSave,
                child: savingPassword
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ProgressRing(strokeWidth: 2),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Updating password...',
                            style: AppTheme.body.copyWith(fontSize: 14),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.accept, size: 14),
                          SizedBox(width: AppSpacing.sm),
                          Text('Update password'),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'After updating, use your new password the next time you sign in.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.icon,
    this.statusText,
    this.statusIsSuccess,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? statusText;
  final bool? statusIsSuccess;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final statusColor = widget.statusIsSuccess == true
        ? AppColors.success
        : widget.statusIsSuccess == false
        ? AppColors.warning
        : context.elixTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isDark
                  ? Colors.white.withValues(alpha: _focused ? 0.05 : 0.025)
                  : Colors.black.withValues(alpha: _focused ? 0.025 : 0.015),
              border: Border.all(
                color: _focused
                    ? AppColors.primary.withValues(alpha: 0.55)
                    : context.elixBorder.withValues(alpha: isDark ? 0.55 : 0.8),
              ),
            ),
            child: TextBox(
              controller: widget.controller,
              obscureText: _obscured,
              onSubmitted: widget.onSubmitted,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 11,
              ),
              prefix: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm + 2),
                child: Icon(
                  widget.icon,
                  color: _focused
                      ? AppColors.primary
                      : context.elixTextSecondary,
                  size: 16,
                ),
              ),
              suffix: _PasswordVisibilityButton(
                obscured: _obscured,
                onToggle: () => setState(() => _obscured = !_obscured),
              ),
              style: AppTheme.body.copyWith(
                color: context.elixTextPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ),
        if (widget.statusText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(
                widget.statusIsSuccess == true
                    ? FluentIcons.check_mark
                    : FluentIcons.info_solid,
                size: 12,
                color: statusColor,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  widget.statusText!,
                  style: AppTheme.caption.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PasswordVisibilityButton extends StatelessWidget {
  const _PasswordVisibilityButton({
    required this.obscured,
    required this.onToggle,
  });

  final bool obscured;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: obscured ? 'Show password' : 'Hide password',
      child: IconButton(
        icon: Icon(
          obscured ? FluentIcons.view : FluentIcons.hide,
          size: 15,
          color: context.elixTextSecondary,
        ),
        onPressed: onToggle,
      ),
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  const _PasswordRequirement({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met
        ? AppColors.success
        : context.elixTextSecondary.withValues(alpha: 0.85);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? FluentIcons.check_mark : FluentIcons.circle_ring,
          size: 12,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: color,
            fontWeight: met ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
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
