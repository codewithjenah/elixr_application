import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/user_name.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../data/repositories/profile_image_repository.dart';
import '../../../services/auth_service.dart';
import '../models/pending_profile_crop.dart';
import '../widgets/profile_image_crop_dialog.dart';
import '../widgets/settings_components.dart';

/// Picks a gallery image for the Account & Profile avatar. Injectable for tests.
typedef AccountProfileImagePicker = Future<XFile?> Function();

/// Opens the crop dialog (or a test double) for [sourceBytes].
typedef AccountProfileImageCropper =
    Future<PendingProfileCrop?> Function(
      BuildContext context,
      Uint8List sourceBytes,
    );

/// Merged Account & Profile Settings section.
class AccountProfileSection extends StatefulWidget {
  const AccountProfileSection({
    super.key,
    this.watchPlayer,
    this.onDirtyChanged,
    this.pickProfileImage,
    this.cropProfileImage,
  });

  /// Optional override for tests (avoids constructing Firestore).
  final Stream<LeaderboardEntry?> Function(String userId)? watchPlayer;

  /// Notified whenever [AccountProfileSectionState.isDirty] changes.
  final ValueChanged<bool>? onDirtyChanged;

  /// Optional gallery picker override (defaults to [ImagePicker]).
  final AccountProfileImagePicker? pickProfileImage;

  /// Optional crop-dialog override (defaults to [ProfileImageCropDialog.show]).
  final AccountProfileImageCropper? cropProfileImage;

  @override
  AccountProfileSectionState createState() => AccountProfileSectionState();
}

