import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../core/widgets/elix_primary_button.dart';
import '../../../services/auth_service.dart';
import '../widgets/settings_components.dart';

/// Security Settings: password change form.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  SecuritySectionState createState() => SecuritySectionState();
}

class SecuritySectionState extends State<SecuritySection> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _savingPassword = false;
  bool _deletingAccount = false;
  int _passwordFormRevision = 0;

  @override
  void initState() {
    super.initState();
    _currentPasswordController.addListener(_onPasswordFieldsChanged);
    _newPasswordController.addListener(_onPasswordFieldsChanged);
    _confirmPasswordController.addListener(_onPasswordFieldsChanged);
  }

  @override
  void dispose() {
    _currentPasswordController.removeListener(_onPasswordFieldsChanged);
    _newPasswordController.removeListener(_onPasswordFieldsChanged);
    _confirmPasswordController.removeListener(_onPasswordFieldsChanged);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordFieldsChanged() {
    if (mounted) setState(() {});
  }

  /// Clears password fields when the Settings surface closes.
  void clearPasswordFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    if (mounted) {
      setState(() => _passwordFormRevision++);
    }
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

  Future<void> _savePassword() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      await ElixDialog.error(context, 'All password fields are required.');
      return;
    }
    if (newPass != confirm) {
      await ElixDialog.error(context, 'New passwords do not match.');
      return;
    }
    if (newPass.length < 6) {
      await ElixDialog.error(
        context,
        'Password must be at least 6 characters.',
      );
      return;
    }

    setState(() => _savingPassword = true);
    final authService = context.read<AuthService>();
    try {
      await authService.updatePassword(
        currentPassword: current,
        newPassword: newPass,
      );
      if (!mounted) return;
      clearPasswordFields();
      await ElixDialog.passwordUpdated(context);
    } catch (e) {
      if (mounted) {
        await ElixDialog.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    final authService = context.read<AuthService>();
    final confirmed = await _DeleteAccountConfirm.show(
      context,
      email: authService.currentUser?.email ?? '',
      googleOnly: authService.isGoogleOnly,
    );
    if (confirmed == null || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await authService.deleteAccount(
        reauthentication: authService.isGoogleOnly
            ? const AccountReauthentication.google()
            : AccountReauthentication.password(confirmed.password),
        confirmationPhrase: confirmed.phrase,
      );
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (mounted) {
        await ElixDialog.error(context, _messageForDeleteAccountFailure(e));
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  /// Maps delete-account failures for the dialog.
  ///
  /// Auth/re-auth messages stay specific. Raw Firebase plugin errors are
  /// replaced with a clean erasure failure message.
  static String _messageForDeleteAccountFailure(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (_looksLikeRawFirebaseError(message)) {
      return accountErasurePurgeFailedMessage;
    }
    return message;
  }

  static bool _looksLikeRawFirebaseError(String message) {
    return message.contains('[cloud_firestore/') ||
        message.contains('[firebase_storage/') ||
        message.contains('cloud_firestore/') ||
        message.contains('firebase_storage/') ||
        (message.contains('permission-denied') &&
            (message.contains('firestore') || message.contains('storage')));
  }

  @override
  Widget build(BuildContext context) {
    final googleOnly = context.watch<AuthService>().isGoogleOnly;
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

    final hasMinLength = newPass.length >= 6;
    final passwordsMatch = confirm.isNotEmpty && newPass == confirm;

    return ConstrainedBox(
      key: ValueKey(_passwordFormRevision),
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SecurityIntroBanner(),
          const SizedBox(height: AppSpacing.lg),
          if (googleOnly)
            const InfoBar(
              key: Key('google_managed_security_notice'),
              title: Text('Sign-in is managed by Google'),
              content: Text(
                'Password changes are unavailable for this Google-only account.',
              ),
            ),
          if (googleOnly) const SizedBox(height: AppSpacing.lg),
          if (!googleOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SettingsGroup(
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
                              borderRadius: BorderRadius.circular(
                                settingsRadiusSm,
                              ),
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
                        controller: _currentPasswordController,
                        icon: FluentIcons.lock,
                        onSubmitted: (_) {
                          if (_canSubmitPassword && !_savingPassword) {
                            _savePassword();
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PasswordField(
                        label: 'New password',
                        controller: _newPasswordController,
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
                        controller: _confirmPasswordController,
                        icon: FluentIcons.lock_solid,
                        statusText: confirmStatus,
                        statusIsSuccess: confirmSuccess,
                        onSubmitted: (_) {
                          if (_canSubmitPassword && !_savingPassword) {
                            _savePassword();
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: _savingPassword || !_canSubmitPassword
                            ? null
                            : _savePassword,
                        child: _savingPassword
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
            ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SettingsGroup(
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
                            color: AppColors.error.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              settingsRadiusSm,
                            ),
                          ),
                          child: const Icon(
                            FluentIcons.delete,
                            size: 16,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm + 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delete account',
                                style: AppTheme.body.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.elixTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Permanently erase your profile, training data, and sign-in. This cannot be undone.',
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
                    Button(
                      onPressed: _deletingAccount || _savingPassword
                          ? null
                          : _confirmAndDeleteAccount,
                      style: ButtonStyle(
                        backgroundColor: WidgetStatePropertyAll(
                          AppColors.error.withValues(alpha: 0.12),
                        ),
                        foregroundColor: const WidgetStatePropertyAll(
                          AppColors.error,
                        ),
                      ),
                      child: _deletingAccount
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ProgressRing(strokeWidth: 2),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  'Deleting account...',
                                  style: AppTheme.body.copyWith(fontSize: 14),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.delete, size: 14),
                                SizedBox(width: AppSpacing.sm),
                                Text('Delete account'),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(settingsRadiusMd),
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
              borderRadius: BorderRadius.circular(settingsRadiusSm),
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
              suffix: Tooltip(
                message: _obscured ? 'Show password' : 'Hide password',
                child: IconButton(
                  icon: Icon(
                    _obscured ? FluentIcons.view : FluentIcons.hide,
                    size: 15,
                    color: context.elixTextSecondary,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
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

class _DeleteAccountConfirmation {
  const _DeleteAccountConfirmation({
    required this.password,
    required this.phrase,
  });

  final String password;
  final String phrase;
}

/// Returns the typed confirmation when the user confirms deletion.
class _DeleteAccountConfirm {
  const _DeleteAccountConfirm._();

  static Future<_DeleteAccountConfirmation?> show(
    BuildContext context, {
    required String email,
    bool googleOnly = false,
  }) async {
    final phrase = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => Center(child: _DeleteAccountDialog(email: email)),
    );
    if (phrase == null || !context.mounted) return null;

    if (googleOnly) {
      return _DeleteAccountConfirmation(password: '', phrase: phrase);
    }

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      builder: (ctx) => Center(child: _DeletePasswordDialog(email: email)),
    );
    if (password == null) return null;

    return _DeleteAccountConfirmation(password: password, phrase: phrase);
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.email});

  final String email;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteInputStatus extends StatelessWidget {
  const _DeleteInputStatus({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: AppTheme.caption.copyWith(color: color, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _erasureBullets = [
    'Profile and sign-in account',
    'Practice sessions and feedback',
    'Leaderboard XP and quest / achievement progress',
    'Public profile, cosmetics, and profile visits',
    'Profile photo in cloud storage',
  ];

  final _phraseController = TextEditingController();

  String get _requiredPhrase =>
      accountDeletionConfirmationPhraseFor(widget.email);

  @override
  void initState() {
    super.initState();
    _phraseController.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    _phraseController.removeListener(_onFieldsChanged);
    _phraseController.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    if (mounted) setState(() {});
  }

  bool get _canContinue => _phraseController.text.trim() == _requiredPhrase;

  Widget _buildPhraseStatus(BuildContext context) {
    final phrase = _phraseController.text.trim();
    if (phrase.isEmpty) {
      return _DeleteInputStatus(
        key: const ValueKey('delete-phrase-empty'),
        icon: FluentIcons.info,
        message: 'Required. Type the full phrase exactly as shown.',
        color: context.elixTextSecondary,
      );
    }
    if (phrase != _requiredPhrase) {
      return const _DeleteInputStatus(
        key: ValueKey('delete-phrase-mismatch'),
        icon: FluentIcons.status_error_full,
        message:
            "Doesn't match yet. Check for missing words, spaces, or an email typo.",
        color: AppColors.error,
      );
    }
    return const _DeleteInputStatus(
      key: ValueKey('delete-phrase-match'),
      icon: FluentIcons.check_mark,
      message: 'Phrase matches.',
      color: AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElixDialog(
      key: const ValueKey('delete-phrase-dialog'),
      title: 'Delete account permanently?',
      subtitle: 'This cannot be undone',
      icon: FluentIcons.delete,
      iconColor: AppColors.error,
      headerAccentColor: AppColors.error,
      maxWidth: 620,
      maxHeight: MediaQuery.sizeOf(context).height - (AppSpacing.lg * 2),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The following will be permanently erased:',
            style: AppTheme.body.copyWith(
              fontSize: 14,
              color: context.elixTextSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final bullet in _erasureBullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: AppTheme.body.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: AppTheme.body.copyWith(
                        fontSize: 13,
                        color: context.elixTextSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TYPE THIS EXACTLY',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  _requiredPhrase,
                  key: const ValueKey('delete-required-phrase'),
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontFamily: 'Consolas',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Confirmation phrase',
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextBox(
            key: const ValueKey('delete-phrase-field'),
            controller: _phraseController,
            placeholder: 'Type the phrase shown above',
            autocorrect: false,
            enableSuggestions: false,
            style: AppTheme.body.copyWith(
              fontFamily: 'Consolas',
              fontSize: 14,
              letterSpacing: 0.15,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 11,
            ),
          ),
          _buildPhraseStatus(context),
        ],
      ),
      actions: [
        SizedBox(
          width: 160,
          height: 52,
          child: Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        SizedBox(
          width: 160,
          height: 52,
          child: ElixPrimaryButton(
            label: 'Continue',
            dense: true,
            expanded: false,
            onPressed: _canContinue
                ? () => Navigator.of(context).pop(_phraseController.text.trim())
                : null,
          ),
        ),
      ],
    );
  }
}

class _DeletePasswordDialog extends StatefulWidget {
  const _DeletePasswordDialog({required this.email});

  final String email;

  @override
  State<_DeletePasswordDialog> createState() => _DeletePasswordDialogState();
}

class _DeletePasswordDialogState extends State<_DeletePasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _passwordController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  bool get _canDelete => _passwordController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ElixDialog(
      title: 'Confirm your identity',
      subtitle: 'Step 2 of 2 · Final security check',
      icon: FluentIcons.lock,
      iconColor: AppColors.error,
      headerAccentColor: AppColors.error,
      maxWidth: 440,
      maxHeight: 560,
      scrollableContent: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    FluentIcons.warning,
                    size: 16,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'You are permanently deleting '),
                        TextSpan(
                          text: widget.email.trim(),
                          style: TextStyle(
                            color: context.elixTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    style: AppTheme.body.copyWith(
                      fontSize: 13,
                      color: context.elixTextSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Current password',
            style: AppTheme.body.copyWith(
              color: context.elixTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextBox(
            key: const ValueKey('delete-password-field'),
            controller: _passwordController,
            placeholder: 'Enter your password',
            obscureText: _obscured,
            autofocus: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 11,
            ),
            suffix: IconButton(
              icon: Icon(
                _obscured ? FluentIcons.view : FluentIcons.hide,
                size: 15,
                color: context.elixTextSecondary,
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
            onSubmitted: _canDelete
                ? (_) => Navigator.of(context).pop(_passwordController.text)
                : null,
          ),
          _DeleteInputStatus(
            key: const ValueKey('delete-password-help'),
            icon: _passwordController.text.isEmpty
                ? FluentIcons.info
                : FluentIcons.lock,
            message: _passwordController.text.isEmpty
                ? 'Required to verify that this is your account.'
                : 'Your password will be verified securely.',
            color: context.elixTextSecondary,
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: 150,
          height: 52,
          child: Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        SizedBox(
          width: 190,
          height: 52,
          child: ElixPrimaryButton(
            label: 'Delete permanently',
            dense: true,
            expanded: false,
            onPressed: _canDelete
                ? () => Navigator.of(context).pop(_passwordController.text)
                : null,
          ),
        ),
      ],
    );
  }
}
