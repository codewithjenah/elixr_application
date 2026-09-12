import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_dialog.dart';
import '../../../data/models/public_profile.dart';
import '../../../services/session_service.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../widgets/settings_components.dart';

class PrivacySection extends StatefulWidget {
  const PrivacySection({
    super.key,
    this.publicProfileRepository,
    this.sessionService,
    this.isActive = false,
    this.saveDeadline = const Duration(seconds: 12),
    this.reconciliationDeadline = const Duration(seconds: 6),
  });

  final PublicProfileRepository? publicProfileRepository;
  final SessionService? sessionService;
  final bool isActive;
  final Duration saveDeadline;
  final Duration reconciliationDeadline;

  @override
  State<PrivacySection> createState() => PrivacySectionState();
}

class PrivacySectionState extends State<PrivacySection> {
  PublicProfileRepository? _repository;
  ProfileVisibility _visibility = ProfileVisibility.private;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  bool _reconciling = false;
  bool _rootNeedsRepair = false;
  int _operationId = 0;
  String? _error;
  bool? _evidenceEnabled;
  bool _evidenceStatusLoaded = false;
  bool _updatingEvidence = false;

  @override
  void didUpdateWidget(covariant PrivacySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_loaded) {
      _loaded = true;
      _loading = true;
      _repository = widget.publicProfileRepository ?? PublicProfileRepository();
      _load();
    }
  }

  Future<void> _load() async {
    final userId = context.read<AuthService>().currentUser?.id;
    final repository = _repository;
    if (userId == null || repository == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final service = widget.sessionService ?? context.read<SessionService>();
      final profile = await repository.getProfileRoot(userId);
      final evidenceEnabled = await service.sessionEvidenceEnabled(userId);
      if (!mounted) return;
      setState(() {
        _visibility = profile?.visibility ?? ProfileVisibility.private;
        _rootNeedsRepair = profile == null;
        _loading = false;
        _evidenceEnabled = evidenceEnabled ?? false;
        _evidenceStatusLoaded = true;
      });
    } catch (error, stackTrace) {
      _logFailure('load', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _evidenceEnabled = null;
        _evidenceStatusLoaded = false;
        _error = 'Could not load privacy settings.';
      });
    }
  }

  Future<void> _setEvidenceEnabled(bool enabled) async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null || _updatingEvidence) return;
    setState(() {
      _updatingEvidence = true;
      _error = null;
    });
    final service = widget.sessionService ?? context.read<SessionService>();
    try {
      if (enabled) {
        await service.setSessionEvidenceEnabled(userId: userId, enabled: true);
      } else {
        await service.revokeSessionEvidence(userId);
      }
      if (mounted) {
        setState(() {
          _evidenceEnabled = enabled;
          _evidenceStatusLoaded = true;
        });
      }
    } catch (error, stackTrace) {
      _logFailure('update session evidence', error, stackTrace);
      bool? authoritativeEvidenceSetting;
      try {
        authoritativeEvidenceSetting = await service.sessionEvidenceEnabled(
          userId,
        );
      } catch (reconciliationError, reconciliationStackTrace) {
        _logFailure(
          'reconcile session evidence',
          reconciliationError,
          reconciliationStackTrace,
        );
      }
      if (mounted) {
        setState(() {
          if (authoritativeEvidenceSetting != null) {
            _evidenceEnabled = authoritativeEvidenceSetting;
            _evidenceStatusLoaded = true;
          }
          _error = 'Could not update session image privacy. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _updatingEvidence = false);
    }
  }

  Future<void> _changeEvidenceSetting(bool enabled) async {
    if (enabled || _evidenceEnabled != true) {
      await _setEvidenceEnabled(enabled);
      return;
    }

    final confirmed = await ElixDialog.show<bool>(
      context,
      title: 'Delete saved movement images?',
      icon: FluentIcons.warning,
      iconColor: context.elixColors.warning,
      headerAccentColor: context.elixColors.warning,
      content: Text(
        'Turning this off stops Teachers from viewing your saved movement '
        'images and permanently deletes retained confirmed-movement images and '
        'their session references. Your session scores and feedback remain. '
        'Classroom learning progress sharing is unchanged.',
        style: AppTheme.body.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          child: const Text('Keep images'),
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
        ),
        FilledButton(
          child: const Text('Delete and turn off'),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        ),
      ],
      uniformActionSize: const Size(152, 36),
    );
    if (confirmed == true && mounted) await _setEvidenceEnabled(false);
  }

  Future<void> _setLocked(bool isLocked) async {
    final userId = context.read<AuthService>().currentUser?.id;
    final repository = _repository;
    if (userId == null || repository == null || _saving || _reconciling) {
      if (userId == null && mounted) {
        setState(() => _error = 'Sign in to change your privacy setting.');
      }
      return;
    }

    final next = isLocked
        ? ProfileVisibility.private
        : ProfileVisibility.public;
    final previous = _visibility;
    final operationId = ++_operationId;
    setState(() {
      _visibility = next;
      _saving = true;
      _error = null;
    });

    _debug('update visibility start');
    _debug('uid=$userId');
    _debug('path=public_profiles/$userId');
    _debug('target=${next.firestoreValue}');

    final write = _writeVisibility(
      repository: repository,
      userId: userId,
      visibility: next,
    );
    try {
      await write.timeout(widget.saveDeadline);
      if (!_isCurrent(operationId)) return;
      _debug('success');
      setState(() {
        _saving = false;
        _rootNeedsRepair = false;
      });
    } on TimeoutException {
      if (!_isCurrent(operationId)) return;
      _debug('timeout/pending recovery');
      setState(() {
        _saving = false;
        _reconciling = true;
        _error =
            'Saving is taking longer than usual. Checking the saved setting…';
      });
      unawaited(_observeLateCompletion(write, operationId, userId, next));
      await _reconcileUnconfirmed(
        repository: repository,
        userId: userId,
        previous: previous,
        operationId: operationId,
      );
    } catch (error, stackTrace) {
      _logFailure('update visibility', error, stackTrace);
      if (!_isCurrent(operationId)) return;
      setState(() {
        _visibility = previous;
        _saving = false;
        _error = 'Could not save privacy setting. Please try again.';
      });
    }
  }

  Future<void> _writeVisibility({
    required PublicProfileRepository repository,
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    if (_rootNeedsRepair) {
      final user = context.read<AuthService>().currentUser;
      await repository.ensurePrivacyProfileRoot(
        userId: userId,
        displayName: user?.fullName ?? 'Trainee',
        profilePictureUrl: user?.profilePictureUrl,
        role: user?.role,
      );
    }
    await repository.updateVisibility(userId: userId, visibility: visibility);
  }

  Future<void> _reconcileUnconfirmed({
    required PublicProfileRepository repository,
    required String userId,
    required ProfileVisibility previous,
    required int operationId,
  }) async {
    try {
      final profile = await repository
          .getProfileRoot(userId, forceServer: true)
          .timeout(widget.reconciliationDeadline);
      if (!_isCurrent(operationId)) return;
      setState(() {
        _visibility = profile?.visibility ?? previous;
        _rootNeedsRepair = profile == null;
        _reconciling = false;
        _error =
            'Could not confirm the privacy setting. Check your connection and retry.';
      });
    } on TimeoutException {
      if (!_isCurrent(operationId)) return;
      _debug('reconciliation unavailable: timeout');
      setState(() {
        _visibility = previous;
        _reconciling = false;
        _error =
            'Could not confirm the privacy setting. Check your connection and retry.';
      });
    } catch (error, stackTrace) {
      _logFailure('reconcile visibility', error, stackTrace);
      if (!_isCurrent(operationId)) return;
      setState(() {
        _visibility = previous;
        _reconciling = false;
        _error =
            'Could not confirm the privacy setting. Check your connection and retry.';
      });
    }
  }

  Future<void> _observeLateCompletion(
    Future<void> write,
    int operationId,
    String userId,
    ProfileVisibility target,
  ) async {
    try {
      await write;
      if (!_isCurrent(operationId)) return;
      _debug('success (after pending recovery)');
      setState(() {
        _visibility = target;
        _saving = false;
        _reconciling = false;
        _rootNeedsRepair = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      _logFailure('late update visibility', error, stackTrace);
    }
  }

  bool _isCurrent(int operationId) => mounted && operationId == _operationId;

  void _debug(String message) {
    if (kDebugMode) debugPrint('[Privacy] $message');
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    if (error is FirebaseException) {
      debugPrint(
        '[Privacy] $operation failed: ${error.code}: ${error.message}',
      );
    } else {
      debugPrint('[Privacy] $operation failed: $error');
    }
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive && !_loaded) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return const Center(child: ProgressRing());
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            showAccentBar: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile visibility',
                  style: AppTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SettingsToggleRow(
                  toggleKey: const Key('privacy_profile_lock_toggle'),
                  label: 'Lock profile',
                  description:
                      'When locked, other signed-in Trainees and Teachers cannot see '
                      'your detailed stats, claimed achievements, completed movements, '
                      'or practice history. Approved classroom Teachers can still view '
                      'classroom-authorized learning progress while your membership is '
                      'approved. Your basic leaderboard identity remains visible either '
                      'way. Profile owners can see recent profile visitors.',
                  checked: _visibility == ProfileVisibility.private,
                  onChanged: _saving || _reconciling ? null : _setLocked,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved practice images',
                  style: AppTheme.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.elixTextPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SettingsToggleRow(
                  toggleKey: const Key('privacy_evidence_toggle'),
                  label: 'Save confirmed movement images',
                  description:
                      'Controls saved movement images separately from classroom '
                      'learning progress. While this is on, Teachers with approved '
                      'classroom membership can view available saved movement images.',
                  checked: _evidenceEnabled ?? false,
                  onChanged:
                      !_evidenceStatusLoaded ||
                          _saving ||
                          _reconciling ||
                          _updatingEvidence
                      ? null
                      : _changeEvidenceSetting,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    !_evidenceStatusLoaded
                        ? 'Status unavailable - Teacher saved-image access could '
                              'not be confirmed.'
                        : _evidenceEnabled == true
                        ? 'On - Teachers with approved classroom membership can view '
                              'available saved practice images.'
                        : 'Off - Teachers cannot view saved practice images.',
                    key: const Key('privacy_evidence_status'),
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
                if (_updatingEvidence)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('Updating private session images...'),
                  ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('Saving...'),
                  ),
                if (_reconciling)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: Text('Checking saved setting...'),
                  ),
                if (_error != null) SettingsStatusBanner(message: _error!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
