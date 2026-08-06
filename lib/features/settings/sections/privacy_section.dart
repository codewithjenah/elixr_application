import 'package:fluent_ui/fluent_ui.dart';
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
  });

  final PublicProfileRepository? publicProfileRepository;
  final bool isActive;

  @override
  State<PrivacySection> createState() => PrivacySectionState();
}

class PrivacySectionState extends State<PrivacySection> {
  PublicProfileRepository? _repository;
  ProfileVisibility _visibility = ProfileVisibility.private;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
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
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load privacy settings.';
      });
    }
  }

  Future<void> _setVisibility(bool isPublic) async {
    final userId = context.read<AuthService>().currentUser?.id;
    final repository = _repository;
    if (userId == null || repository == null || _saving) return;

    final next = isPublic
        ? ProfileVisibility.public
        : ProfileVisibility.private;
    final previous = _visibility;
    setState(() {
      _visibility = next;
      _saving = true;
      _error = null;
    });

    try {
      await repository.updateVisibility(userId: userId, visibility: next);
      if (!mounted) return;
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visibility = previous;
        _saving = false;
        _error = 'Could not save privacy setting. Please try again.';
      });
    }
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
              label: 'Public profile',
              description:
                  'When enabled, other players can see your detailed stats, '
                  'claimed achievements, completed movements, and practice history. '
                  'Your basic leaderboard identity remains visible either way. '
                  'Profile owners can see recent profile visitors.',
              checked: _visibility == ProfileVisibility.public,
              onChanged: _saving ? null : _setVisibility,
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Saving...'),
              ),
            if (_error != null) SettingsStatusBanner(message: _error!),
          ],
        ),
      ),
    );
  }
}
