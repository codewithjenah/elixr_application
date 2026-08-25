import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_route_paths.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/auth_service.dart';
import '../settings/sections/account_profile_section.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import '../settings/widgets/settings_legal_footer.dart';

class TeacherSettingsScreen extends StatelessWidget {
  const TeacherSettingsScreen({
    super.key,
    this.initialSection,
    this.watchPlayer,
    this.watchUserCosmetics,
    this.equipBorder,
    this.pickProfileImage,
    this.cropProfileImage,
    this.publicProfileRepository,
  });

  final SettingsSection? initialSection;

  /// Optional Account & Profile overrides for tests (avoids Firestore).
  final AccountProfileWatchPlayer? watchPlayer;
  final AccountProfileWatchCosmetics? watchUserCosmetics;
  final AccountProfileEquipBorder? equipBorder;
  final AccountProfileImagePicker? pickProfileImage;
  final AccountProfileImageCropper? cropProfileImage;
  final PublicProfileRepository? publicProfileRepository;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final profiles =
        publicProfileRepository ?? context.read<PublicProfileRepository>();

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: user == null
          ? const SizedBox.shrink()
          : SettingsScreen(
              audience: SettingsAudience.teacher,
              initialSection: initialSection ?? SettingsSection.accountProfile,
              onClose: () {
                if (context.mounted) {
                  context.go(AppRoutePaths.teacherDashboard);
                }
              },
              watchPlayer: watchPlayer,
              watchUserCosmetics: watchUserCosmetics,
              equipBorder: equipBorder,
              pickProfileImage: pickProfileImage,
              cropProfileImage: cropProfileImage,
              publicProfileRepository: profiles,
              embeddedFooter: const SettingsLegalFooter(),
            ),
    );
  }
}
