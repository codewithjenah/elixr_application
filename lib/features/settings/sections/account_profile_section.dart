import 'dart:async';
import 'dart:io';

import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/user_name.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../core/widgets/profile_avatar.dart';
import '../../../core/widgets/profile_border_frame.dart';
import '../../../data/models/achievement_claim.dart';
import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/profile_border.dart';
import '../../../data/models/user_cosmetics.dart';
import '../../../data/repositories/achievement_repository.dart';
import '../../../data/repositories/leaderboard_repository.dart';
import '../../../data/repositories/profile_image_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../models/pending_profile_crop.dart';
import '../widgets/profile_frame_selector.dart';
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

/// Watches the authenticated user's public leaderboard row.
typedef AccountProfileWatchPlayer =
    Stream<LeaderboardEntry?> Function(String userId);

/// Watches unlocked cosmetics for the authenticated user.
typedef AccountProfileWatchCosmetics =
    Stream<UserCosmetics?> Function(String userId);

/// Equips or clears a cosmetic border (`borderId` empty = unequip).
typedef AccountProfileEquipBorder =
    Future<EquipBorderResult> Function({
      required String userId,
      required String borderId,
    });

/// Wider body so the avatar customization column and form can sit side by side.
const double _accountProfileMaxBodyWidth = 960;
const double _avatarCustomizationColumnWidth = 300;
const double _avatarPreviewRadius = 56;

enum _ProfilePictureOperation { idle, uploading, removing }

/// Merged Account & Profile Settings section.
class AccountProfileSection extends StatefulWidget {
  const AccountProfileSection({
    super.key,
    this.watchPlayer,
    this.watchUserCosmetics,
    this.equipBorder,
    this.onDirtyChanged,
    this.pickProfileImage,
    this.cropProfileImage,
  });

  /// Optional override for tests (avoids constructing Firestore).
  final AccountProfileWatchPlayer? watchPlayer;

  /// Optional cosmetics stream override for tests.
  final AccountProfileWatchCosmetics? watchUserCosmetics;

  /// Optional equip/unequip override for tests.
  final AccountProfileEquipBorder? equipBorder;

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

  /// Temporary preview while an immediate profile-picture upload is in flight.
  PendingProfileCrop? _pendingCrop;
  late final AuthService _authService;
  StreamSubscription<LeaderboardEntry?>? _leaderboardSub;
  StreamSubscription<UserCosmetics?>? _cosmeticsSub;
  String? _boundUserId;
  String? _equippedBorderId;
  Set<String> _unlockedBorderIds = const {};
  bool _leaderboardMissing = false;
  String? _frameError;
  String? _busyBorderId;

  bool _savingProfile = false;
  _ProfilePictureOperation _profilePictureOperation =
      _ProfilePictureOperation.idle;
  bool _refreshingEmail = false;
  bool _editingEmail = false;

  String _originalFirstName = '';
  String _originalMiddleName = '';
  String _originalLastName = '';
  String _originalEmail = '';

  bool _lastReportedDirty = false;

