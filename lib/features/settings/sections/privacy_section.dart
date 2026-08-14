import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../data/models/public_profile.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../widgets/settings_components.dart';

class PrivacySection extends StatefulWidget {
  const PrivacySection({
    super.key,
    this.publicProfileRepository,
    this.isActive = false,
    this.saveDeadline = const Duration(seconds: 12),
    this.reconciliationDeadline = const Duration(seconds: 6),
  });

  final PublicProfileRepository? publicProfileRepository;
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
      final profile = await repository.getProfileRoot(userId);
      if (!mounted) return;
      setState(() {
        _visibility = profile?.visibility ?? ProfileVisibility.private;
        _rootNeedsRepair = profile == null;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _logFailure('load', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load privacy settings.';
      });
    }
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
      child: SettingsGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              label: 'Lock profile',
              description:
                  'When locked, other players cannot see your detailed stats, '
                  'claimed achievements, completed movements, or practice history. '
                  'Your basic leaderboard identity remains visible either way. '
                  'Profile owners can see recent profile visitors.',
              checked: _visibility == ProfileVisibility.private,
              onChanged: _saving || _reconciling ? null : _setLocked,
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
    );
  }
}
