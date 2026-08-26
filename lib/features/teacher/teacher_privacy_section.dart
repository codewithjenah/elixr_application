import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../settings/widgets/settings_components.dart';

/// Teacher-only Privacy controls: lock profile and preview the public page.
///
/// Does not mount Trainee [PrivacySection] (session-image saving stays
/// Trainee-only). Missing roots are seeded public and existing private roots
/// are never rewritten.
class TeacherPrivacySection extends StatefulWidget {
  const TeacherPrivacySection({super.key, this.publicProfileRepository});

  final PublicProfileRepository? publicProfileRepository;

  @override
  State<TeacherPrivacySection> createState() => TeacherPrivacySectionState();
}

class TeacherPrivacySectionState extends State<TeacherPrivacySection> {
  PublicProfileRepository? _repository;
  ProfileVisibility _visibility = ProfileVisibility.private;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repository =
        widget.publicProfileRepository ??
        context.read<PublicProfileRepository>();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthService>().currentUser;
    final userId = user?.id?.trim();
    final repository = _repository;
    if (user == null ||
        userId == null ||
        userId.isEmpty ||
        repository == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await repository.seedNewAccountPublicProfile(
        userId: userId,
        displayName: user.fullName,
        profilePictureUrl: user.profilePictureUrl,
      );
      final profile = await repository.getProfileRoot(userId);
      if (!mounted) return;
      setState(() {
        _visibility = profile?.visibility ?? ProfileVisibility.private;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load privacy settings.';
      });
    }
  }

  Future<void> _setLocked(bool isLocked) async {
    final userId = context.read<AuthService>().currentUser?.id?.trim();
    final repository = _repository;
    if (userId == null || userId.isEmpty || repository == null || _saving) {
      return;
    }

    final next = isLocked
        ? ProfileVisibility.private
        : ProfileVisibility.public;
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: ProgressRing(),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: settingsMaxBodyWidth),
      child: SettingsGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsToggleRow(
              toggleKey: const Key('teacher_privacy_profile_lock_toggle'),
              label: 'Lock profile',
              description:
                  'When locked, other students and teachers cannot see your '
                  'detailed stats. Your name and photo stay visible either way.',
              checked: _visibility == ProfileVisibility.private,
              onChanged: _saving ? null : _setLocked,
            ),
            const SizedBox(height: AppSpacing.md),
            Button(
              key: const Key('teacher_view_my_public_profile'),
              onPressed: () {
                final userId = context
                    .read<AuthService>()
                    .currentUser
                    ?.id
                    ?.trim();
                if (userId == null || userId.isEmpty) return;
                context.push(AppRoutePaths.teacherProfile(userId));
              },
              child: const Text('View my public profile'),
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