  AchievementRepository? _achievementRepo;

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyDirtyChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = _authService.currentUser?.id;
    if (userId != _boundUserId) {
      _boundUserId = userId;
      _bindCosmeticStreams(userId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaderboardSub?.cancel();
    _cosmeticsSub?.cancel();
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

  void _bindCosmeticStreams(String? userId) {
    _leaderboardSub?.cancel();
    _cosmeticsSub?.cancel();
    _leaderboardSub = null;
    _cosmeticsSub = null;

    if (userId == null) {
      setState(() {
        _equippedBorderId = null;
        _unlockedBorderIds = const {};
        _leaderboardMissing = true;
        _frameError = null;
        _busyBorderId = null;
      });
      return;
    }

    final watchPlayer =
        widget.watchPlayer ?? LeaderboardRepository().watchPlayer;
    _leaderboardSub = watchPlayer(userId).listen((entry) {
      if (!mounted) return;
      setState(() {
        _equippedBorderId = entry?.equippedBorderId;
        _leaderboardMissing = entry == null;
      });
    });

    final watchCosmetics =
        widget.watchUserCosmetics ??
        ((id) {
          _achievementRepo ??= AchievementRepository(
            publicProfileRepository: context.read<PublicProfileRepository>(),
          );
          return _achievementRepo!.watchUserCosmetics(id);
        });
    _cosmeticsSub = watchCosmetics(userId).listen((cosmetics) {
      if (!mounted) return;
      setState(() {
        _unlockedBorderIds = cosmetics?.unlockedBorderIds.toSet() ?? const {};
      });
    });
  }

  Future<void> _equipOrClearBorder(String borderId) async {
    final userId = _boundUserId;
    if (userId == null || _busyBorderId != null) return;

    final trimmed = borderId.trim();
    final current = _equippedBorderId?.trim() ?? '';
    if (trimmed == current) return;

    setState(() {
      _busyBorderId = trimmed;
      _frameError = null;
    });

    try {
      final equip =
          widget.equipBorder ??
          (({required String userId, required String borderId}) {
            _achievementRepo ??= AchievementRepository(
              publicProfileRepository: context.read<PublicProfileRepository>(),
            );
            return _achievementRepo!.equipBorder(
              userId: userId,
              borderId: borderId,
            );
          });
      final result = await equip(userId: userId, borderId: trimmed);
      if (!mounted) return;

      final error = switch (result.status) {
        EquipBorderStatus.equipped || EquipBorderStatus.alreadyEquipped => null,
        EquipBorderStatus.invalidBorder => 'Unknown avatar frame.',
        EquipBorderStatus.borderLocked => 'Unlock this frame first.',
        EquipBorderStatus.cosmeticsMissing =>
          'Claim an achievement to unlock frames.',
        EquipBorderStatus.leaderboardMissing =>
          'Complete a session to create your leaderboard profile first.',
      };
      setState(() => _frameError = error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _frameError = 'Could not update avatar frame.');
    } finally {
      if (mounted) setState(() => _busyBorderId = null);
    }
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

  /// True when unsaved name/email form fields differ from the last snapshot.
  ///
  /// Profile-picture pick/crop/upload never contributes to this flag; avatar
  /// changes save immediately via [_updateProfilePicture].
  bool get isDirty {
    return _firstNameController.text != _originalFirstName ||
        _middleNameController.text != _originalMiddleName ||
        _lastNameController.text != _originalLastName ||
        _emailController.text != _originalEmail;
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
      // Keep an in-flight upload preview; otherwise clear any stale preview.
      if (_profilePictureOperation != _ProfilePictureOperation.uploading) {
        _pendingCrop = null;
      }
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

  Future<void> _pickImage() async {
    if (_savingProfile ||
        _profilePictureOperation != _ProfilePictureOperation.idle) {
      return;
    }

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
      await _updateProfilePicture(cropped);
    } catch (e) {
      if (!mounted) return;
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Uploads a cropped avatar immediately without touching name/email fields.
  ///
  /// Legacy note: name-only Save changes no longer migrates a machine-local
  /// `profilePicturePath` to Cloud Storage. Local paths still render via
  /// [ProfileAvatarWidget.legacyLocalPath] until the user uploads a new
  /// cloud avatar, which retires the legacy path.
  Future<void> _updateProfilePicture(PendingProfileCrop crop) async {
    if (_profilePictureOperation != _ProfilePictureOperation.idle) return;

    if (!_authService.isAuthenticated) {
      await ElixDialog.error(
        context,
        'You must be signed in to update your profile picture.',
      );
      return;
    }

    if (crop.bytes.isEmpty) {
      await ElixDialog.error(context, 'Selected image is empty.');
      return;
    }

    if (!ProfileImageRepository.isAllowedContentType(crop.contentType)) {
      await ElixDialog.error(
        context,
        'Unsupported image type. Choose a JPEG, PNG, or WebP image.',
      );
      return;
    }

    if (crop.bytes.length > ProfileImageRepository.maxUploadBytes) {
      await ElixDialog.error(
        context,
        'Image is too large. Choose a file smaller than 5 MB.',
      );
      return;
    }

    setState(() {
      _pendingCrop = crop;
      _profilePictureOperation = _ProfilePictureOperation.uploading;
    });

    try {
      await _authService.updateProfilePicture(
        bytes: crop.bytes,
        contentType: crop.contentType,
      );
      if (!mounted) return;
      setState(() {
        _pendingCrop = null;
        _profilePictureOperation = _ProfilePictureOperation.idle;
      });
      // Picture changes must not affect account-form dirty state.
      _notifyDirtyChanged();
      await ElixDialog.success(
        context,
        'Profile picture updated successfully.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingCrop = null;
        _profilePictureOperation = _ProfilePictureOperation.idle;
      });
      _notifyDirtyChanged();
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  bool _hasProfilePicture(User? user) {
    if (user == null) return false;
    return [
      user.profilePictureUrl,
      user.profilePictureStoragePath,
      user.profilePicturePath,
    ].any((value) => value?.trim().isNotEmpty == true);
  }

  Future<void> _removeProfilePicture() async {
    if (_savingProfile ||
        _profilePictureOperation != _ProfilePictureOperation.idle) {
      return;
    }
    if (!_hasProfilePicture(_authService.currentUser)) return;

    final confirmed = await _confirmRemoveProfilePicture(context);
    if (!mounted || !confirmed) return;

    setState(
      () => _profilePictureOperation = _ProfilePictureOperation.removing,
    );
    try {
      await _authService.removeProfilePicture();
      if (!mounted) return;
      await ElixDialog.success(context, 'Profile photo removed.');
    } catch (e) {
      if (!mounted) return;
      await ElixDialog.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(
          () => _profilePictureOperation = _ProfilePictureOperation.idle,
        );
        _notifyDirtyChanged();
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_savingProfile ||
        _profilePictureOperation != _ProfilePictureOperation.idle) {
      return;
    }

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
      );

      if (!mounted) return;
      setState(() {
        _editingEmail = false;
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

  Widget _buildAvatarPreview() {
    final user = context.watch<AuthService>().currentUser;
    final avatarBusy =
        _profilePictureOperation != _ProfilePictureOperation.idle;
    final avatarDisabled = _savingProfile || avatarBusy;
    final hasPhoto = _hasProfilePicture(user);
    final avatarDiameter = _avatarPreviewRadius * 2;
    final ornament = ProfileBorderFrame.ornamentPaddingFor(_equippedBorderId);
    final outer = avatarDiameter + ornament * 2;

    return Column(
      key: const Key('account_avatar_customization'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Avatar customization',
          style: AppTheme.headingMedium.copyWith(
            color: context.elixTextPrimary,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Tooltip(
            message: hasPhoto ? 'Change profile photo' : 'Add profile photo',
            child: Button(
              key: const Key('account_profile_avatar_tap'),
              onPressed: avatarDisabled ? null : _pickImage,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
              ),
              child: SizedBox(
                width: outer,
                height: outer,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatarWidget(
                      memoryPreviewBytes: _pendingCrop?.bytes,
                      networkImageUrl: user?.profilePictureUrl,
                      legacyLocalPath: user?.profilePicturePath,
                      radius: _avatarPreviewRadius,
                      initials: userInitials(_composedDisplayName()),
                      equippedBorderId: _equippedBorderId,
                      animateBorder: true,
                    ),
                    if (avatarBusy)
                      Container(
                        width: avatarDiameter,
                        height: avatarDiameter,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: ProgressRing(strokeWidth: 2.5),
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(
                        avatarDiameter * 0.34,
                        avatarDiameter * 0.34,
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
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
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Button(
                key: const Key('account_profile_change_photo'),
                onPressed: avatarDisabled ? null : _pickImage,
                child: Text(hasPhoto ? 'Change photo' : 'Add photo'),
              ),
              if (hasPhoto)
                Button(
                  key: const Key('account_profile_remove_photo'),
                  onPressed: avatarDisabled ? null : _removeProfilePicture,
                  style: ButtonStyle(
                    foregroundColor: const WidgetStatePropertyAll(
                      AppColors.error,
                    ),
                  ),
                  child: const Text('Remove photo'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Avatar Frame',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        _buildSelectedFrameMeta(),
        const SizedBox(height: AppSpacing.sm),
        if (_leaderboardMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Complete a practice session to create your leaderboard profile '
              'before equipping frames.',
              style: AppTheme.caption.copyWith(color: AppColors.warning),
            ),
          ),
        if (_frameError != null && !_leaderboardMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _frameError!,
              style: AppTheme.caption.copyWith(color: AppColors.error),
            ),
          ),
        ProfileFrameSelector(
          unlockedBorderIds: _unlockedBorderIds,
          equippedBorderId: _equippedBorderId,
          busyBorderId: _busyBorderId,
          actionsDisabled: _busyBorderId != null || _leaderboardMissing,
          onSelectBorder: _equipOrClearBorder,
          onClearBorder: () => _equipOrClearBorder(''),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Frames are unlocked by claiming achievements.',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedFrameMeta() {
    final id = _equippedBorderId?.trim();
    if (id == null || id.isEmpty) {
      return Text(
        'No Frame · Default',
        style: AppTheme.body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.elixTextPrimary,
        ),
      );
    }
    final border = profileBorderById(id);
    if (border == null) {
      return Text(
        'Unknown frame',
        style: AppTheme.body.copyWith(
          fontSize: 13,
          color: context.elixTextSecondary,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${border.displayName} · ${border.rarityLabel}',
          style: AppTheme.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.elixTextPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          border.description,
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final googleOnly = authService.isGoogleOnly;
    final stackLayout =
        MediaQuery.sizeOf(context).width < settingsWideBreakpoint;

    final customization = _buildAvatarPreview();

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
          enabled: !googleOnly,
        ),
        if (googleOnly) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your sign-in email is managed by Google.',
            key: const Key('google_managed_email_notice'),
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
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
      constraints: const BoxConstraints(maxWidth: _accountProfileMaxBodyWidth),
      child: SettingsGroup(
        child: stackLayout
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  customization,
                  const SizedBox(height: AppSpacing.xl),
                  formFields,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _avatarCustomizationColumnWidth,
                    child: customization,
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: formFields),
                ],
              ),
      ),
    );
  }
}

Future<bool> _confirmRemoveProfilePicture(BuildContext context) async {
  final result = await ElixDialog.show<bool>(
    context,
    title: 'Remove profile photo?',
    icon: FluentIcons.warning,
    iconColor: AppColors.error,
    headerAccentColor: AppColors.error,
    maxWidth: 420,
    barrierDismissible: false,
    content: Text(
      'Your current photo will be deleted and your initials will be shown '
      'instead. This can’t be undone.',
      style: AppTheme.body.copyWith(
        fontSize: 14,
        color: context.elixTextSecondary,
        height: 1.45,
      ),
    ),
    actions: [
      Button(
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      ElixPrimaryButton(
        label: 'Remove photo',
        expanded: false,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return result == true;
}