class AccountProfileSectionState extends State<AccountProfileSection>
    with WidgetsBindingObserver {
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;

  PendingProfileCrop? _pendingCrop;
  late final AuthService _authService;
  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;
  String? _equippedBorderId;

  bool _savingProfile = false;
  bool _refreshingEmail = false;
  bool _editingEmail = false;

  String _originalFirstName = '';
  String _originalMiddleName = '';
  String _originalLastName = '';
  String _originalEmail = '';

  bool _lastReportedDirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = context.read<AuthService>();
    final user = _authService.currentUser;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _middleNameController = TextEditingController(text: user?.middleName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    captureSnapshot();

    _firstNameController.addListener(_onFormChanged);
    _middleNameController.addListener(_onFormChanged);
    _lastNameController.addListener(_onFormChanged);
    _emailController.addListener(_onFormChanged);
    _authService.addListener(_onAuthServiceChanged);

    final userId = user?.id;
    if (userId != null) {
      final watch = widget.watchPlayer ?? LeaderboardRepository().watchPlayer;
      _leaderboardSub = watch(userId).listen((entry) {
        if (!mounted) return;
        setState(() => _equippedBorderId = entry?.equippedBorderId);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyDirtyChanged());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaderboardSub?.cancel();
    _authService.removeListener(_onAuthServiceChanged);
    _firstNameController.removeListener(_onFormChanged);
    _middleNameController.removeListener(_onFormChanged);
    _lastNameController.removeListener(_onFormChanged);
    _emailController.removeListener(_onFormChanged);
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
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

  bool get isDirty {
    return _firstNameController.text != _originalFirstName ||
        _middleNameController.text != _originalMiddleName ||
        _lastNameController.text != _originalLastName ||
        _emailController.text != _originalEmail ||
        _pendingCrop != null;
  }

  void captureSnapshot() {
    _originalFirstName = _firstNameController.text;
    _originalMiddleName = _middleNameController.text;
    _originalLastName = _lastNameController.text;
    _originalEmail = _emailController.text;
    _editingEmail = false;
  }

  void discardChanges() {
    _firstNameController.text = _originalFirstName;
    _middleNameController.text = _originalMiddleName;
    _lastNameController.text = _originalLastName;
    _emailController.text = _originalEmail;
    setState(() {
      _pendingCrop = null;
      _editingEmail = false;
    });
    _notifyDirtyChanged();
  }

  void _onFormChanged() {
    if (_emailController.text != _originalEmail) {
      _editingEmail = true;
    }
    if (mounted) setState(() {});
    _notifyDirtyChanged();
  }

  void _notifyDirtyChanged() {
    final dirty = isDirty;
    if (dirty == _lastReportedDirty) return;
    _lastReportedDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  void _onAuthServiceChanged() {
    if (!mounted) return;

    final authService = _authService;
    final successMessage = authService.takePendingEmailChangeSuccessMessage();
    if (successMessage != null) {
      _acceptVerifiedEmailUpdate(successMessage: successMessage);
      return;
    }

    // Unrelated auth notifications must not overwrite active user edits.
    // Only sync the email field when it still matches the last accepted
    // verified snapshot (user is not mid-edit of email).
  }

  void _acceptVerifiedEmailUpdate({String? successMessage}) {
    final confirmedEmail = _authService.currentUser?.email.trim() ?? '';
    if (confirmedEmail.isEmpty) return;

    final emailUnchangedByUser =
        _emailController.text == _originalEmail || !_editingEmail;

    if (emailUnchangedByUser ||
        _emailController.text.trim().toLowerCase() ==
            confirmedEmail.toLowerCase()) {
      _emailController.text = confirmedEmail;
      _originalEmail = confirmedEmail;
    }

    setState(() => _editingEmail = false);
    _notifyDirtyChanged();
    if (successMessage != null) {
      ElixDialog.success(context, successMessage);
    }
  }

  String _composedDisplayName() {
    return composeUserFullName(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
  }

  static String? _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }

  Future<void> _pickImage() async {
    if (_savingProfile) return;

    final pick =
        widget.pickProfileImage ??
        () => ImagePicker().pickImage(source: ImageSource.gallery);
    final picked = await pick();
    if (!mounted || picked == null) return;

    late final Uint8List sourceBytes;
    try {
      if (picked.path.isNotEmpty) {
        sourceBytes = await File(picked.path).readAsBytes();
      } else {
        sourceBytes = await picked.readAsBytes();
      }
    } catch (e) {
      if (!mounted) return;
      await ElixDialog.error(
        context,
        'Could not read the selected image. Try another file.',
      );
      return;
    }
    if (!mounted) return;
    if (sourceBytes.isEmpty) {
      await ElixDialog.error(context, 'Selected image is empty.');
      return;
    }

    final crop =
        widget.cropProfileImage ??
        (ctx, bytes) => ProfileImageCropDialog.show(ctx, sourceBytes: bytes);

    try {
      final cropped = await crop(context, sourceBytes);
      if (!mounted) return;
      if (cropped == null) return;
      setState(() => _pendingCrop = cropped);
      _notifyDirtyChanged();
    } catch (e) {
      if (!mounted) return;
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<({Uint8List bytes, String contentType})?> _resolveImageForUpload(
    AuthService authService,
  ) async {
    final pending = _pendingCrop;
    if (pending != null) {
      return (bytes: pending.bytes, contentType: pending.contentType);
    }

    // No staged crop: preserve legacy local-file migration when the account
    // still has only a machine-local path and no Cloud Storage URL.
    final currentUser = authService.currentUser;
    final hasCloudImage = (currentUser?.profilePictureUrl ?? '').isNotEmpty;
    final legacyPath = currentUser?.profilePicturePath;
    if (!hasCloudImage && legacyPath != null && legacyPath.isNotEmpty) {
      final legacyFile = File(legacyPath);
      if (legacyFile.existsSync()) {
        final contentType = _contentTypeForPath(legacyPath);
        if (contentType != null) {
          final bytes = await legacyFile.readAsBytes();
          return (bytes: bytes, contentType: contentType);
        }
      }
    }

    return null;
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;

    final nameError = validateUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );
    if (nameError != null) {
      await ElixDialog.error(context, nameError);
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      await ElixDialog.error(context, 'Email cannot be empty.');
      return;
    }

    final normalized = normalizeUserNameParts(
      firstName: _firstNameController.text,
      middleName: _middleNameController.text,
      lastName: _lastNameController.text,
    );

    final authService = context.read<AuthService>();
    if (!authService.isAuthenticated) {
      await ElixDialog.error(
        context,
        'You must be signed in to update your profile.',
      );
      return;
    }
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

    Uint8List? imageBytes;
    String? imageContentType;
    try {
      final resolved = await _resolveImageForUpload(authService);
      if (resolved != null) {
        if (resolved.bytes.length > ProfileImageRepository.maxUploadBytes) {
          if (!mounted) return;
          await ElixDialog.error(
            context,
            'Image is too large. Choose a file smaller than 5 MB.',
          );
          return;
        }
        imageBytes = resolved.bytes;
        imageContentType = resolved.contentType;
      }
    } catch (e) {
      if (!mounted) return;
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      var verificationSent = false;

      if (emailChanged) {
        verificationSent = await authService.requestEmailChange(
          newEmail: email,
          currentPassword: currentPassword!,
        );
      }

      await authService.updateProfileDetails(
        firstName: normalized.firstName,
        middleName: normalized.middleName,
        lastName: normalized.lastName,
        newProfileImageBytes: imageBytes,
        newProfileImageContentType: imageContentType,
      );

      if (!mounted) return;
      setState(() {
        _editingEmail = false;
        _pendingCrop = null;
        _firstNameController.text = normalized.firstName;
        _middleNameController.text = normalized.middleName ?? '';
        _lastNameController.text = normalized.lastName;
        if (!emailChanged) {
          _emailController.text = verifiedEmail;
        }
      });
      captureSnapshot();
      _notifyDirtyChanged();

      if (verificationSent) {
        await ElixDialog.emailVerificationSent(context, email);
      } else {
        await ElixDialog.success(context, 'Profile updated successfully.');
      }
    } catch (e) {
      if (mounted) {
        await ElixDialog.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
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
        _acceptVerifiedEmailUpdate(
          successMessage: showFeedback
              ? 'Your verified email has been updated.'
              : null,
        );
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
        await ElixDialog.error(context, message);
      }
    } catch (e) {
      if (mounted && showFeedback) {
        await ElixDialog.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
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
        await ElixDialog.success(context, 'No email change is pending.');
      }
    } catch (e) {
      if (mounted) {
        await ElixDialog.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
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

  Widget _buildNameFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 360;
        final firstNameField = SettingsFormField(
          label: 'First Name',
          controller: _firstNameController,
          icon: FluentIcons.contact,
        );
        final lastNameField = SettingsFormField(
          label: 'Last Name',
          controller: _lastNameController,
          icon: FluentIcons.contact,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: firstNameField),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: lastNameField),
                ],
              )
            else ...[
              firstNameField,
              const SizedBox(height: AppSpacing.md),
              lastNameField,
            ],
            const SizedBox(height: AppSpacing.md),
            SettingsFormField(
              label: 'Middle Name (Optional)',
              controller: _middleNameController,
              icon: FluentIcons.contact,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final stackAvatar =
        MediaQuery.sizeOf(context).width < settingsWideBreakpoint;

    final avatar = GestureDetector(
      key: const Key('account_profile_avatar_tap'),
      onTap: _savingProfile ? null : _pickImage,
      child: MouseRegion(
        cursor: _savingProfile
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Stack(
          children: [
            ProfileAvatarWidget(
              memoryPreviewBytes: _pendingCrop?.bytes,
              networkImageUrl: user?.profilePictureUrl,
              legacyLocalPath: user?.profilePicturePath,
              radius: 48,
              initials: userInitials(_composedDisplayName()),
              equippedBorderId: _equippedBorderId,
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
                  border: Border.all(color: const Color(0xFF1A1A1F), width: 2),
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
    );

    final formFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameFields(),
        const SizedBox(height: AppSpacing.md),
        SettingsFormField(
          label: 'Email',
          controller: _emailController,
          icon: FluentIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        if (context.watch<AuthService>().hasPendingEmailChange) ...[
          const SizedBox(height: AppSpacing.md),
          _buildPendingEmailNotice(),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Role',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          user?.role ?? 'Trainee',
          style: AppTheme.body.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _savingProfile || !isDirty ? null : _saveProfile,
          child: _savingProfile
              ? const ProgressRing(strokeWidth: 2)
              : const Text('Save changes'),
        ),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: SettingsGroup(
        child: stackAvatar
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(height: AppSpacing.lg),
                  formFields,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: formFields),
                ],
              ),
      ),
    );
  }
}
